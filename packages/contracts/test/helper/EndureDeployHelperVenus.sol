// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.25;

import {Unitroller} from "@protocol/venus-staging/Comptroller/Unitroller.sol";
import {VToken} from "@protocol/venus-staging/Tokens/VTokens/VToken.sol";
import {VBep20Immutable} from "@protocol/venus-staging/Tokens/VTokens/VBep20Immutable.sol";
import {ComptrollerInterface} from "@protocol/venus-staging/Comptroller/ComptrollerInterface.sol";
import {ComptrollerLensInterface} from "@protocol/venus-staging/Comptroller/ComptrollerLensInterface.sol";
import {Diamond} from "@protocol/venus-staging/Comptroller/Diamond/Diamond.sol";
import {IDiamondCut} from "@protocol/venus-staging/Comptroller/Diamond/interfaces/IDiamondCut.sol";
import {MarketFacet} from "@protocol/venus-staging/Comptroller/Diamond/facets/MarketFacet.sol";
import {PolicyFacet} from "@protocol/venus-staging/Comptroller/Diamond/facets/PolicyFacet.sol";
import {SetterFacet} from "@protocol/venus-staging/Comptroller/Diamond/facets/SetterFacet.sol";
import {RewardFacet} from "@protocol/venus-staging/Comptroller/Diamond/facets/RewardFacet.sol";
import {ComptrollerLens} from "@protocol/venus-staging/Lens/ComptrollerLens.sol";
import {InterestRateModelV8} from "@protocol/venus-staging/InterestRateModels/InterestRateModelV8.sol";
import {TwoKinksInterestRateModel} from "@protocol/venus-staging/InterestRateModels/TwoKinksInterestRateModel.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MockResilientOracle} from "@protocol/endure/MockResilientOracle.sol";
import {AllowAllAccessControlManager} from "@protocol/endure/AllowAllAccessControlManager.sol";
import {EnduRateModelParamsVenus} from "@protocol/endure/EnduRateModelParams.sol";
import {WTAO} from "@protocol/endure/WTAO.sol";
import {MockAlpha30} from "@protocol/endure/MockAlpha30.sol";
import {MockAlpha64} from "@protocol/endure/MockAlpha64.sol";

