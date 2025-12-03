// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { BaseAccount } from "@account-abstraction/core/BaseAccount.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { JustaPermissionManager } from "../../../src/JustaPermissionManager.sol";
import { JustaPermissionManagerTestBase } from "../utils/JustaPermissionManagerTestBase.sol";

contract TestViewFunctions is JustaPermissionManagerTestBase {

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_IsApprovedReturnsFalseForUnapproved() public view {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();
        assertFalse(manager.isApproved(permission));
    }

    function test_IsApprovedReturnsTrueForApproved() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        vm.prank(account);
        manager.approve(permission);

        assertTrue(manager.isApproved(permission));
    }

    function test_IsRevokedReturnsFalseForNotRevoked() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        vm.prank(account);
        manager.approve(permission);

        assertFalse(manager.isRevoked(permission));
    }

    function test_IsRevokedReturnsTrueForRevoked() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        vm.prank(account);
        manager.approve(permission);

        vm.prank(account);
        manager.revoke(permission);

        assertTrue(manager.isRevoked(permission));
    }

    function test_GetHashIsDeterministic() public view {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        bytes32 hash1 = manager.getHash(permission);
        bytes32 hash2 = manager.getHash(permission);

        assertEq(hash1, hash2);
    }

    function test_GetHashDiffersForDifferentPermissions() public view {
        JustaPermissionManager.Permission memory permission1 = _createBasicPermission();

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({ target: address(erc20), selector: IERC20.transfer.selector });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: address(erc20),
            allowance: 100 ether,
            unit: JustaPermissionManager.PeriodUnit.Hour,
            multiplier: 6 // 6-hour limit
        });

        JustaPermissionManager.Permission memory permission2 = JustaPermissionManager.Permission({
            account: account,
            spender: spender,
            start: uint48(block.timestamp),
            end: uint48(block.timestamp + 1 days),
            salt: 999, // Different salt
            calls: calls,
            spends: spends
        });

        assertNotEq(manager.getHash(permission1), manager.getHash(permission2));
    }

    function test_GetLastUpdatedPeriod() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        vm.prank(account);
        manager.approve(permission);

        // Before any spending
        JustaPermissionManager.PeriodSpend memory periodBefore =
            manager.getLastUpdatedPeriod(permission, permission.spends[0]);
        assertEq(periodBefore.start, 0);
        assertEq(periodBefore.end, 0);
        assertEq(periodBefore.spend, 0);

        // Execute a transfer
        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({
            target: address(erc20),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, randomUser, 50 ether)
        });

        vm.prank(spender);
        manager.executeBatch(permission, calls);

        // After spending
        JustaPermissionManager.PeriodSpend memory periodAfter =
            manager.getLastUpdatedPeriod(permission, permission.spends[0]);
        // Spend tracking stores the actual spent amount
        assertTrue(periodAfter.spend > 0);
        assertTrue(periodAfter.start > 0);
        assertTrue(periodAfter.end > periodAfter.start);
    }

    function test_GetCurrentPeriod() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        vm.prank(account);
        manager.approve(permission);

        JustaPermissionManager.PeriodSpend memory currentPeriod =
            manager.getCurrentPeriod(permission, permission.spends[0]);

        assertTrue(currentPeriod.start <= block.timestamp);
        assertTrue(currentPeriod.end > block.timestamp);
        assertEq(currentPeriod.spend, 0);
    }

}
