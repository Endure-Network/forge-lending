// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockXVS is ERC20 {
    constructor() ERC20("Mock XVS", "mXVS") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
