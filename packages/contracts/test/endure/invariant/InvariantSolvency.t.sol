// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {StdInvariant} from "@forge-std/StdInvariant.sol";
import {Test} from "@forge-std/Test.sol";
import {EndureDeployHelper} from "@test/helper/EndureDeployHelper.sol";
import {EndureRoles} from "@protocol/endure/EndureRoles.sol";
import {EndureHandler} from "./handlers/EndureHandler.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {MockPriceOracle} from "@protocol/endure/MockPriceOracle.sol";

contract InvariantSolvencyTest is StdInvariant, Test, EndureDeployHelper {
    EndureDeployHelper.Addresses addrs;
    EndureHandler handler;
    MErc20Delegator mWTAO;

    function setUp() public {
        vm.warp(block.timestamp + 1 days);
        EndureRoles.RoleSet memory roles = EndureRoles.RoleSet({
            admin: address(this),
            pauseGuardian: address(this),
            borrowCapGuardian: address(this),
            supplyCapGuardian: address(this)
        });
        addrs = _deployAs(roles);
        mWTAO = MErc20Delegator(payable(addrs.mWTAO));

        handler = new EndureHandler(
            addrs.comptrollerProxy,
            addrs.mWTAO,
            addrs.mMockAlpha30,
            addrs.wtao,
            addrs.mockAlpha30,
            addrs.mockPriceOracle
        );
        MockPriceOracle(addrs.mockPriceOracle).setAdmin(address(handler));

        targetContract(address(handler));
    }

    function invariant_SolvencyGlobal() public view {
        uint256 cash = mWTAO.getCash();
        uint256 supplyValueInUnderlying =
            (mWTAO.totalSupply() * mWTAO.exchangeRateStored()) / 1e18;
        uint256 borrows = mWTAO.totalBorrows();
        uint256 reserves = mWTAO.totalReserves();

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
        assertGt(
            handler.callCounts("moveOraclePrice"),
            0,
            "moveOraclePrice not called"
        );
    }
}
