// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IPermissionManager {
    struct Permission {
        address account;
        address spender;
        uint48 start;
        uint48 end;
        uint256 salt;
        CallPermission[] calls;
        SpendLimit[] spends;
    }

    struct CallPermission {
        address target;
        bytes4 selector;
    }

    struct SpendLimit {
        address token;
        uint256 limit;
        uint48 period;
    }

    function spend(Permission memory permission, uint256 spendIndex, uint256 value) external;
}

/**
 * @dev Malicious ERC20 token that attempts reentrancy during transferFrom
 */
contract MockReentrantToken is ERC20 {
    address public attackTarget;
    bool public shouldAttack;
    IPermissionManager.Permission public attackPermission;
    uint256 public attackSpendIndex;
    uint256 public attackValue;

    constructor() ERC20("Reentrant", "REENT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setupAttack(
        address _target,
        IPermissionManager.Permission memory _permission,
        uint256 _spendIndex,
        uint256 _value
    ) external {
        attackTarget = _target;
        attackPermission = _permission;
        attackSpendIndex = _spendIndex;
        attackValue = _value;
        shouldAttack = true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        if (shouldAttack && attackTarget != address(0)) {
            shouldAttack = false; // Prevent infinite recursion
            // Attempt reentrancy
            IPermissionManager(attackTarget).spend(attackPermission, attackSpendIndex, attackValue);
        }
        return super.transferFrom(from, to, amount);
    }
}
