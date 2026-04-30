// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.25;

import {Test} from "@forge-std/Test.sol";
import {EndureDeployHelper} from "@protocol/endure/EndureDeployHelper.sol";

import {MarketFacet} from "@protocol/Comptroller/Diamond/facets/MarketFacet.sol";
import {PolicyFacet} from "@protocol/Comptroller/Diamond/facets/PolicyFacet.sol";
import {SetterFacet} from "@protocol/Comptroller/Diamond/facets/SetterFacet.sol";
import {RewardFacet} from "@protocol/Comptroller/Diamond/facets/RewardFacet.sol";
import {Diamond} from "@protocol/Comptroller/Diamond/Diamond.sol";

contract DiamondSelectorRoutingTest is Test {
    EndureDeployHelper helper;
    EndureDeployHelper.Addresses addrs;

    function setUp() public {
        helper = new EndureDeployHelper();
        addrs = helper.deployAll();
    }

    // ─── Selector helpers ─────────────────────────────────────────────────────

    /// @dev 31 spike selectors + 3 new = 34 total
    function _marketFacetSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](34);
        // Logic functions (from spike verbatim)
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
        // Public state-variable auto-getters
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
        // New selectors (Stage B expansion + Liquidator optional path)
        s[31] = bytes4(keccak256("actionPaused(address,uint8)"));
        s[32] = bytes4(keccak256("venusSupplySpeeds(address)"));
        s[33] = bytes4(keccak256("venusBorrowSpeeds(address)"));
    }

    /// @dev 16 spike selectors + 1 new = 17 total
    function _policyFacetSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](17);
        // From spike verbatim
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
        // New selector (Stage B expansion)
        s[16] = bytes4(keccak256("_setVenusSpeeds(address[],uint256[],uint256[])"));
    }

    /// @dev 12 spike selectors + 5 new = 17 total
    function _setterFacetSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](17);
        // From spike verbatim
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
        // New selectors (Stage B expansion + VAI optional path)
        s[12] = bytes4(keccak256("_setXVSToken(address)"));
        s[13] = SetterFacet._setVAIController.selector;
        s[14] = SetterFacet._setVAIMintRate.selector;
        s[15] = SetterFacet.setMintedVAIOf.selector;
        s[16] = bytes4(keccak256("_setActionsPaused(address[],uint8[],bool)"));
    }

    /// @dev 2 spike selectors + 6 new = 8 total
    function _rewardFacetSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](8);
        // From spike verbatim
        s[0] = bytes4(keccak256("claimVenus(address)"));
        s[1] = RewardFacet.getXVSVTokenAddress.selector;
        // New selectors (Stage B expansion)
        s[2] = bytes4(keccak256("claimVenus(address,address[])"));
        s[3] = bytes4(keccak256("claimVenus(address[],address[],bool,bool)"));
        s[4] = bytes4(keccak256("claimVenusAsCollateral(address)"));
        s[5] = bytes4(keccak256("_grantXVS(address,uint256)"));
        s[6] = bytes4(keccak256("seizeVenus(address[],address)"));
        s[7] = bytes4(keccak256("getXVSAddress()"));
    }

    // ─── Tests ────────────────────────────────────────────────────────────────

    function test_TotalSelectorCount() public pure {
        uint256 total = _marketFacetSelectors().length
            + _policyFacetSelectors().length
            + _setterFacetSelectors().length
            + _rewardFacetSelectors().length;
        assertEq(total, 76, "Expected exactly 76 selectors");
    }

    function test_AllSelectorsRoutedCorrectly() public {
        Diamond diamond = Diamond(payable(addrs.unitroller));

        bytes4[] memory mSels = _marketFacetSelectors();
        for (uint256 i = 0; i < mSels.length; i++) {
            assertEq(
                diamond.facetAddress(mSels[i]).facetAddress,
                addrs.marketFacet,
                string.concat("MarketFacet selector not routed: ", vm.toString(mSels[i]))
            );
        }

        bytes4[] memory pSels = _policyFacetSelectors();
        for (uint256 i = 0; i < pSels.length; i++) {
            assertEq(
                diamond.facetAddress(pSels[i]).facetAddress,
                addrs.policyFacet,
                string.concat("PolicyFacet selector not routed: ", vm.toString(pSels[i]))
            );
        }

        bytes4[] memory sSels = _setterFacetSelectors();
        for (uint256 i = 0; i < sSels.length; i++) {
            assertEq(
                diamond.facetAddress(sSels[i]).facetAddress,
                addrs.setterFacet,
                string.concat("SetterFacet selector not routed: ", vm.toString(sSels[i]))
            );
        }

        bytes4[] memory rSels = _rewardFacetSelectors();
        for (uint256 i = 0; i < rSels.length; i++) {
            assertEq(
                diamond.facetAddress(rSels[i]).facetAddress,
                addrs.rewardFacet,
                string.concat("RewardFacet selector not routed: ", vm.toString(rSels[i]))
            );
        }
    }

    function test_LiquidateCalculateSeizeTokensBothVariants() public {
        // Finding F2: BOTH 3-arg and 4-arg variants required
        Diamond diamond = Diamond(payable(addrs.unitroller));
        bytes4 sel4 = bytes4(keccak256("liquidateCalculateSeizeTokens(address,address,address,uint256)"));
        bytes4 sel3 = bytes4(keccak256("liquidateCalculateSeizeTokens(address,address,uint256)"));
        // Both must be registered (will revert if not wired correctly after T9 makes test GREEN)
        // In RED state, these assertions fail because helper doesn't exist
        assertTrue(diamond.facetAddress(sel4).facetAddress != address(0), "4-arg liquidate not routed");
        assertTrue(diamond.facetAddress(sel3).facetAddress != address(0), "3-arg liquidate not routed");
    }
}
