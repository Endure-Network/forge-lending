// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.25;

import {StdInvariant} from "@forge-std/StdInvariant.sol";
import {Test} from "@forge-std/Test.sol";
import {EndureDeployHelper} from "@test/helper/EndureDeployHelper.sol";
import {EndureHandler} from "./handlers/EndureHandler.sol";
import {VBep20Immutable} from "@protocol/Tokens/VTokens/VBep20Immutable.sol";
import {MockResilientOracle} from "@protocol/endure/MockResilientOracle.sol";

contract InvariantSolvencyTest is StdInvariant, Test {
    EndureDeployHelper helper;
    EndureDeployHelper.Addresses addrs;
    EndureHandler handler;
    VBep20Immutable vWTAO;

    function setUp() public {
        helper = new EndureDeployHelper();
        addrs = helper.deployAll();
        vWTAO = VBep20Immutable(payable(addrs.vWTAO));

        // Transfer oracle admin to handler for price manipulation
        vm.prank(address(helper));
        MockResilientOracle(addrs.resilientOracle).setAdmin(address(this));

        handler = new EndureHandler(
            addrs.unitroller,
            addrs.vWTAO,
            addrs.vAlpha30,
            addrs.wtao,
            addrs.mockAlpha30,
            addrs.resilientOracle
        );

        // Transfer oracle admin to handler
        MockResilientOracle(addrs.resilientOracle).setAdmin(address(handler));

        targetContract(address(handler));
    }

    function invariant_SolvencyGlobal() public view {
        uint256 cash = vWTAO.getCash();
        uint256 supplyValueInUnderlying =
            (vWTAO.totalSupply() * vWTAO.exchangeRateStored()) / 1e18;
        uint256 borrows = vWTAO.totalBorrows();
        uint256 reserves = vWTAO.totalReserves();

        assertGe(
            cash + supplyValueInUnderlying,
            borrows + reserves,
            "solvency invariant violated"
        );
    }

    function test_InvariantHandlerCoverage() public {
        for (uint256 i = 0; i < 10; i++) {
            handler.supply(i, (i + 1) * 10e18);
        }

        for (uint256 i = 0; i < 5; i++) {
            handler.borrow(i, (i + 1) * 1e18);
        }

        for (uint256 i = 0; i < 3; i++) {
            handler.repay(i, 0.5e18);
        }

        handler.redeem(0, 1e15);
        handler.moveOraclePrice(0, 0.5e18);

        assertGt(handler.callCounts("supply"), 0, "supply not called");
        assertGt(handler.callCounts("borrow"), 0, "borrow not called");
        assertGt(handler.callCounts("repay"), 0, "repay not called");
        assertGt(handler.callCounts("redeem"), 0, "redeem not called");
        assertGt(handler.callCounts("moveOraclePrice"), 0, "moveOraclePrice not called");
    }
}
