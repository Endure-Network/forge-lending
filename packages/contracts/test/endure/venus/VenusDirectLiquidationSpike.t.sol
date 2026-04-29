// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.25;

import {Test} from "@forge-std/Test.sol";

import {Unitroller} from "@protocol/venus-staging/Comptroller/Unitroller.sol";
import {Diamond} from "@protocol/venus-staging/Comptroller/Diamond/Diamond.sol";
import {IDiamondCut} from "@protocol/venus-staging/Comptroller/Diamond/interfaces/IDiamondCut.sol";
import {MarketFacet} from "@protocol/venus-staging/Comptroller/Diamond/facets/MarketFacet.sol";
import {PolicyFacet} from "@protocol/venus-staging/Comptroller/Diamond/facets/PolicyFacet.sol";
import {SetterFacet} from "@protocol/venus-staging/Comptroller/Diamond/facets/SetterFacet.sol";
import {RewardFacet} from "@protocol/venus-staging/Comptroller/Diamond/facets/RewardFacet.sol";
import {ComptrollerLens} from "@protocol/venus-staging/Lens/ComptrollerLens.sol";
import {ComptrollerLensInterface} from "@protocol/venus-staging/Comptroller/ComptrollerLensInterface.sol";
import {ComptrollerInterface} from "@protocol/venus-staging/Comptroller/ComptrollerInterface.sol";

import {VBep20Immutable} from "@protocol/venus-staging/Tokens/VTokens/VBep20Immutable.sol";
import {VToken} from "@protocol/venus-staging/Tokens/VTokens/VToken.sol";
import {InterestRateModelV8} from "@protocol/venus-staging/InterestRateModels/InterestRateModelV8.sol";
import {TwoKinksInterestRateModel} from "@protocol/venus-staging/InterestRateModels/TwoKinksInterestRateModel.sol";
import {MockToken} from "@protocol/test-helpers/venus/MockToken.sol";

import {ResilientOracleInterface} from "@venusprotocol/oracle/contracts/interfaces/OracleInterface.sol";

import {MockResilientOracle} from "@protocol/endure/MockResilientOracle.sol";
import {AllowAllAccessControlManager} from "@protocol/endure/AllowAllAccessControlManager.sol";

