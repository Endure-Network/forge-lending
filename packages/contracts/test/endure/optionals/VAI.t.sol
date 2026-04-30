// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.25;

import {Test} from "@forge-std/Test.sol";
import {EndureDeployHelper} from "@protocol/endure/EndureDeployHelper.sol";
import {MockAlpha30} from "@protocol/endure/MockAlpha30.sol";
import {MarketFacet} from "@protocol/Comptroller/Diamond/facets/MarketFacet.sol";
import {VBep20Immutable} from "@protocol/Tokens/VTokens/VBep20Immutable.sol";
import {VAIControllerInterface} from "@protocol/Tokens/VAI/VAIControllerInterface.sol";

contract VAIOptionalTest is Test {
    EndureDeployHelper helper;
    EndureDeployHelper.Addresses addrs;
    EndureDeployHelper.VAIConfig config;
    EndureDeployHelper.VAIAddresses vaiAddrs;

    address alice = makeAddr("alice");

    function setUp() public {
        helper = new EndureDeployHelper();
        addrs = helper.deployAll();
        config = EndureDeployHelper.VAIConfig({
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

    function test_DeployVAIOptional_WiresTokenControllerAndComptroller() public {
        vaiAddrs = helper.deployVAIOptional(addrs, config, _vaiCreationCode());

        assertTrue(vaiAddrs.vai != address(0), "vai");
        assertTrue(vaiAddrs.vaiController != address(0), "vaiController");
        assertTrue(vaiAddrs.vaiControllerImplementation != address(0), "vaiControllerImplementation");
        assertEq(IComptrollerVAI(addrs.unitroller).vaiController(), vaiAddrs.vaiController, "comptroller controller");
        assertEq(IVAIControllerView(vaiAddrs.vaiController).getVAIAddress(), vaiAddrs.vai, "controller token");
        assertEq(IComptrollerVAI(addrs.unitroller).vaiMintRate(), config.vaiMintRate, "mint rate");
        assertEq(IVAI(vaiAddrs.vai).wards(vaiAddrs.vaiController), 1, "controller auth");
    }

    function test_MintVAI_RevertsWithoutCollateral() public {
        vaiAddrs = helper.deployVAIOptional(addrs, config, _vaiCreationCode());

        vm.prank(alice);
        vm.expectRevert(bytes("minting more than allowed"));
        VAIControllerInterface(vaiAddrs.vaiController).mintVAI(1e18);
    }

    function test_MintAndRepayVAI_UpdatesDebtAndTokenBalance() public {
        vaiAddrs = helper.deployVAIOptional(addrs, config, _vaiCreationCode());
        _supplyAlphaCollateral(alice, 100e18);

        vm.startPrank(alice);
        assertEq(VAIControllerInterface(vaiAddrs.vaiController).mintVAI(10e18), 0, "mint VAI");
        assertEq(IVAI(vaiAddrs.vai).balanceOf(alice), 10e18, "vai balance");
        assertEq(IComptrollerVAI(addrs.unitroller).mintedVAIs(alice), 10e18, "minted debt");

        IVAI(vaiAddrs.vai).approve(vaiAddrs.vaiController, 4e18);
        (uint256 err, uint256 actualRepayAmount) = VAIControllerInterface(vaiAddrs.vaiController).repayVAI(4e18);
        assertEq(err, 0, "repay err");
        assertEq(actualRepayAmount, 4e18, "actual repay");
        assertEq(IVAI(vaiAddrs.vai).balanceOf(alice), 6e18, "vai balance after repay");
        assertEq(IComptrollerVAI(addrs.unitroller).mintedVAIs(alice), 6e18, "remaining debt");
        vm.stopPrank();
    }

    function test_MintVAI_EnforcesMintCap() public {
        config.mintCap = 5e18;
        vaiAddrs = helper.deployVAIOptional(addrs, config, _vaiCreationCode());
        _supplyAlphaCollateral(alice, 100e18);

        vm.prank(alice);
        vm.expectRevert(bytes("mint cap reached"));
        VAIControllerInterface(vaiAddrs.vaiController).mintVAI(6e18);
    }

    function _supplyAlphaCollateral(address account, uint256 amount) internal {
        MockAlpha30 alpha30 = MockAlpha30(addrs.mockAlpha30);
        VBep20Immutable vAlpha30 = VBep20Immutable(payable(addrs.vAlpha30));
        alpha30.mint(account, amount);

        vm.startPrank(account);
        alpha30.approve(address(vAlpha30), amount);
        assertEq(vAlpha30.mint(amount), 0, "mint vAlpha30");

        address[] memory markets = new address[](1);
        markets[0] = address(vAlpha30);
        uint256[] memory results = MarketFacet(addrs.unitroller).enterMarkets(markets);
        assertEq(results[0], 0, "enter market");
        vm.stopPrank();
    }

    function _vaiCreationCode() internal view returns (bytes memory) {
        return abi.encodePacked(vm.getCode("VAI.sol:VAI"), abi.encode(block.chainid));
    }
}

interface IComptrollerVAI {
    function vaiController() external view returns (address);

    function vaiMintRate() external view returns (uint256);

    function mintedVAIs(address account) external view returns (uint256);
}

interface IVAIControllerView {
    function getVAIAddress() external view returns (address);
}

interface IVAI {
    function wards(address account) external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);
}
