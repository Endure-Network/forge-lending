// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.19;
import {ERC20} from "@openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MockAlpha64 is ERC20 {
    uint256 public immutable netuid = 64;
    constructor() ERC20("Mock Alpha 64", "mALPHA64") {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
    function burn(address from, uint256 amount) external { _burn(from, amount); }
}