/// @title VenusDirectLiquidationSpikeTest
/// @notice Phase 0.5 Stage A tightened spike. Closes the 5 partial gates the
///         external spike left open (lifecycle through Unitroller-routed Diamond,
///         ResilientOracle mock, full repay+redeem, LT<CF rejection, real ACM
///         interface), and preserves the 2 GREEN gates from the external spike
///         (selector registration, direct vToken liquidation with
///         liquidatorContract == address(0)).
///
///         Reference: docs/briefs/phase-0.5-venus-rebase-spec.md, sections
///         "Stage A re-verdict" and "Task 0: Tightened Stage A".
///
/// @dev Hard gates closed by each test:
///         test_DiamondRegistersRequiredCoreSelectors          → Gate 3
///         test_VBep20MarketsDeployAgainstUnitrollerProxy      → Gates 2, 5
///         test_ResilientOracleMockSatisfiesPriceReads         → Gate 4
///         test_FullLifecycleSupplyBorrowRepayRedeem           → Gate 6
///         test_DirectVTokenLiquidationWorksWhenLiquidatorContractUnset → Gate 7
///         test_SetCollateralFactorRejectsLTBelowCF            → Gate 8
///         test_DiamondRoutesLifecycleThroughUnitroller        → Gate 2 (lifecycle, not just selectors)
///         Gate 1 (Foundry compile) is implicitly proven by this file compiling.
contract VenusDirectLiquidationSpikeTest is Test {
    // ─── Diamond plumbing ─────────────────────────────────────────────────────
    Unitroller internal unitroller;
    Diamond internal diamondImpl;
    MarketFacet internal marketFacet;
    PolicyFacet internal policyFacet;
    SetterFacet internal setterFacet;
    RewardFacet internal rewardFacet;
    ComptrollerLens internal lens;

    // ─── Endure-authored mocks ────────────────────────────────────────────────
    MockResilientOracle internal oracle;
    AllowAllAccessControlManager internal acm;

    // ─── Underlyings & markets ────────────────────────────────────────────────
    MockToken internal wtao;
    MockToken internal alpha;
    VBep20Immutable internal vWTAO;
    VBep20Immutable internal vAlpha;
    TwoKinksInterestRateModel internal irm;

    // ─── Actors ───────────────────────────────────────────────────────────────
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    // ─── Constants matching spec defaults ─────────────────────────────────────
    uint256 internal constant CF_ALPHA = 0.25e18;
    uint256 internal constant LT_ALPHA = 0.35e18;
    uint256 internal constant CLOSE_FACTOR = 0.5e18;
    uint256 internal constant LIQUIDATION_INCENTIVE = 1.08e18;

    function setUp() public {
        _deployDiamondAndFacets();
        _deployMocks();
        _wireDiamondPolicy();
        _deployMarkets();
        _supportAndConfigureMarkets();
        _seedSupply();
    }

    // ─── Deployment helpers ───────────────────────────────────────────────────

    function _deployDiamondAndFacets() internal {
        unitroller = new Unitroller();
        diamondImpl = new Diamond();
        marketFacet = new MarketFacet();
        policyFacet = new PolicyFacet();
        setterFacet = new SetterFacet();
        rewardFacet = new RewardFacet();
        lens = new ComptrollerLens();

        require(unitroller._setPendingImplementation(address(diamondImpl)) == 0, "set pending impl");
        diamondImpl._become(unitroller);

        IDiamondCut.FacetCut[] memory cut = _buildFacetCut();
        IDiamondCut(address(unitroller)).diamondCut(cut);
    }

    function _deployMocks() internal {
        oracle = new MockResilientOracle();
        acm = new AllowAllAccessControlManager();
    }

    function _wireDiamondPolicy() internal {
        SetterFacet(address(unitroller))._setAccessControl(address(acm));
        SetterFacet(address(unitroller))._setComptrollerLens(ComptrollerLensInterface(address(lens)));
        SetterFacet(address(unitroller))._setPriceOracle(oracle);
        SetterFacet(address(unitroller))._setCloseFactor(CLOSE_FACTOR);
    }

    function _deployMarkets() internal {
        irm = new TwoKinksInterestRateModel({
            baseRatePerYear_: 0,
            multiplierPerYear_: 0,
            kink1_: 0.5e18,
            multiplier2PerYear_: 0,
            baseRate2PerYear_: 0,
            kink2_: 0.8e18,
            jumpMultiplierPerYear_: 0,
            blocksPerYear_: 2_628_000
        });

        wtao = new MockToken("Wrapped TAO", "WTAO", 18);
        alpha = new MockToken("Mock Alpha", "ALPHA", 18);

        vWTAO = new VBep20Immutable({
            underlying_: address(wtao),
            comptroller_: ComptrollerInterface(address(unitroller)),
            interestRateModel_: InterestRateModelV8(address(irm)),
            initialExchangeRateMantissa_: 2e18,
            name_: "Venus WTAO",
            symbol_: "vWTAO",
            decimals_: 8,
            admin_: payable(address(this))
        });

        vAlpha = new VBep20Immutable({
            underlying_: address(alpha),
            comptroller_: ComptrollerInterface(address(unitroller)),
            interestRateModel_: InterestRateModelV8(address(irm)),
            initialExchangeRateMantissa_: 2e18,
            name_: "Venus Alpha",
            symbol_: "vALPHA",
            decimals_: 8,
            admin_: payable(address(this))
        });
    }

    function _supportAndConfigureMarkets() internal {
        MarketFacet mf = MarketFacet(address(unitroller));
        SetterFacet sf = SetterFacet(address(unitroller));

        require(mf._supportMarket(VToken(address(vWTAO))) == 0, "support vWTAO");
        require(mf._supportMarket(VToken(address(vAlpha))) == 0, "support vAlpha");

        oracle.setUnderlyingPrice(address(vWTAO), 1e18);
        oracle.setUnderlyingPrice(address(vAlpha), 1e18);

        require(sf.setCollateralFactor(VToken(address(vWTAO)), 0, 0) == 0, "cf vWTAO");
        require(sf.setCollateralFactor(VToken(address(vAlpha)), CF_ALPHA, LT_ALPHA) == 0, "cf vAlpha");

        require(sf.setLiquidationIncentive(address(vAlpha), LIQUIDATION_INCENTIVE) == 0, "li vAlpha");

        sf.setIsBorrowAllowed(0, address(vWTAO), true);

        VToken[] memory markets = new VToken[](2);
        uint256[] memory supplyCaps = new uint256[](2);
        uint256[] memory borrowCaps = new uint256[](2);
        markets[0] = VToken(address(vWTAO));
        markets[1] = VToken(address(vAlpha));
        supplyCaps[0] = type(uint256).max;
        supplyCaps[1] = type(uint256).max;
        borrowCaps[0] = type(uint256).max;
        borrowCaps[1] = 0;
        sf.setMarketSupplyCaps(markets, supplyCaps);
        sf.setMarketBorrowCaps(markets, borrowCaps);
    }

    function _seedSupply() internal {
        wtao.faucet(1_000e18);
        wtao.approve(address(vWTAO), type(uint256).max);
        require(vWTAO.mint(1_000e18) == 0, "seed vWTAO");
    }

    function _buildFacetCut() internal view returns (IDiamondCut.FacetCut[] memory) {
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](4);

        cut[0] = IDiamondCut.FacetCut({
            facetAddress: address(marketFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _marketFacetSelectors()
        });
        cut[1] = IDiamondCut.FacetCut({
            facetAddress: address(setterFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _setterFacetSelectors()
        });
        cut[2] = IDiamondCut.FacetCut({
            facetAddress: address(policyFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _policyFacetSelectors()
        });
        cut[3] = IDiamondCut.FacetCut({
            facetAddress: address(rewardFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _rewardFacetSelectors()
        });

        return cut;
    }

    /// @dev Mirrors every external function on IMarketFacet so the Unitroller-routed
    ///      Diamond can serve VToken's `comptroller.isComptroller()` / `markets()` /
    ///      `liquidateCalculateSeizeTokens()` and similar runtime calls. Also
    ///      registers ComptrollerStorage public-getter selectors that ComptrollerLens
    ///      and other Diamond-routed callers need (oracle(), comptrollerLens(), etc.).
    ///      Every facet inherits ComptrollerV18Storage so the auto-generated getters
    ///      exist on each facet's bytecode; pointing the selectors at MarketFacet
    ///      is conventional and keeps the cut compact.
    function _marketFacetSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](31);
        // Logic functions
        s[0] = MarketFacet.isComptroller.selector;
        s[1] = bytes4(keccak256("liquidateCalculateSeizeTokens(address,address,uint256)"));
        s[2] = bytes4(keccak256("liquidateCalculateSeizeTokens(address,address,address,uint256)"));
        s[3] = bytes4(keccak256("liquidateVAICalculateSeizeTokens(address,uint256)"));
        s[4] = MarketFacet.checkMembership.selector;
        s[5] = MarketFacet.enterMarketBehalf.selector;
        s[6] = MarketFacet.enterMarkets.selector;
        s[7] = MarketFacet.exitMarket.selector;
        s[8] = MarketFacet._supportMarket.selector;
        s[9] = MarketFacet.supportMarket.selector;
        s[10] = MarketFacet.isMarketListed.selector;
        s[11] = MarketFacet.getAssetsIn.selector;
        s[12] = MarketFacet.getAllMarkets.selector;
        s[13] = MarketFacet.updateDelegate.selector;
        s[14] = MarketFacet.unlistMarket.selector;
        s[15] = bytes4(keccak256("markets(address)"));
        s[16] = MarketFacet.getCollateralFactor.selector;
        s[17] = MarketFacet.getLiquidationThreshold.selector;
        s[18] = MarketFacet.getLiquidationIncentive.selector;
        s[19] = MarketFacet.getEffectiveLiquidationIncentive.selector;
        s[20] = bytes4(keccak256("getEffectiveLtvFactor(address,address,uint8)"));
        // Public state-variable auto-getters (live in every facet's bytecode).
        s[21] = bytes4(keccak256("oracle()"));
        s[22] = bytes4(keccak256("comptrollerLens()"));
        s[23] = bytes4(keccak256("liquidatorContract()"));
        s[24] = bytes4(keccak256("closeFactorMantissa()"));
        s[25] = bytes4(keccak256("pauseGuardian()"));
        s[26] = bytes4(keccak256("borrowCapGuardian()"));
        s[27] = bytes4(keccak256("borrowCaps(address)"));
        s[28] = bytes4(keccak256("supplyCaps(address)"));
        s[29] = bytes4(keccak256("approvedDelegates(address,address)"));
        s[30] = bytes4(keccak256("isForcedLiquidationEnabled(address)"));
    }

    /// @dev Mirrors every external function on IPolicyFacet (allowance hooks
    ///      that VToken calls during mint/borrow/repay/liquidate/seize/transfer
    ///      plus the liquidity views that Diamond-routed callers use).
    function _policyFacetSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](16);
        s[0] = PolicyFacet.mintAllowed.selector;
        s[1] = PolicyFacet.mintVerify.selector;
        s[2] = PolicyFacet.redeemAllowed.selector;
        s[3] = PolicyFacet.redeemVerify.selector;
        s[4] = PolicyFacet.borrowAllowed.selector;
        s[5] = PolicyFacet.borrowVerify.selector;
        s[6] = PolicyFacet.repayBorrowAllowed.selector;
        s[7] = PolicyFacet.repayBorrowVerify.selector;
        s[8] = PolicyFacet.liquidateBorrowAllowed.selector;
        s[9] = PolicyFacet.liquidateBorrowVerify.selector;
        s[10] = PolicyFacet.seizeAllowed.selector;
        s[11] = PolicyFacet.seizeVerify.selector;
        s[12] = PolicyFacet.transferAllowed.selector;
        s[13] = PolicyFacet.transferVerify.selector;
        s[14] = PolicyFacet.getAccountLiquidity.selector;
        s[15] = PolicyFacet.getHypotheticalAccountLiquidity.selector;
    }

    /// @dev Mirrors every external function on ISetterFacet that the Stage A
    ///      lifecycle exercises. Excludes VAI/Prime/XVS/FlashLoan-specific
    ///      setters that the spike never calls (those will be added in Stage
    ///      B Chunk 2 when full Endure surface is wired).
    function _setterFacetSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](12);
        s[0] = SetterFacet._setPriceOracle.selector;
        s[1] = SetterFacet._setComptrollerLens.selector;
        s[2] = SetterFacet._setAccessControl.selector;
        s[3] = SetterFacet._setCloseFactor.selector;
        s[4] = bytes4(keccak256("setCollateralFactor(address,uint256,uint256)"));
        s[5] = bytes4(keccak256("setLiquidationIncentive(address,uint256)"));
        s[6] = bytes4(keccak256("setIsBorrowAllowed(uint96,address,bool)"));
        s[7] = SetterFacet.setMarketBorrowCaps.selector;
        s[8] = SetterFacet.setMarketSupplyCaps.selector;
        s[9] = SetterFacet._setLiquidatorContract.selector;
        s[10] = SetterFacet._setPauseGuardian.selector;
        s[11] = SetterFacet._setProtocolPaused.selector;
    }

    /// @dev Mirrors RewardFacet's primary entrypoints with reward state held
    ///      at zero (no XVS/Venus rewards configured). Required because
    ///      PolicyFacet's mint/borrow paths inherit XVSRewardsHelper which
    ///      may reference reward state through the Diamond.
    function _rewardFacetSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](2);
        s[0] = bytes4(keccak256("claimVenus(address)"));
        s[1] = RewardFacet.getXVSVTokenAddress.selector;
    }

    // ═══ TESTS ════════════════════════════════════════════════════════════════

    /// @notice Gate 3: Diamond resolves all required core selectors to expected facets.
    function test_DiamondRegistersRequiredCoreSelectors() public view {
        Diamond diamond = Diamond(payable(address(unitroller)));

        assertEq(
            diamond.facetAddress(MarketFacet._supportMarket.selector).facetAddress,
            address(marketFacet),
            "_supportMarket"
        );
        assertEq(
            diamond.facetAddress(MarketFacet.enterMarkets.selector).facetAddress,
            address(marketFacet),
            "enterMarkets"
        );
        assertEq(
            diamond.facetAddress(bytes4(keccak256("setCollateralFactor(address,uint256,uint256)"))).facetAddress,
            address(setterFacet),
            "setCollateralFactor"
        );
        assertEq(
            diamond.facetAddress(SetterFacet._setPriceOracle.selector).facetAddress,
            address(setterFacet),
            "_setPriceOracle"
        );
        assertEq(
            diamond.facetAddress(SetterFacet._setAccessControl.selector).facetAddress,
            address(setterFacet),
            "_setAccessControl"
        );
        assertEq(
            diamond.facetAddress(PolicyFacet.mintAllowed.selector).facetAddress, address(policyFacet), "mintAllowed"
        );
        assertEq(
            diamond.facetAddress(PolicyFacet.borrowAllowed.selector).facetAddress, address(policyFacet), "borrowAllowed"
        );
        assertEq(
            diamond.facetAddress(PolicyFacet.liquidateBorrowAllowed.selector).facetAddress,
            address(policyFacet),
            "liquidateBorrowAllowed"
        );
        assertEq(
            diamond.facetAddress(PolicyFacet.redeemAllowed.selector).facetAddress,
            address(policyFacet),
            "redeemAllowed"
        );
        assertEq(
            diamond.facetAddress(bytes4(keccak256("claimVenus(address)"))).facetAddress,
            address(rewardFacet),
            "claimVenus(address)"
        );
    }

    /// @notice Gates 2 + 5: vToken markets are deployed and supported through the Unitroller-routed Diamond,
    ///         not against ComptrollerMock. Asserts the markets resolve their comptroller pointer to the
    ///         Unitroller proxy and that they are listed in the diamond-routed comptroller's market table.
    function test_VBep20MarketsDeployAgainstUnitrollerProxy() public view {
        assertEq(address(vWTAO.comptroller()), address(unitroller), "vWTAO.comptroller != unitroller");
        assertEq(address(vAlpha.comptroller()), address(unitroller), "vAlpha.comptroller != unitroller");

        (bool isWTAOListed,,) = _getMarket(address(vWTAO));
        (bool isAlphaListed,,) = _getMarket(address(vAlpha));
        assertTrue(isWTAOListed, "vWTAO not listed");
        assertTrue(isAlphaListed, "vAlpha not listed");

        assertEq(oracle.getUnderlyingPrice(address(vWTAO)), 1e18, "vWTAO price not seeded");
        assertEq(oracle.getUnderlyingPrice(address(vAlpha)), 1e18, "vAlpha price not seeded");
    }

    /// @notice Gate 4: MockResilientOracle satisfies Venus's price-read surface
    ///         (getUnderlyingPrice + getPrice + updatePrice no-op) without reverting.
    function test_ResilientOracleMockSatisfiesPriceReads() public {
        oracle.setUnderlyingPrice(address(vWTAO), 1.5e18);
        oracle.setDirectPrice(address(wtao), 0.99e18);

        ResilientOracleInterface r = ResilientOracleInterface(address(oracle));
        assertEq(r.getUnderlyingPrice(address(vWTAO)), 1.5e18, "underlying price read mismatch");
        assertEq(r.getPrice(address(wtao)), 0.99e18, "direct price read mismatch");

        r.updatePrice(address(vWTAO));
        r.updateAssetPrice(address(wtao));
        assertEq(r.getUnderlyingPrice(address(vWTAO)), 1.5e18, "updatePrice mutated state");
        assertEq(r.getPrice(address(wtao)), 0.99e18, "updateAssetPrice mutated state");
    }

    /// @notice Gate 6: Full supply → enterMarkets → borrow → repay → redeem
    ///         lifecycle through the Unitroller-routed Diamond. The original
    ///         spike only proved supply+borrow against ComptrollerMock.
    function test_FullLifecycleSupplyBorrowRepayRedeem() public {
        uint256 supplyAmount = 100e18;
        uint256 borrowAmount = 10e18;

        vm.startPrank(alice);

        alpha.faucet(supplyAmount);
        alpha.approve(address(vAlpha), type(uint256).max);
        assertEq(vAlpha.mint(supplyAmount), 0, "mint vAlpha");

        address[] memory entered = new address[](1);
        entered[0] = address(vAlpha);
        uint256[] memory results = MarketFacet(address(unitroller)).enterMarkets(entered);
        assertEq(results[0], 0, "enterMarkets vAlpha");

        assertEq(vWTAO.borrow(borrowAmount), 0, "borrow vWTAO");
        assertEq(wtao.balanceOf(alice), borrowAmount, "alice wtao balance after borrow");

        wtao.approve(address(vWTAO), type(uint256).max);
        assertEq(vWTAO.repayBorrow(borrowAmount), 0, "repay vWTAO");
        assertEq(vWTAO.borrowBalanceStored(alice), 0, "borrow balance not zero after repay");

        uint256 vAlphaBalance = vAlpha.balanceOf(alice);
        assertGt(vAlphaBalance, 0, "alice has no vAlpha");
        assertEq(vAlpha.redeem(vAlphaBalance), 0, "redeem vAlpha");
        assertEq(vAlpha.balanceOf(alice), 0, "vAlpha balance not zero after redeem");
        assertGt(alpha.balanceOf(alice), 0, "alice received no underlying alpha after redeem");

        vm.stopPrank();
    }

    /// @notice Gate 2 (lifecycle): Same as Gate 6 but explicitly proves the
    ///         Diamond is the dispatch surface — every comptroller-side call
    ///         must succeed via the unitroller-cast facet interfaces.
    function test_DiamondRoutesLifecycleThroughUnitroller() public {
        vm.startPrank(alice);
        alpha.faucet(50e18);
        alpha.approve(address(vAlpha), type(uint256).max);
        assertEq(vAlpha.mint(50e18), 0, "mint must succeed via diamond mintAllowed");

        address[] memory entered = new address[](1);
        entered[0] = address(vAlpha);
        uint256[] memory results = MarketFacet(address(unitroller)).enterMarkets(entered);
        assertEq(results[0], 0, "enterMarkets must succeed via diamond marketFacet");

        assertEq(vWTAO.borrow(5e18), 0, "borrow must succeed via diamond borrowAllowed");
        vm.stopPrank();
    }

    /// @notice Gate 7 (preserved): Direct vToken liquidation succeeds while
    ///         liquidatorContract == address(0). PolicyFacet.liquidateBorrowAllowed
    ///         only restricts callers when liquidatorContract is set.
    function test_DirectVTokenLiquidationWorksWhenLiquidatorContractUnset() public {
        vm.startPrank(alice);
        alpha.faucet(100e18);
        alpha.approve(address(vAlpha), type(uint256).max);
        assertEq(vAlpha.mint(100e18), 0, "mint vAlpha");
        address[] memory entered = new address[](1);
        entered[0] = address(vAlpha);
        uint256[] memory results = MarketFacet(address(unitroller)).enterMarkets(entered);
        assertEq(results[0], 0, "enterMarkets vAlpha");
        assertEq(vWTAO.borrow(20e18), 0, "borrow vWTAO");
        vm.stopPrank();

        oracle.setUnderlyingPrice(address(vAlpha), 0.1e18);
        (, , uint256 shortfall) = _getAccountLiquidity(alice);
        assertGt(shortfall, 0, "alice not in shortfall after price drop");

        vm.startPrank(bob);
        wtao.faucet(50e18);
        wtao.approve(address(vWTAO), type(uint256).max);
        assertEq(
            vWTAO.liquidateBorrow(alice, 5e18, VToken(address(vAlpha))),
            0,
            "liquidateBorrow with liquidatorContract == address(0)"
        );
        vm.stopPrank();

        assertGt(vAlpha.balanceOf(bob), 0, "bob did not receive seized vAlpha");
    }

    /// @notice Gate 8: setCollateralFactor rejects LT < CF. Venus uses Compound's
    ///         soft-failure pattern (return non-zero error code, do not revert)
    ///         for this validation, so the assertion is on a non-zero return,
    ///         not on a revert. The mutation must also be a no-op: vAlpha's
    ///         existing CF/LT must remain unchanged (0.25e18 / 0.35e18).
    function test_SetCollateralFactorRejectsLTBelowCF() public {
        SetterFacet sf = SetterFacet(address(unitroller));

        uint256 oldCf = _markets_collateralFactor(address(vAlpha));
        uint256 oldLt = _markets_liquidationThreshold(address(vAlpha));
        assertEq(oldCf, CF_ALPHA, "precondition: CF");
        assertEq(oldLt, LT_ALPHA, "precondition: LT");

        uint256 err = sf.setCollateralFactor(VToken(address(vAlpha)), 0.6e18, 0.5e18);
        assertGt(err, 0, "setCollateralFactor must return non-zero error when LT < CF");

        assertEq(_markets_collateralFactor(address(vAlpha)), oldCf, "CF must not mutate");
        assertEq(_markets_liquidationThreshold(address(vAlpha)), oldLt, "LT must not mutate");
    }

    // ─── Internal helpers ─────────────────────────────────────────────────────

    /// @dev Reads core fields from the diamond's markets() view. Venus's full
    ///      return shape is (bool isListed, uint256 cf, bool isVenus, uint256 lt,
    ///      uint256 li, uint96 poolId, bool isBorrowAllowed). We surface only
    ///      what the spike asserts on (isListed, cf, lt) and discard the rest.
    function _getMarket(address vToken) internal view returns (bool isListed, uint256 cf, uint256 lt) {
        (bool ok, bytes memory data) =
            address(unitroller).staticcall(abi.encodeWithSignature("markets(address)", vToken));
        require(ok, "markets() call failed");
        (isListed, cf,, lt,,,) = abi.decode(data, (bool, uint256, bool, uint256, uint256, uint96, bool));
    }

    /// @dev Reads (errorCode, liquidity, shortfall) for an account via the
    ///      diamond's getAccountLiquidity() view.
    function _getAccountLiquidity(address account) internal view returns (uint256, uint256, uint256) {
        (bool ok, bytes memory data) =
            address(unitroller).staticcall(abi.encodeWithSignature("getAccountLiquidity(address)", account));
        require(ok, "getAccountLiquidity() call failed");
        return abi.decode(data, (uint256, uint256, uint256));
    }

    function _markets_collateralFactor(address vToken) internal view returns (uint256) {
        (, uint256 cf,) = _getMarket(vToken);
        return cf;
    }

    function _markets_liquidationThreshold(address vToken) internal view returns (uint256) {
        (,, uint256 lt) = _getMarket(vToken);
        return lt;
    }
}
