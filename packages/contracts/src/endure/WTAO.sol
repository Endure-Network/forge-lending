// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.19;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract WTAO is ERC20 {
    constructor() ERC20("Wrapped TAO", "WTAO") {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
    function burn(address from, uint256 amount) external { _burn(from, amount); }
}
