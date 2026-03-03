// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev ERC20 mock with `increaseAllowance`
contract ERC20IncreaseAllowanceMock is ERC20 {

    constructor() ERC20("MockToken", "MT") { }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
        _approve(msg.sender, spender, allowance(msg.sender, spender) + addedValue);
        return true;
    }

}