contract EndureDeployHelperVenus {
    address internal constant DEAD = 0x000000000000000000000000000000000000dEaD;

    address public deployedUnitroller;

    struct VenusAddresses {
        address unitroller;
        address comptrollerLens;
        address accessControlManager;
        address resilientOracle;
        address marketFacet;
        address policyFacet;
        address setterFacet;
        address rewardFacet;
        address vWTAO;
        address vAlpha30;
        address vAlpha64;
        address irmWTAO;
        address irmAlpha;
        address wtao;
        address mockAlpha30;
        address mockAlpha64;
    }

    function deployAll() external returns (VenusAddresses memory addrs) {
        AllowAllAccessControlManager accessControlManager = new AllowAllAccessControlManager();
        MockResilientOracle resilientOracle = new MockResilientOracle();
        ComptrollerLens comptrollerLens = new ComptrollerLens();
        Unitroller unitroller = new Unitroller();
        Diamond diamond = new Diamond();
        MarketFacet marketFacet = new MarketFacet();
        PolicyFacet policyFacet = new PolicyFacet();
        SetterFacet setterFacet = new SetterFacet();
        RewardFacet rewardFacet = new RewardFacet();

        require(unitroller._setPendingImplementation(address(diamond)) == 0, "set pending impl");
        diamond._become(unitroller);
        Diamond(payable(address(unitroller))).diamondCut(_buildFacetCut(marketFacet, policyFacet, setterFacet, rewardFacet));

        SetterFacet liveSetter = SetterFacet(address(unitroller));
        MarketFacet liveMarket = MarketFacet(address(unitroller));

        require(
            liveSetter._setComptrollerLens(ComptrollerLensInterface(address(comptrollerLens))) == 0,
            "set comptroller lens"
        );
        require(liveSetter._setPriceOracle(resilientOracle) == 0, "set price oracle");
        require(liveSetter._setAccessControl(address(accessControlManager)) == 0, "set access control");

        addrs.wtao = address(new WTAO());
        addrs.mockAlpha30 = address(new MockAlpha30());
        addrs.mockAlpha64 = address(new MockAlpha64());

        {
            TwoKinksInterestRateModel irmWTAO = new TwoKinksInterestRateModel(
                EnduRateModelParamsVenus.WTAO_BASE_RATE_PER_YEAR,
                EnduRateModelParamsVenus.WTAO_MULTIPLIER_PER_YEAR,
                EnduRateModelParamsVenus.WTAO_KINK1,
                EnduRateModelParamsVenus.WTAO_MULTIPLIER_2_PER_YEAR,
                EnduRateModelParamsVenus.WTAO_BASE_RATE_2_PER_YEAR,
                EnduRateModelParamsVenus.WTAO_KINK2,
                EnduRateModelParamsVenus.WTAO_JUMP_MULTIPLIER_PER_YEAR,
                EnduRateModelParamsVenus.BLOCKS_PER_YEAR
            );
            addrs.irmWTAO = address(irmWTAO);
        }

        {
            TwoKinksInterestRateModel irmAlpha = new TwoKinksInterestRateModel(
                EnduRateModelParamsVenus.ALPHA_BASE_RATE_PER_YEAR,
                EnduRateModelParamsVenus.ALPHA_MULTIPLIER_PER_YEAR,
                EnduRateModelParamsVenus.ALPHA_KINK1,
                EnduRateModelParamsVenus.ALPHA_MULTIPLIER_2_PER_YEAR,
                EnduRateModelParamsVenus.ALPHA_BASE_RATE_2_PER_YEAR,
                EnduRateModelParamsVenus.ALPHA_KINK2,
                EnduRateModelParamsVenus.ALPHA_JUMP_MULTIPLIER_PER_YEAR,
                EnduRateModelParamsVenus.BLOCKS_PER_YEAR
            );
            addrs.irmAlpha = address(irmAlpha);
        }

        {
            VBep20Immutable vWTAO = new VBep20Immutable(
                addrs.wtao,
                ComptrollerInterface(address(unitroller)),
                InterestRateModelV8(addrs.irmWTAO),
                1e18,
                "Endure WTAO",
                "vWTAO",
                8,
                payable(address(this))
            );
            addrs.vWTAO = address(vWTAO);
            require(liveMarket._supportMarket(VToken(address(vWTAO))) == 0, "support vWTAO");
            resilientOracle.setUnderlyingPrice(address(vWTAO), 1e18);
        }

        {
            VBep20Immutable vAlpha30 = new VBep20Immutable(
                addrs.mockAlpha30,
                ComptrollerInterface(address(unitroller)),
                InterestRateModelV8(addrs.irmAlpha),
                1e18,
                "Endure Alpha30",
                "vALPHA30",
                8,
                payable(address(this))
            );
            addrs.vAlpha30 = address(vAlpha30);
            require(liveMarket._supportMarket(VToken(address(vAlpha30))) == 0, "support vAlpha30");
            resilientOracle.setUnderlyingPrice(address(vAlpha30), 1e18);
        }

        {
            VBep20Immutable vAlpha64 = new VBep20Immutable(
                addrs.mockAlpha64,
                ComptrollerInterface(address(unitroller)),
                InterestRateModelV8(addrs.irmAlpha),
                1e18,
                "Endure Alpha64",
                "vALPHA64",
                8,
                payable(address(this))
            );
            addrs.vAlpha64 = address(vAlpha64);
            require(liveMarket._supportMarket(VToken(address(vAlpha64))) == 0, "support vAlpha64");
            resilientOracle.setUnderlyingPrice(address(vAlpha64), 1e18);
        }

        _configurePhase3(liveSetter, addrs);
        _seedAndBurn(addrs.wtao, addrs.vWTAO, 1e18);
        _seedAndBurn(addrs.mockAlpha30, addrs.vAlpha30, 1e18);
        _seedAndBurn(addrs.mockAlpha64, addrs.vAlpha64, 1e18);

        deployedUnitroller = address(unitroller);

        addrs.unitroller = address(unitroller);
        addrs.comptrollerLens = address(comptrollerLens);
        addrs.accessControlManager = address(accessControlManager);
        addrs.resilientOracle = address(resilientOracle);
        addrs.marketFacet = address(marketFacet);
        addrs.policyFacet = address(policyFacet);
        addrs.setterFacet = address(setterFacet);
        addrs.rewardFacet = address(rewardFacet);
    }

    function enableVenusRewards(
        address xvsToken,
        address[] calldata vTokens,
        uint256[] calldata supplySpeeds,
        uint256[] calldata borrowSpeeds,
        uint256 fundingAmount
    ) external {
        require(deployedUnitroller != address(0), "not deployed");

        SetterFacet(address(deployedUnitroller))._setXVSToken(xvsToken);

        if (fundingAmount != 0) {
            require(
                IERC20(xvsToken).transferFrom(msg.sender, address(deployedUnitroller), fundingAmount),
                "xvs transfer failed"
            );
        }

        uint256 len = vTokens.length;
        VToken[] memory rewardMarkets = new VToken[](len);
        for (uint256 i; i < len; i++) {
            rewardMarkets[i] = VToken(vTokens[i]);
        }

        PolicyFacet(address(deployedUnitroller))._setVenusSpeeds(rewardMarkets, supplySpeeds, borrowSpeeds);
    }

    function _configurePhase3(SetterFacet liveSetter, VenusAddresses memory addrs) internal {
        require(liveSetter.setCollateralFactor(VToken(addrs.vWTAO), 0, 0) == 0, "cf vWTAO");
        require(liveSetter.setCollateralFactor(VToken(addrs.vAlpha30), 0.25e18, 0.35e18) == 0, "cf vAlpha30");
        require(liveSetter.setCollateralFactor(VToken(addrs.vAlpha64), 0.25e18, 0.35e18) == 0, "cf vAlpha64");

        require(liveSetter.setLiquidationIncentive(addrs.vWTAO, 1.08e18) == 0, "li vWTAO");
        require(liveSetter.setLiquidationIncentive(addrs.vAlpha30, 1.08e18) == 0, "li vAlpha30");
        require(liveSetter.setLiquidationIncentive(addrs.vAlpha64, 1.08e18) == 0, "li vAlpha64");
        require(liveSetter._setCloseFactor(0.5e18) == 0, "close factor");

        VToken[] memory borrowCapTokens = new VToken[](3);
        uint256[] memory borrowCaps = new uint256[](3);
        borrowCapTokens[0] = VToken(addrs.vWTAO);
        borrowCapTokens[1] = VToken(addrs.vAlpha30);
        borrowCapTokens[2] = VToken(addrs.vAlpha64);
        borrowCaps[0] = type(uint256).max;
        liveSetter.setMarketBorrowCaps(borrowCapTokens, borrowCaps);

        VToken[] memory supplyCapTokens = new VToken[](3);
        uint256[] memory supplyCaps = new uint256[](3);
        supplyCapTokens[0] = VToken(addrs.vWTAO);
        supplyCapTokens[1] = VToken(addrs.vAlpha30);
        supplyCapTokens[2] = VToken(addrs.vAlpha64);
        supplyCaps[0] = type(uint256).max;
        supplyCaps[1] = type(uint256).max;
        supplyCaps[2] = type(uint256).max;
        liveSetter.setMarketSupplyCaps(supplyCapTokens, supplyCaps);

        liveSetter.setIsBorrowAllowed(0, addrs.vWTAO, true);
    }

    function _seedAndBurn(address underlying, address vToken, uint256 amount) internal {
        (bool mintOk,) = underlying.call(abi.encodeWithSignature("mint(address,uint256)", address(this), amount));
        require(mintOk, "underlying mint failed");
        require(IERC20(underlying).approve(vToken, amount), "underlying approve failed");

        VBep20Immutable market = VBep20Immutable(payable(vToken));
        uint256 beforeBalance = market.balanceOf(address(this));
        require(market.mint(amount) == 0, "seed mint failed");
        uint256 minted = market.balanceOf(address(this)) - beforeBalance;
        require(minted > 0, "no seed vtokens");
        require(market.transfer(DEAD, minted), "burn transfer failed");
    }

    function _buildFacetCut(
        MarketFacet marketFacet,
        PolicyFacet policyFacet,
        SetterFacet setterFacet,
        RewardFacet rewardFacet
    ) internal pure returns (IDiamondCut.FacetCut[] memory cut) {
        cut = new IDiamondCut.FacetCut[](4);

        cut[0] = IDiamondCut.FacetCut({
            facetAddress: address(marketFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _marketFacetSelectors()
        });
        cut[1] = IDiamondCut.FacetCut({
            facetAddress: address(policyFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _policyFacetSelectors()
        });
        cut[2] = IDiamondCut.FacetCut({
            facetAddress: address(setterFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _setterFacetSelectors()
        });
        cut[3] = IDiamondCut.FacetCut({
            facetAddress: address(rewardFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _rewardFacetSelectors()
        });
    }

    function _marketFacetSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](33);
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
        s[31] = bytes4(keccak256("venusSupplySpeeds(address)"));
        s[32] = bytes4(keccak256("venusBorrowSpeeds(address)"));
    }

    function _policyFacetSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](17);
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
        s[16] = bytes4(keccak256("_setVenusSpeeds(address[],uint256[],uint256[])"));
    }

    function _setterFacetSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](13);
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
        s[12] = bytes4(keccak256("_setXVSToken(address)"));
    }

    function _rewardFacetSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](8);
        s[0] = bytes4(keccak256("claimVenus(address)"));
        s[1] = RewardFacet.getXVSVTokenAddress.selector;
        s[2] = bytes4(keccak256("claimVenus(address,address[])"));
        s[3] = bytes4(keccak256("claimVenus(address[],address[],bool,bool)"));
        s[4] = bytes4(keccak256("claimVenusAsCollateral(address)"));
        s[5] = bytes4(keccak256("_grantXVS(address,uint256)"));
        s[6] = bytes4(keccak256("seizeVenus(address[],address)"));
        s[7] = bytes4(keccak256("getXVSAddress()"));
    }
}
