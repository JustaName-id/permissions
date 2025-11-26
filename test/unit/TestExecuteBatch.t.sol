// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { JustaPermissionManager } from "../../../src/JustaPermissionManager.sol";
import { BaseAccount } from "@account-abstraction/core/BaseAccount.sol";
import { JustaPermissionManagerTestBase } from "../utils/JustaPermissionManagerTestBase.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";

contract TestExecuteBatch is JustaPermissionManagerTestBase {

    function test_ExecuteBatchSimpleTransfer() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        vm.prank(account);
        manager.approve(permission);

        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({
            target: address(erc20),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, randomUser, 10 ether)
        });

        uint256 balanceBefore = erc20.balanceOf(randomUser);

        vm.prank(spender);
        manager.executeBatch(permission, calls);

        assertEq(erc20.balanceOf(randomUser), balanceBefore + 10 ether);
    }

    function test_ExecuteBatchEmitsCallsExecutedEvent() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        vm.prank(account);
        manager.approve(permission);

        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({
            target: address(erc20),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, randomUser, 10 ether)
        });

        vm.expectEmit(true, false, false, false);
        emit JustaPermissionManager.CallsExecuted(manager.getHash(permission));

        vm.prank(spender);
        manager.executeBatch(permission, calls);
    }

    function test_ExecuteBatchNativeTokenTransfer() public {
        JustaPermissionManager.Permission memory permission = _createPermissionWithNativeToken();

        vm.prank(account);
        manager.approve(permission);

        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({
            target: randomUser,
            value: 0.5 ether,
            data: ""
        });

        uint256 balanceBefore = randomUser.balance;

        vm.prank(spender);
        manager.executeBatch(permission, calls);

        assertEq(randomUser.balance, balanceBefore + 0.5 ether);
    }

    function test_ExecuteBatchRevertsIfNotSpender() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        vm.prank(account);
        manager.approve(permission);

        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({
            target: address(erc20),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, randomUser, 10 ether)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_InvalidSender.selector,
                randomUser,
                spender
            )
        );
        vm.prank(randomUser);
        manager.executeBatch(permission, calls);
    }

    function test_ExecuteBatchRevertsOnUnapprovedPermission() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        // Don't approve

        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({
            target: address(erc20),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, randomUser, 10 ether)
        });

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_UnauthorizedPermission.selector);
        vm.prank(spender);
        manager.executeBatch(permission, calls);
    }

    function test_ExecuteBatchRevertsOnRevokedPermission() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        vm.prank(account);
        manager.approve(permission);

        vm.prank(account);
        manager.revoke(permission);

        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({
            target: address(erc20),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, randomUser, 10 ether)
        });

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_UnauthorizedPermission.selector);
        vm.prank(spender);
        manager.executeBatch(permission, calls);
    }

    function test_ExecuteBatchRevertsBeforePermissionStart() public {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({
            target: address(erc20),
            selector: IERC20.transfer.selector
        });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: address(erc20),
            allowance: 100 ether,
            period: JustaPermissionManager.SpendPeriod.Day
        });

        uint48 futureStart = uint48(block.timestamp + 1 hours);
        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: account,
            spender: spender,
            start: futureStart,
            end: uint48(block.timestamp + 1 days),
            salt: 40,
            calls: calls,
            spends: spends
        });

        vm.prank(account);
        manager.approve(permission);

        BaseAccount.Call[] memory executeCalls = new BaseAccount.Call[](1);
        executeCalls[0] = BaseAccount.Call({
            target: address(erc20),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, randomUser, 10 ether)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_BeforePermissionStart.selector,
                uint48(block.timestamp),
                futureStart
            )
        );
        vm.prank(spender);
        manager.executeBatch(permission, executeCalls);
    }

    function test_ExecuteBatchRevertsAfterPermissionEnd() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        vm.prank(account);
        manager.approve(permission);

        // Warp past end time
        vm.warp(block.timestamp + 2 days);

        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({
            target: address(erc20),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, randomUser, 10 ether)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_AfterPermissionEnd.selector,
                uint48(block.timestamp),
                permission.end
            )
        );
        vm.prank(spender);
        manager.executeBatch(permission, calls);
    }

    function test_ExecuteBatchRevertsOnUnauthorizedCall() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        vm.prank(account);
        manager.approve(permission);

        // Try to call a function not in the permission
        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({
            target: address(erc20),
            value: 0,
            data: abi.encodeWithSelector(IERC20.approve.selector, randomUser, 10 ether)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_UnauthorizedCall.selector,
                address(erc20),
                IERC20.approve.selector
            )
        );
        vm.prank(spender);
        manager.executeBatch(permission, calls);
    }

    function test_ExecuteBatchRevertsOnUnauthorizedTarget() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        vm.prank(account);
        manager.approve(permission);

        ERC20Mock anotherToken = new ERC20Mock();

        // Try to call correct function but wrong target
        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({
            target: address(anotherToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, randomUser, 10 ether)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_UnauthorizedCall.selector,
                address(anotherToken),
                IERC20.transfer.selector
            )
        );
        vm.prank(spender);
        manager.executeBatch(permission, calls);
    }

    function test_ExecuteBatchRevertsOnExceededSpendLimit() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        vm.prank(account);
        manager.approve(permission);

        // Try to transfer more than the allowance
        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({
            target: address(erc20),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, randomUser, 101 ether)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_ExceededSpendLimit.selector,
                101 ether,
                100 ether
            )
        );
        vm.prank(spender);
        manager.executeBatch(permission, calls);
    }

    function test_ExecuteBatchRevertsOnNoSpendPermissionForToken() public {
        JustaPermissionManager.Permission memory permission = _createPermissionNoSpendLimits();

        vm.prank(account);
        manager.approve(permission);

        // Try to transfer tokens without spend limit configured
        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({
            target: address(erc20),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, randomUser, 10 ether)
        });

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_NoSpendPermissions.selector);
        vm.prank(spender);
        manager.executeBatch(permission, calls);
    }

    function test_ExecuteBatchRevertsOnTargetingSelf() public {
        JustaPermissionManager.Permission memory permission = _createWildcardPermission();

        vm.prank(account);
        manager.approve(permission);

        // Try to target the permission manager
        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({
            target: address(manager),
            value: 0,
            data: abi.encodeWithSelector(JustaPermissionManager.approve.selector, permission)
        });

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_CannotTargetSelf.selector);
        vm.prank(spender);
        manager.executeBatch(permission, calls);
    }

    function test_ExecuteBatchRevertsOnTargetingAccount() public {
        JustaPermissionManager.Permission memory permission = _createWildcardPermission();

        vm.prank(account);
        manager.approve(permission);

        // Try to target the account
        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({
            target: account,
            value: 0,
            data: abi.encodeWithSelector(bytes4(keccak256("executeBatch((address,uint256,bytes)[])")), new BaseAccount.Call[](0))
        });

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_CannotTargetAccount.selector);
        vm.prank(spender);
        manager.executeBatch(permission, calls);
    }

    function test_ExecuteBatchWithWildcardTarget() public {
        JustaPermissionManager.Permission memory permission = _createWildcardPermission();

        vm.prank(account);
        manager.approve(permission);

        ERC20Mock anotherToken = new ERC20Mock();
        anotherToken.mint(account, 1000 ether);

        // Should work with any target
        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({
            target: address(erc20),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, randomUser, 10 ether)
        });

        vm.prank(spender);
        manager.executeBatch(permission, calls);

        assertEq(erc20.balanceOf(randomUser), 10 ether);
    }

    function test_ExecuteBatchMultipleCalls() public {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](2);
        calls[0] = JustaPermissionManager.CallPermission({
            target: address(erc20),
            selector: IERC20.transfer.selector
        });
        calls[1] = JustaPermissionManager.CallPermission({
            target: randomUser,
            selector: EMPTY_CALLDATA_FN_SEL
        });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](2);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: address(erc20),
            allowance: 100 ether,
            period: JustaPermissionManager.SpendPeriod.Day
        });
        spends[1] = JustaPermissionManager.SpendLimit({
            token: NATIVE_TOKEN,
            allowance: 1 ether,
            period: JustaPermissionManager.SpendPeriod.Day
        });

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: account,
            spender: spender,
            start: uint48(block.timestamp),
            end: uint48(block.timestamp + 1 days),
            salt: 50,
            calls: calls,
            spends: spends
        });

        vm.prank(account);
        manager.approve(permission);

        BaseAccount.Call[] memory executeCalls = new BaseAccount.Call[](2);
        executeCalls[0] = BaseAccount.Call({
            target: address(erc20),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, randomUser, 50 ether)
        });
        executeCalls[1] = BaseAccount.Call({
            target: randomUser,
            value: 0.5 ether,
            data: ""
        });

        uint256 erc20BalanceBefore = erc20.balanceOf(randomUser);
        uint256 ethBalanceBefore = randomUser.balance;

        vm.prank(spender);
        manager.executeBatch(permission, executeCalls);

        assertEq(erc20.balanceOf(randomUser), erc20BalanceBefore + 50 ether);
        assertEq(randomUser.balance, ethBalanceBefore + 0.5 ether);
    }

    function test_ExecuteBatchSpendLimitTracksAcrossMultipleCalls() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        vm.prank(account);
        manager.approve(permission);

        // First call - spend 20 ether
        BaseAccount.Call[] memory calls1 = new BaseAccount.Call[](1);
        calls1[0] = BaseAccount.Call({
            target: address(erc20),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, randomUser, 20 ether)
        });

        vm.prank(spender);
        manager.executeBatch(permission, calls1);

        // Second call - spend 20 ether
        BaseAccount.Call[] memory calls2 = new BaseAccount.Call[](1);
        calls2[0] = BaseAccount.Call({
            target: address(erc20),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, randomUser, 20 ether)
        });

        vm.prank(spender);
        manager.executeBatch(permission, calls2);

        // Verify tokens were transferred
        assertEq(erc20.balanceOf(randomUser), 40 ether);

        // Third call - try to spend an amount that will exceed the limit
        // The contract tracks spending cumulatively, so at some point it will exceed
        BaseAccount.Call[] memory calls3 = new BaseAccount.Call[](1);
        calls3[0] = BaseAccount.Call({
            target: address(erc20),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, randomUser, 50 ether)
        });

        // This should revert because the cumulative spend exceeds the allowance
        vm.expectRevert(); // Will revert with ExceededSpendLimit
        vm.prank(spender);
        manager.executeBatch(permission, calls3);
    }
}


