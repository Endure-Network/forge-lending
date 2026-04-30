// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.25;

import {Test} from "@forge-std/Test.sol";
import {EndureDeployHelper} from "@protocol/endure/EndureDeployHelper.sol";
import {Liquidator} from "@protocol/Liquidator/Liquidator.sol";
import {IVToken} from "@protocol/InterfacesV8.sol";
import {MarketFacet} from "@protocol/Comptroller/Diamond/facets/MarketFacet.sol";
import {MockAlpha30} from "@protocol/endure/MockAlpha30.sol";
import {MockResilientOracle} from "@protocol/endure/MockResilientOracle.sol";
import {VBep20Immutable} from "@protocol/Tokens/VTokens/VBep20Immutable.sol";
import {WTAO} from "@protocol/endure/WTAO.sol";

contract LiquidatorOptionalTest is Test {
    EndureDeployHelper helper;
    EndureDeployHelper.Addresses addrs;
    EndureDeployHelper.VAIAddresses vaiAddrs;
    EndureDeployHelper.LiquidatorConfig liquidatorConfig;
    EndureDeployHelper.LiquidatorAddresses liquidatorAddrs;

    VBep20Immutable vAlpha30;
    VBep20Immutable vWTAO;
    MockAlpha30 alpha30;
    WTAO wtao;
    MockResilientOracle oracle;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address supplier = makeAddr("supplier");

    function setUp() public {
        helper = new EndureDeployHelper();
        addrs = helper.deployAll();
        vaiAddrs = helper.deployVAIOptional(addrs, _defaultVAIConfig(), _vaiCreationCode());

        liquidatorConfig = EndureDeployHelper.LiquidatorConfig({
            treasuryPercentMantissa: 0.05e18,
            minLiquidatableVAI: 0,
            pendingRedeemChunkLength: 10
        });

        vAlpha30 = VBep20Immutable(payable(addrs.vAlpha30));
        vWTAO = VBep20Immutable(payable(addrs.vWTAO));
        alpha30 = MockAlpha30(addrs.mockAlpha30);
        wtao = WTAO(addrs.wtao);
        oracle = MockResilientOracle(addrs.resilientOracle);

        vm.prank(address(helper));
        oracle.setAdmin(address(this));

        _supplyBorrowSetup();
    }

    function test_DeployLiquidatorOptional_WiresComptrollerAndInitializesConfig() public {
        liquidatorAddrs = helper.deployLiquidatorOptional(addrs, liquidatorConfig);

        assertTrue(liquidatorAddrs.liquidator != address(0), "liquidator");
        assertTrue(liquidatorAddrs.liquidatorImplementation != address(0), "implementation");
        assertTrue(liquidatorAddrs.protocolShareReserve != address(0), "psr");
        assertEq(IComptrollerLiquidator(addrs.unitroller).liquidatorContract(), liquidatorAddrs.liquidator, "comptroller liquidator");
        assertEq(Liquidator(payable(liquidatorAddrs.liquidator)).treasuryPercentMantissa(), 0.05e18, "treasury percent");
        assertEq(Liquidator(payable(liquidatorAddrs.liquidator)).minLiquidatableVAI(), 0, "min VAI");
    }

    function test_LiquidatorOptional_CanLiquidateVTokenBorrowAndSendTreasuryShareToReserve() public {
        liquidatorAddrs = helper.deployLiquidatorOptional(addrs, liquidatorConfig);

        vm.prank(alice);
        assertEq(vWTAO.borrow(20e18), 0, "borrow");

        oracle.setUnderlyingPrice(addrs.vAlpha30, 0.3e18);

        uint256 repayAmount = 5e18;
        wtao.mint(bob, repayAmount);

        vm.startPrank(bob);
        wtao.approve(liquidatorAddrs.liquidator, repayAmount);
        Liquidator(payable(liquidatorAddrs.liquidator)).liquidateBorrow(
            addrs.vWTAO,
            alice,
            repayAmount,
            IVToken(addrs.vAlpha30)
        );
        vm.stopPrank();

        assertGt(vAlpha30.balanceOf(bob), 0, "bob seized collateral");
        assertGt(alpha30.balanceOf(liquidatorAddrs.protocolShareReserve), 0, "reserve got treasury share");
    }

    function _supplyBorrowSetup() internal {
        alpha30.mint(alice, 100e18);
        vm.startPrank(alice);
        alpha30.approve(address(vAlpha30), 100e18);
        assertEq(vAlpha30.mint(100e18), 0, "alice supply");
        address[] memory markets = new address[](1);
        markets[0] = address(vAlpha30);
        uint256[] memory results = MarketFacet(addrs.unitroller).enterMarkets(markets);
        assertEq(results[0], 0, "enter alpha");
        vm.stopPrank();

        wtao.mint(supplier, 1_000e18);
        vm.startPrank(supplier);
        wtao.approve(address(vWTAO), 1_000e18);
        assertEq(vWTAO.mint(1_000e18), 0, "supplier supply");
        vm.stopPrank();
    }

    function _defaultVAIConfig() internal view returns (EndureDeployHelper.VAIConfig memory) {
        return EndureDeployHelper.VAIConfig({
            vaiMintRate: 5_000,
            mintCap: 1_000_000e18,
            receiver: address(this),
            treasuryGuardian: address(this),
            treasuryAddress: address(this),
            treasuryPercent: 0,
            baseRateMantissa: 0,
            floatRateMantissa: 0
        });
    }

    function _vaiCreationCode() internal view returns (bytes memory) {
        return abi.encodePacked(vm.getCode("VAI.sol:VAI"), abi.encode(block.chainid));
    }
}

interface IComptrollerLiquidator {
    function liquidatorContract() external view returns (address);
}
