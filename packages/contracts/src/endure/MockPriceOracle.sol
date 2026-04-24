// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {PriceOracle} from "@protocol/oracles/PriceOracle.sol";
import {MToken} from "@protocol/MToken.sol";

contract MockPriceOracle is PriceOracle {
    address public admin;
    mapping(address => uint256) public prices;

    event PriceSet(address indexed mToken, uint256 price);
    event AdminChanged(address indexed oldAdmin, address indexed newAdmin);

    constructor() {
        admin = msg.sender;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "only admin");
        _;
    }

    function getUnderlyingPrice(
        MToken mToken
    ) external view override returns (uint256) {
        return prices[address(mToken)];
    }

    function setUnderlyingPrice(
        MToken mToken,
        uint256 price
    ) external onlyAdmin {
        prices[address(mToken)] = price;
        emit PriceSet(address(mToken), price);
    }

    function setAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "new admin = 0");
        emit AdminChanged(admin, newAdmin);
        admin = newAdmin;
    }
}
