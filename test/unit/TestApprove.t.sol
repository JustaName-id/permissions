// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { JustaPermissionManager } from "../../../src/JustaPermissionManager.sol";

import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { JustaPermissionManagerTestBase } from "../utils/JustaPermissionManagerTestBase.sol";

contract TestApprove is JustaPermissionManagerTestBase {

    /*//////////////////////////////////////////////////////////////
                        APPROVE TESTS - HAPPY PATH
    //////////////////////////////////////////////////////////////*/

    function test_ApproveSimplePermission() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        vm.prank(account);
        bool result = manager.approve(permission);

        assertTrue(result);
        assertTrue(manager.isApproved(permission));
        assertFalse(manager.isRevoked(permission));
    }

    function test_ApproveEmitsEvent() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();
        bytes32 expectedHash = manager.getHash(permission);

        vm.expectEmit(true, false, false, false);
        emit JustaPermissionManager.PermissionApproved(expectedHash, permission);

        vm.prank(account);
        manager.approve(permission);
    }

    function test_ApproveMultipleCallPermissions() public {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](3);
        calls[0] = JustaPermissionManager.CallPermission({ target: address(erc20), selector: IERC20.transfer.selector });
        calls[1] = JustaPermissionManager.CallPermission({ target: address(erc20), selector: IERC20.approve.selector });
        calls[2] =
            JustaPermissionManager.CallPermission({ target: address(erc20), selector: IERC20.transferFrom.selector });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: address(erc20),
            allowance: 100 ether,
            period: JustaPermissionManager.SpendPeriod.Day
        });

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: account,
            spender: spender,
            start: uint48(block.timestamp),
            end: uint48(block.timestamp + 1 days),
            salt: 10,
            calls: calls,
            spends: spends
        });

        vm.prank(account);
        assertTrue(manager.approve(permission));
        assertTrue(manager.isApproved(permission));
    }

    function test_ApproveMultipleSpendLimits() public {
        ERC20Mock erc20Two = new ERC20Mock();

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({ target: ANY_TARGET, selector: IERC20.transfer.selector });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](2);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: address(erc20),
            allowance: 100 ether,
            period: JustaPermissionManager.SpendPeriod.Day
        });
        spends[1] = JustaPermissionManager.SpendLimit({
            token: address(erc20Two),
            allowance: 50 ether,
            period: JustaPermissionManager.SpendPeriod.Hour
        });

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: account,
            spender: spender,
            start: uint48(block.timestamp),
            end: uint48(block.timestamp + 1 days),
            salt: 11,
            calls: calls,
            spends: spends
        });

        vm.prank(account);
        assertTrue(manager.approve(permission));
    }

    function test_ApproveWithWildcardTarget() public {
        JustaPermissionManager.Permission memory permission = _createWildcardPermission();

        vm.prank(account);
        assertTrue(manager.approve(permission));
        assertTrue(manager.isApproved(permission));
    }

    function test_ApproveWithWildcardSelector() public {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({ target: address(erc20), selector: ANY_FN_SEL });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: address(erc20),
            allowance: 100 ether,
            period: JustaPermissionManager.SpendPeriod.Day
        });

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: account,
            spender: spender,
            start: uint48(block.timestamp),
            end: uint48(block.timestamp + 1 days),
            salt: 12,
            calls: calls,
            spends: spends
        });

        vm.prank(account);
        assertTrue(manager.approve(permission));
    }

    function test_ApproveReturnsTrueIfAlreadyApproved() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        vm.prank(account);
        assertTrue(manager.approve(permission));

        // Approve again - should return true (idempotent)
        vm.prank(account);
        assertTrue(manager.approve(permission));
    }

    function test_ApproveWithNativeToken() public {
        JustaPermissionManager.Permission memory permission = _createPermissionWithNativeToken();

        vm.prank(account);
        assertTrue(manager.approve(permission));
        assertTrue(manager.isApproved(permission));
    }

    function test_ApproveWithNoSpendLimits() public {
        JustaPermissionManager.Permission memory permission = _createPermissionNoSpendLimits();

        vm.prank(account);
        assertTrue(manager.approve(permission));
        assertTrue(manager.isApproved(permission));
    }

    function test_ApproveSameTokenDifferentPeriods() public {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({ target: address(erc20), selector: IERC20.transfer.selector });

        // Same token with different periods should be allowed
        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](2);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: address(erc20),
            allowance: 10 ether,
            period: JustaPermissionManager.SpendPeriod.Hour
        });
        spends[1] = JustaPermissionManager.SpendLimit({
            token: address(erc20),
            allowance: 100 ether,
            period: JustaPermissionManager.SpendPeriod.Day
        });

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: account,
            spender: spender,
            start: uint48(block.timestamp),
            end: uint48(block.timestamp + 1 days),
            salt: 13,
            calls: calls,
            spends: spends
        });

        vm.prank(account);
        assertTrue(manager.approve(permission));
    }

    /*//////////////////////////////////////////////////////////////
                    APPROVE TESTS - VALIDATION ERRORS
    //////////////////////////////////////////////////////////////*/

    function test_ApproveRevertsIfNotAccountOwner() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_InvalidSender.selector, randomUser, account
            )
        );
        vm.prank(randomUser);
        manager.approve(permission);
    }

    function test_ApproveRevertsOnZeroSpender() public {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({ target: address(erc20), selector: IERC20.transfer.selector });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: address(erc20),
            allowance: 100 ether,
            period: JustaPermissionManager.SpendPeriod.Day
        });

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: account,
            spender: address(0), // Zero spender
            start: uint48(block.timestamp),
            end: uint48(block.timestamp + 1 days),
            salt: 20,
            calls: calls,
            spends: spends
        });

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_ZeroSpender.selector);
        vm.prank(account);
        manager.approve(permission);
    }

    function test_ApproveRevertsOnInvalidStartEnd() public {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({ target: address(erc20), selector: IERC20.transfer.selector });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: address(erc20),
            allowance: 100 ether,
            period: JustaPermissionManager.SpendPeriod.Day
        });

        // Start >= End
        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: account,
            spender: spender,
            start: uint48(block.timestamp + 1 days),
            end: uint48(block.timestamp), // End before start
            salt: 21,
            calls: calls,
            spends: spends
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_InvalidStartEnd.selector,
                uint48(block.timestamp + 1 days),
                uint48(block.timestamp)
            )
        );
        vm.prank(account);
        manager.approve(permission);
    }

    function test_ApproveRevertsOnStartEqualsEnd() public {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({ target: address(erc20), selector: IERC20.transfer.selector });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: address(erc20),
            allowance: 100 ether,
            period: JustaPermissionManager.SpendPeriod.Day
        });

        uint48 sameTime = uint48(block.timestamp);
        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: account,
            spender: spender,
            start: sameTime,
            end: sameTime, // Same as start
            salt: 22,
            calls: calls,
            spends: spends
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_InvalidStartEnd.selector, sameTime, sameTime
            )
        );
        vm.prank(account);
        manager.approve(permission);
    }

    function test_ApproveRevertsOnEmptyCallPermissions() public {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](0);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: address(erc20),
            allowance: 100 ether,
            period: JustaPermissionManager.SpendPeriod.Day
        });

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: account,
            spender: spender,
            start: uint48(block.timestamp),
            end: uint48(block.timestamp + 1 days),
            salt: 23,
            calls: calls,
            spends: spends
        });

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_EmptyPermission.selector);
        vm.prank(account);
        manager.approve(permission);
    }

    function test_ApproveRevertsOnZeroTarget() public {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({
            target: address(0), // Zero target
            selector: IERC20.transfer.selector
        });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: address(erc20),
            allowance: 100 ether,
            period: JustaPermissionManager.SpendPeriod.Day
        });

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: account,
            spender: spender,
            start: uint48(block.timestamp),
            end: uint48(block.timestamp + 1 days),
            salt: 24,
            calls: calls,
            spends: spends
        });

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_ZeroTarget.selector);
        vm.prank(account);
        manager.approve(permission);
    }

    function test_ApproveRevertsOnZeroSelector() public {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({
            target: address(erc20),
            selector: bytes4(0) // Zero selector
         });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: address(erc20),
            allowance: 100 ether,
            period: JustaPermissionManager.SpendPeriod.Day
        });

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: account,
            spender: spender,
            start: uint48(block.timestamp),
            end: uint48(block.timestamp + 1 days),
            salt: 25,
            calls: calls,
            spends: spends
        });

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_ZeroSelector.selector);
        vm.prank(account);
        manager.approve(permission);
    }

    function test_ApproveRevertsOnZeroTokenInSpendLimit() public {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({ target: address(erc20), selector: IERC20.transfer.selector });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: address(0), // Zero token
            allowance: 100 ether,
            period: JustaPermissionManager.SpendPeriod.Day
        });

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: account,
            spender: spender,
            start: uint48(block.timestamp),
            end: uint48(block.timestamp + 1 days),
            salt: 26,
            calls: calls,
            spends: spends
        });

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_ZeroToken.selector);
        vm.prank(account);
        manager.approve(permission);
    }

    function test_ApproveRevertsOnZeroAllowance() public {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({ target: address(erc20), selector: IERC20.transfer.selector });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: address(erc20),
            allowance: 0, // Zero allowance
            period: JustaPermissionManager.SpendPeriod.Day
        });

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: account,
            spender: spender,
            start: uint48(block.timestamp),
            end: uint48(block.timestamp + 1 days),
            salt: 27,
            calls: calls,
            spends: spends
        });

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_ZeroAllowance.selector);
        vm.prank(account);
        manager.approve(permission);
    }

    function test_ApproveRevertsOnERC721Token() public {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({
            target: address(erc721),
            selector: bytes4(keccak256("safeTransferFrom(address,address,uint256)"))
        });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: address(erc721), // ERC721 token
            allowance: 1,
            period: JustaPermissionManager.SpendPeriod.Day
        });

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: account,
            spender: spender,
            start: uint48(block.timestamp),
            end: uint48(block.timestamp + 1 days),
            salt: 28,
            calls: calls,
            spends: spends
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_ERC721TokenNotSupported.selector, address(erc721)
            )
        );
        vm.prank(account);
        manager.approve(permission);
    }

    function test_ApproveRevertsOnERC1155Token() public {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({
            target: address(erc1155),
            selector: bytes4(keccak256("safeTransferFrom(address,address,uint256,uint256,bytes)"))
        });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: address(erc1155), // ERC1155 token
            allowance: 1,
            period: JustaPermissionManager.SpendPeriod.Day
        });

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: account,
            spender: spender,
            start: uint48(block.timestamp),
            end: uint48(block.timestamp + 1 days),
            salt: 29,
            calls: calls,
            spends: spends
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_ERC1155TokenNotSupported.selector, address(erc1155)
            )
        );
        vm.prank(account);
        manager.approve(permission);
    }

    function test_ApproveRevertsOnDuplicateSpendLimit() public {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({ target: address(erc20), selector: IERC20.transfer.selector });

        // Exact duplicate spend limits
        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](2);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: address(erc20),
            allowance: 100 ether,
            period: JustaPermissionManager.SpendPeriod.Day
        });
        spends[1] = JustaPermissionManager.SpendLimit({
            token: address(erc20),
            allowance: 100 ether,
            period: JustaPermissionManager.SpendPeriod.Day
        });

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: account,
            spender: spender,
            start: uint48(block.timestamp),
            end: uint48(block.timestamp + 1 days),
            salt: 30,
            calls: calls,
            spends: spends
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_DuplicateSpendLimit.selector, address(erc20)
            )
        );
        vm.prank(account);
        manager.approve(permission);
    }

    function test_ApproveRevertsOnTargetingSelf() public {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({
            target: address(manager), // Targeting the permission manager itself
            selector: JustaPermissionManager.approve.selector
        });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](0);

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: account,
            spender: spender,
            start: uint48(block.timestamp),
            end: uint48(block.timestamp + 1 days),
            salt: 31,
            calls: calls,
            spends: spends
        });

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_CannotTargetSelf.selector);
        vm.prank(account);
        manager.approve(permission);
    }

    function test_ApproveRevertsOnTargetingAccount() public {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({
            target: account, // Targeting the account itself
            selector: bytes4(keccak256("executeBatch((address,uint256,bytes)[])"))
        });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](0);

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: account,
            spender: spender,
            start: uint48(block.timestamp),
            end: uint48(block.timestamp + 1 days),
            salt: 32,
            calls: calls,
            spends: spends
        });

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_CannotTargetAccount.selector);
        vm.prank(account);
        manager.approve(permission);
    }

    function test_ApproveRevertsOnRevokedPermission() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        // Approve first
        vm.prank(account);
        manager.approve(permission);

        // Revoke
        vm.prank(account);
        manager.revoke(permission);

        // Try to approve again - should fail
        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_UnauthorizedPermission.selector);
        vm.prank(account);
        manager.approve(permission);
    }

}
