// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseTest} from "../utils/BaseTest.sol";
import {JustaPermissionManager} from "../../src/JustaPermissionManager.sol";

/**
 * @title TestJustaPermissionManagerRevoke
 * @notice Comprehensive tests for revoke() and revokeAsSpender() functions
 */
contract TestJustaPermissionManagerRevoke is BaseTest {
    /*//////////////////////////////////////////////////////////////
                    REVOKE BY ACCOUNT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Revoke_ByAccountSuccessfully() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();
        JustaPermissionManager.CallPermission memory call = permission.calls[0];
        bytes32 hash = manager.getHash(permission);

        // Approve first
        _approvePermission(permission);
        assertTrue(manager.isApproved(permission));

        // Revoke
        vm.prank(address(account));
        vm.expectEmit(true, false, false, false);
        emit PermissionRevoked(hash);
        manager.revoke(permission);

        // Permission is still "approved" but now revoked
        assertTrue(manager.isApproved(permission));
        assertTrue(manager.isRevoked(permission));

        // Try to use it - should fail
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(JustaPermissionManager.JustaPermissionManager_UnauthorizedPermission.selector)
        );
        manager.executeCall(permission, call, abi.encodeWithSelector(target.increment.selector));
    }

    function test_Revoke_NonExistentPermission() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        // Revoke without approving first (should not revert)
        vm.prank(address(account));
        manager.revoke(permission);

        assertFalse(manager.isApproved(permission));
        assertTrue(manager.isRevoked(permission));
    }

    function test_Revoke_AlreadyRevokedPermission() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        // Approve and revoke
        _approvePermission(permission);

        vm.startPrank(address(account));
        manager.revoke(permission);
        assertTrue(manager.isRevoked(permission));

        // Revoke again (should be idempotent)
        manager.revoke(permission);
        vm.stopPrank();

        assertTrue(manager.isRevoked(permission));
    }

    function test_RevertWhen_Revoke_CallerNotAccount() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        _approvePermission(permission);

        // Try to revoke as attacker
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_InvalidSender.selector, attacker, address(account)
            )
        );
        manager.revoke(permission);
    }

    function test_RevertWhen_Revoke_CallerIsSpender() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        _approvePermission(permission);

        // Try to revoke as spender using revoke() instead of revokeAsSpender()
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_InvalidSender.selector, spender, address(account)
            )
        );
        manager.revoke(permission);
    }

    /*//////////////////////////////////////////////////////////////
                    REVOKE AS SPENDER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RevokeAsSpender_Successfully() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();
        JustaPermissionManager.CallPermission memory call = permission.calls[0];
        bytes32 hash = manager.getHash(permission);

        // Approve first
        _approvePermission(permission);
        assertTrue(manager.isApproved(permission));

        // Revoke as spender
        vm.prank(spender);
        vm.expectEmit(true, false, false, false);
        emit PermissionRevoked(hash);
        manager.revokeAsSpender(permission);

        // Permission is revoked
        assertTrue(manager.isRevoked(permission));

        // Try to use it - should fail
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(JustaPermissionManager.JustaPermissionManager_UnauthorizedPermission.selector)
        );
        manager.executeCall(permission, call, abi.encodeWithSelector(target.increment.selector));
    }

    function test_RevokeAsSpender_NonExistentPermission() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        // Revoke without approving first
        vm.prank(spender);
        manager.revokeAsSpender(permission);

        assertTrue(manager.isRevoked(permission));
    }

    function test_RevokeAsSpender_AlreadyRevokedByAccount() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        // Approve, then revoke by account
        _approvePermission(permission);

        vm.prank(address(account));
        manager.revoke(permission);

        // Try to revoke as spender (should be idempotent)
        vm.prank(spender);
        manager.revokeAsSpender(permission);

        assertTrue(manager.isRevoked(permission));
    }

    function test_RevertWhen_RevokeAsSpender_CallerNotSpender() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        _approvePermission(permission);

        // Try to revoke as attacker
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_InvalidSender.selector, attacker, spender
            )
        );
        manager.revokeAsSpender(permission);
    }

    function test_RevertWhen_RevokeAsSpender_CallerIsAccount() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        _approvePermission(permission);

        // Account should use revoke(), not revokeAsSpender()
        vm.prank(address(account));
        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_InvalidSender.selector, address(account), spender
            )
        );
        manager.revokeAsSpender(permission);
    }

    /*//////////////////////////////////////////////////////////////
                    REVOKE THEN RE-APPROVE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Approve_AfterRevoke_ShouldFail() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        // Approve and revoke
        _approvePermission(permission);

        vm.prank(address(account));
        manager.revoke(permission);

        assertTrue(manager.isRevoked(permission));

        // Try to approve again - should return false
        vm.prank(address(account));
        bool result = manager.approve(permission);

        assertFalse(result);
        assertTrue(manager.isRevoked(permission));
    }

    function test_Approve_DifferentSaltAfterRevoke() public {
        JustaPermissionManager.Permission memory permission1 = _createBasicPermission();
        permission1.salt = 0;

        // Approve and revoke permission1
        _approvePermission(permission1);

        vm.prank(address(account));
        manager.revoke(permission1);

        assertTrue(manager.isRevoked(permission1));

        // Create permission with different salt
        JustaPermissionManager.Permission memory permission2 = _createBasicPermission();
        permission2.salt = 1;

        // This should work since it's a different permission
        vm.prank(address(account));
        bool result = manager.approve(permission2);

        assertTrue(result);
        assertTrue(manager.isApproved(permission2));
        assertFalse(manager.isRevoked(permission2));
    }

    /*//////////////////////////////////////////////////////////////
                    REVOKE WITH SPEND LIMITS
    //////////////////////////////////////////////////////////////*/

    function test_Revoke_PermissionWithSpendLimit() public {
        JustaPermissionManager.Permission memory permission = _createSpendPermission(uint160(100e18), PERIOD);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        // Approve and setup
        _approvePermission(permission);
        _approveTokenSpending();

        // Revoke
        vm.prank(address(account));
        manager.revoke(permission);

        assertTrue(manager.isRevoked(permission));

        // Try to spend - should fail
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(JustaPermissionManager.JustaPermissionManager_UnauthorizedPermission.selector)
        );
        manager.spend(permission, spendLimit, 50e18);
    }

    function test_RevokeAsSpender_PermissionWithSpendLimit() public {
        JustaPermissionManager.Permission memory permission = _createSpendPermission(uint160(100e18), PERIOD);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        // Approve and setup
        _approvePermission(permission);
        _approveTokenSpending();

        // Revoke as spender
        vm.prank(spender);
        manager.revokeAsSpender(permission);

        assertTrue(manager.isRevoked(permission));

        // Try to spend - should fail
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(JustaPermissionManager.JustaPermissionManager_UnauthorizedPermission.selector)
        );
        manager.spend(permission, spendLimit, 50e18);
    }

    /*//////////////////////////////////////////////////////////////
                    REVOKE AFTER PARTIAL USE
    //////////////////////////////////////////////////////////////*/

    function test_Revoke_AfterPartialSpendUsage() public {
        JustaPermissionManager.Permission memory permission = _createSpendPermission(uint160(100e18), PERIOD);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        // Approve and setup
        _approvePermission(permission);
        _approveTokenSpending();

        // Use some of the allowance
        vm.prank(spender);
        manager.spend(permission, spendLimit, 30e18);

        assertEq(token.balanceOf(spender), 30e18);

        // Revoke
        vm.prank(address(account));
        manager.revoke(permission);

        // Try to spend more - should fail
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(JustaPermissionManager.JustaPermissionManager_UnauthorizedPermission.selector)
        );
        manager.spend(permission, spendLimit, 20e18);

        // Balance should remain at 30e18
        assertEq(token.balanceOf(spender), 30e18);
    }

    function test_Revoke_AfterCallExecution() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();
        JustaPermissionManager.CallPermission memory call = permission.calls[0];

        // Approve
        _approvePermission(permission);

        // Execute call
        vm.prank(spender);
        manager.executeCall(permission, call, abi.encodeWithSelector(target.increment.selector));

        assertEq(target.counter(), 1);

        // Revoke
        vm.prank(address(account));
        manager.revoke(permission);

        // Try to execute again - should fail
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(JustaPermissionManager.JustaPermissionManager_UnauthorizedPermission.selector)
        );
        manager.executeCall(permission, call, abi.encodeWithSelector(target.increment.selector));

        // Counter should remain at 1
        assertEq(target.counter(), 1);
    }
}
