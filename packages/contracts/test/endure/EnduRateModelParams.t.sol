// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;
import {Test} from "@forge-std/Test.sol";
import {EnduRateModelParams} from "@protocol/endure/EnduRateModelParams.sol";

contract EnduRateModelParamsTest is Test {
    function test_AlphaBorrowCapIs1NotZero() public pure {
        assertEq(EnduRateModelParams.BORROW_CAP_ALPHA, 1, "alpha borrow cap must be 1 wei, not 0 (0 = unlimited)");
    }
}
