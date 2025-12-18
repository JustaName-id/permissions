// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Script } from "forge-std/Script.sol";

import { CodeConstants } from "./HelperConfig.s.sol";
import { JustaPermissionManager } from "../src/JustaPermissionManager.sol";

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
            account: account,
            spender: spender,
            start: start,
            end: end,
            salt: salt,
            calls: calls,
            spends: spends
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
        return JustaPermissionManager.CallPermission({ target: target, selector: selector });
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
        return JustaPermissionManager.SpendLimit({
            token: token,
            allowance: allowance,
            unit: unit,
            multiplier: multiplier
        });
    }

}
