// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";

import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { ERC721Mock } from "../mocks/ERC721Mock.sol";
import { ERC1155Mock } from "../mocks/ERC1155Mock.sol";
import { PreparePermission } from "../../script/PreparePermission.s.sol";
import { JustaPermissionManager } from "../../src/JustaPermissionManager.sol";

contract TestWriteFunctions is Test, PreparePermission {

    JustaPermissionManager public manager;
    ERC20Mock public mockToken;
    ERC721Mock public mockERC721;
    ERC1155Mock public mockERC1155;

    function setUp() public {
        manager = new JustaPermissionManager();
        mockToken = new ERC20Mock();
        mockERC721 = new ERC721Mock();
        mockERC1155 = new ERC1155Mock();
    }

    /*//////////////////////////////////////////////////////////////
                        approve() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Approve_RevertIfNotAccountOwner(
        address sender,
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    ) public {
        vm.assume(sender != TEST_ACCOUNT_ADDRESS);
        vm.assume(sender != address(0));
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 6);
        vm.assume(multiplier > 0);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            address(mockToken),
            selector,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_InvalidSender.selector,
                sender,
                TEST_ACCOUNT_ADDRESS
            )
        );

        vm.prank(sender);
        manager.approve(permission);
    }

    function test_Approve_RevertIfZeroSpender(
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    ) public {
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 6);
        vm.assume(multiplier > 0);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            address(0),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            address(mockToken),
            selector,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_ZeroSpender.selector);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);
    }

    function test_Approve_RevertIfStartAfterEnd(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    ) public {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 6);
        vm.assume(multiplier > 0);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp + 1 days),
            uint48(block.timestamp),
            0,
            address(mockToken),
            selector,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_InvalidStartEnd.selector,
                uint48(block.timestamp + 1 days),
                uint48(block.timestamp)
            )
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);
    }

    function test_Approve_RevertIfStartEqualsEnd(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    ) public {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 6);
        vm.assume(multiplier > 0);

        uint48 timestamp = uint48(block.timestamp);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            timestamp,
            timestamp,
            0,
            address(mockToken),
            selector,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_InvalidStartEnd.selector,
                timestamp,
                timestamp
            )
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);
    }

    function test_Approve_RevertIfEmptyCallsArray(
        address spender,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    ) public {
        vm.assume(spender != address(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 6);
        vm.assume(multiplier > 0);

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](0);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(
            address(mockToken),
            allowance,
            JustaPermissionManager.PeriodUnit(periodUnit),
            multiplier
        );

        JustaPermissionManager.Permission memory permission = createPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            calls,
            spends
        );

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_EmptyPermission.selector);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);
    }

    function test_Approve_RevertIfCallTargetsSelf(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    ) public {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 6);
        vm.assume(multiplier > 0);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            address(manager),
            selector,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_CannotTargetSelf.selector);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);
    }

    function test_Approve_RevertIfCallTargetsAccount(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    ) public {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 6);
        vm.assume(multiplier > 0);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            TEST_ACCOUNT_ADDRESS,
            selector,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_CannotTargetAccount.selector);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);
    }

    function test_Approve_RevertIfCallTargetIsZero(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    ) public {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 6);
        vm.assume(multiplier > 0);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            address(0),
            selector,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_ZeroTarget.selector);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);
    }

    function test_Approve_RevertIfCallSelectorIsZero(
        address spender,
        address target,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    ) public {
        vm.assume(spender != address(0));
        vm.assume(target != address(0));
        vm.assume(target != address(manager));
        vm.assume(target != TEST_ACCOUNT_ADDRESS);
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 6);
        vm.assume(multiplier > 0);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            target,
            bytes4(0),
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_ZeroSelector.selector);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);
    }

    function test_Approve_RevertIfSpendTokenIsZero(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    ) public {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 6);
        vm.assume(multiplier > 0);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            address(mockToken),
            selector,
            address(0),
            allowance,
            periodUnit,
            multiplier
        );

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_ZeroToken.selector);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);
    }

    function test_Approve_RevertIfSpendAllowanceIsZero(
        address spender,
        bytes4 selector,
        uint8 periodUnit,
        uint8 multiplier
    ) public {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(periodUnit <= 6);
        vm.assume(multiplier > 0);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            address(mockToken),
            selector,
            address(mockToken),
            0,
            periodUnit,
            multiplier
        );

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_ZeroAllowance.selector);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);
    }

    function test_Approve_RevertIfSpendMultiplierIsZero(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit
    ) public {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 6);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            address(mockToken),
            selector,
            address(mockToken),
            allowance,
            periodUnit,
            0
        );

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_ZeroMultiplier.selector);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);
    }

    function test_Approve_RevertIfSpendTokenIsERC721(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    ) public {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 6);
        vm.assume(multiplier > 0);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            address(mockToken),
            selector,
            address(mockERC721),
            allowance,
            periodUnit,
            multiplier
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_ERC721TokenNotSupported.selector,
                address(mockERC721)
            )
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);
    }

    function test_Approve_RevertIfSpendTokenIsERC1155(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    ) public {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 6);
        vm.assume(multiplier > 0);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            address(mockToken),
            selector,
            address(mockERC1155),
            allowance,
            periodUnit,
            multiplier
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_ERC1155TokenNotSupported.selector,
                address(mockERC1155)
            )
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);
    }

    function test_Approve_RevertIfDuplicateSpendLimits(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    ) public {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 6);
        vm.assume(multiplier > 0);

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCall(address(mockToken), selector);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](2);
        spends[0] = createSpendLimit(
            address(mockToken),
            allowance,
            JustaPermissionManager.PeriodUnit(periodUnit),
            multiplier
        );
        spends[1] = createSpendLimit(
            address(mockToken),
            allowance,
            JustaPermissionManager.PeriodUnit(periodUnit),
            multiplier
        );

        JustaPermissionManager.Permission memory permission = createPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            calls,
            spends
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_DuplicateSpendLimit.selector,
                address(mockToken)
            )
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);
    }

    function test_Approve_RevertIfAlreadyRevoked(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    ) public {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 6);
        vm.assume(multiplier > 0);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            address(mockToken),
            selector,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.revoke(permission);

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_UnauthorizedPermission.selector);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);
    }

    function test_Approve_ShouldReturnTrueIfAlreadyApproved(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    ) public {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 6);
        vm.assume(multiplier > 0);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            address(mockToken),
            selector,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        bool result = manager.approve(permission);

        assertTrue(result);
    }

    function test_Approve_ShouldApprovePermissionAndEmitEvent(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    ) public {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 6);
        vm.assume(multiplier > 0);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            address(mockToken),
            selector,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        bytes32 expectedHash = manager.getHash(permission);

        vm.expectEmit(true, false, false, true, address(manager));
        emit JustaPermissionManager.PermissionApproved(expectedHash, permission);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        bool result = manager.approve(permission);

        assertTrue(result);
        assertTrue(manager.isApproved(permission));
    }

    /*//////////////////////////////////////////////////////////////
                        revoke() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Revoke_RevertIfNotAccountOwner(
        address sender,
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    ) public {
        vm.assume(sender != TEST_ACCOUNT_ADDRESS);
        vm.assume(sender != address(0));
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 6);
        vm.assume(multiplier > 0);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            address(mockToken),
            selector,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_InvalidSender.selector,
                sender,
                TEST_ACCOUNT_ADDRESS
            )
        );

        vm.prank(sender);
        manager.revoke(permission);
    }

    function test_Revoke_ShouldBeIdempotent(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    ) public {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 6);
        vm.assume(multiplier > 0);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            address(mockToken),
            selector,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.revoke(permission);

        assertTrue(manager.isRevoked(permission));

        // Second revoke should not revert
        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.revoke(permission);

        assertTrue(manager.isRevoked(permission));
    }

    function test_Revoke_ShouldRevokeAndEmitEvent(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    ) public {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 6);
        vm.assume(multiplier > 0);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            address(mockToken),
            selector,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        bytes32 expectedHash = manager.getHash(permission);

        vm.expectEmit(true, false, false, false, address(manager));
        emit JustaPermissionManager.PermissionRevoked(expectedHash);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.revoke(permission);

        assertTrue(manager.isRevoked(permission));
    }

    /*//////////////////////////////////////////////////////////////
                        revokeAsSpender() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RevokeAsSpender_RevertIfNotSpender(
        address sender,
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    ) public {
        vm.assume(sender != spender);
        vm.assume(sender != address(0));
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 6);
        vm.assume(multiplier > 0);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            address(mockToken),
            selector,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_InvalidSender.selector,
                sender,
                spender
            )
        );

        vm.prank(sender);
        manager.revokeAsSpender(permission);
    }

    function test_RevokeAsSpender_ShouldBeIdempotent(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    ) public {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 6);
        vm.assume(multiplier > 0);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            address(mockToken),
            selector,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.prank(spender);
        manager.revokeAsSpender(permission);

        assertTrue(manager.isRevoked(permission));

        // Second revoke should not revert
        vm.prank(spender);
        manager.revokeAsSpender(permission);

        assertTrue(manager.isRevoked(permission));
    }

    function test_RevokeAsSpender_ShouldRevokeAndEmitEvent(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    ) public {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 6);
        vm.assume(multiplier > 0);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            address(mockToken),
            selector,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        bytes32 expectedHash = manager.getHash(permission);

        vm.expectEmit(true, false, false, false, address(manager));
        emit JustaPermissionManager.PermissionRevoked(expectedHash);

        vm.prank(spender);
        manager.revokeAsSpender(permission);

        assertTrue(manager.isRevoked(permission));
    }

}
