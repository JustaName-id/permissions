// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { JustaPermissionManager } from "../../../src/JustaPermissionManager.sol";
import { JustaPermissionManagerTestBase } from "../utils/JustaPermissionManagerTestBase.sol";

contract TestRevoke is JustaPermissionManagerTestBase {

    /*//////////////////////////////////////////////////////////////
                            REVOKE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RevokeAsAccountOwner() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        vm.prank(account);
        manager.approve(permission);

        vm.expectEmit(true, false, false, false);
        emit JustaPermissionManager.PermissionRevoked(manager.getHash(permission));

        vm.prank(account);
        manager.revoke(permission);

        assertTrue(manager.isRevoked(permission));
    }

    function test_RevokeRevertsIfNotAccountOwner() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        vm.prank(account);
        manager.approve(permission);

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_InvalidSender.selector, randomUser, account
            )
        );
        vm.prank(randomUser);
        manager.revoke(permission);
    }

    function test_RevokeIsIdempotent() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        vm.prank(account);
        manager.approve(permission);

        // First revoke
        vm.prank(account);
        manager.revoke(permission);

        // Second revoke should not revert
        vm.prank(account);
        manager.revoke(permission);

        assertTrue(manager.isRevoked(permission));
    }

    function test_RevokeUnapprovedPermission() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        // Revoke without approving first - should work (idempotent)
        vm.prank(account);
        manager.revoke(permission);

        assertTrue(manager.isRevoked(permission));
    }

    /*//////////////////////////////////////////////////////////////
                        REVOKE AS SPENDER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RevokeAsSpender() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        vm.prank(account);
        manager.approve(permission);

        vm.expectEmit(true, false, false, false);
        emit JustaPermissionManager.PermissionRevoked(manager.getHash(permission));

        vm.prank(spender);
        manager.revokeAsSpender(permission);

        assertTrue(manager.isRevoked(permission));
    }

    function test_RevokeAsSpenderRevertsIfNotSpender() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        vm.prank(account);
        manager.approve(permission);

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_InvalidSender.selector, randomUser, spender
            )
        );
        vm.prank(randomUser);
        manager.revokeAsSpender(permission);
    }

    function test_RevokeAsSpenderBeforeApproval() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        // Spender can revoke even before approval
        vm.prank(spender);
        manager.revokeAsSpender(permission);

        assertTrue(manager.isRevoked(permission));
    }

}
