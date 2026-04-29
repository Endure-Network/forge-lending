// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./MockFlashLoanReceiver.sol";
import { ComptrollerInterface } from "../../venus-staging/Comptroller/ComptrollerInterface.sol";
import { VToken } from "../../venus-staging/Tokens/VTokens/VToken.sol";

contract BadFlashLoanReceiver is MockFlashLoanReceiver {
    constructor(ComptrollerInterface comptroller) MockFlashLoanReceiver(comptroller) {}

    function executeOperation(
        VToken[] calldata,
        uint256[] calldata,
        uint256[] calldata,
        address,
        address,
        bytes calldata
    ) external override returns (bool, uint256[] memory) {
        return (false, new uint256[](0));
    }
}
