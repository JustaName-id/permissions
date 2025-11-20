// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {JustaPermissionManager} from "../../src/JustaPermissionManager.sol";

/**
 * @dev Malicious ERC20 token that attempts reentrancy during transferFrom
 */
contract MockReentrantToken is ERC20 {
    address public attackTarget;
    bool public shouldAttack;
    JustaPermissionManager.Permission public attackPermission;
    JustaPermissionManager.SpendLimit public attackSpendLimit;
    uint160 public attackValue;

    constructor() ERC20("Reentrant", "REENT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setupAttack(
        address _target,
        JustaPermissionManager.Permission calldata _permission,
        JustaPermissionManager.SpendLimit calldata _spendLimit,
        uint160 _value
    ) external {
        attackTarget = _target;
        attackPermission = _permission;
        attackSpendLimit = _spendLimit;
        attackValue = _value;
        shouldAttack = true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        if (shouldAttack && attackTarget != address(0)) {
            shouldAttack = false; // Prevent infinite recursion
            // Attempt reentrancy
            JustaPermissionManager(attackTarget).spend(attackPermission, attackSpendLimit, attackValue);
        }
        return super.transferFrom(from, to, amount);
    }
}
