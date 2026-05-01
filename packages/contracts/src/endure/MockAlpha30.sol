// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.19;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockAlpha30 is ERC20 {
    uint256 public immutable netuid = 30;
    constructor() ERC20("Mock Alpha 30", "mALPHA30") {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
    function burn(address from, uint256 amount) external { _burn(from, amount); }
}
