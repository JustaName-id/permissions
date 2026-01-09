// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Script } from "forge-std/Script.sol";

import { JustaPermissionManager } from "../src/JustaPermissionManager.sol";
import { CodeConstants } from "./HelperConfig.s.sol";

/**
 * @title PreparePermission
 * @notice Helper contract for creating Permission structs.
 */
contract PreparePermission is Script, CodeConstants {

    /**
     * @notice Creates a permission with full parameter control.
     * @param account The account that owns the permission.
     * @param spender The address authorized to use the permission.
     * @param start The permission start timestamp.
     * @param end The permission end timestamp.
     * @param salt A unique salt to differentiate permissions.
     * @param calls Array of call permissions.
     * @param spends Array of spend limits.
     * @return permission The constructed Permission struct.
     */
    function createPermission(
        address account,
        address spender,
        uint48 start,
        uint48 end,
        uint256 salt,
        JustaPermissionManager.CallPermission[] memory calls,
        JustaPermissionManager.SpendLimit[] memory spends
    )
        public
        pure
        returns (JustaPermissionManager.Permission memory permission)
    {
        return JustaPermissionManager.Permission({
            account: account, spender: spender, start: start, end: end, salt: salt, calls: calls, spends: spends
        });
    }

    /**
     * @notice Creates a single CallPermission struct.
     * @param target The target contract address.
     * @param selector The function selector.
     * @return call The constructed CallPermission struct.
     */
    function createCall(
        address target,
        bytes4 selector
    )
        public
        pure
        returns (JustaPermissionManager.CallPermission memory call)
    {
        return JustaPermissionManager.CallPermission({ target: target, selector: selector, checker: address(0) });
    }

    /**
     * @notice Creates a single CallPermission struct with a checker.
     * @param target The target contract address.
     * @param selector The function selector.
     * @param checker The checker contract address (address(0) for no checker).
     * @return call The constructed CallPermission struct.
     */
    function createCallWithChecker(
        address target,
        bytes4 selector,
        address checker
    )
        public
        pure
        returns (JustaPermissionManager.CallPermission memory call)
    {
        return JustaPermissionManager.CallPermission({ target: target, selector: selector, checker: checker });
    }

    /**
     * @notice Creates a single SpendLimit struct.
     * @param token The token address.
     * @param allowance The spend allowance.
     * @param unit The period unit.
     * @param multiplier The period multiplier.
     * @return spend The constructed SpendLimit struct.
     */
    function createSpendLimit(
        address token,
        uint160 allowance,
        JustaPermissionManager.PeriodUnit unit,
        uint8 multiplier
    )
        public
        pure
        returns (JustaPermissionManager.SpendLimit memory spend)
    {
        return
            JustaPermissionManager.SpendLimit({
                token: token, allowance: allowance, unit: unit, multiplier: multiplier
            });
    }

    /**
     * @notice Creates a basic permission with a single call and single spend limit.
     * @param account The account that owns the permission.
     * @param spender The address authorized to use the permission.
     * @param start The permission start timestamp.
     * @param end The permission end timestamp.
     * @param salt A unique salt to differentiate permissions.
     * @param target The target contract address for the call permission.
     * @param selector The function selector for the call permission.
     * @param token The token address for the spend limit.
     * @param allowance The spend allowance.
     * @param periodUnit The period unit (0-6).
     * @param multiplier The period multiplier.
     * @return permission The constructed Permission struct.
     */
    function createBasicPermission(
        address account,
        address spender,
        uint48 start,
        uint48 end,
        uint256 salt,
        address target,
        bytes4 selector,
        address token,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
        pure
        returns (JustaPermissionManager.Permission memory permission)
    {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({ target: target, selector: selector, checker: address(0) });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: token,
            allowance: allowance,
            unit: JustaPermissionManager.PeriodUnit(periodUnit),
            multiplier: multiplier
        });

        return JustaPermissionManager.Permission({
            account: account, spender: spender, start: start, end: end, salt: salt, calls: calls, spends: spends
        });
    }

}
