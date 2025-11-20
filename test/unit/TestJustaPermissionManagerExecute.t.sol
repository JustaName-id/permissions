// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseTest} from "../utils/BaseTest.sol";
import {JustaPermissionManager} from "../../src/JustaPermissionManager.sol";

/**
 * @title TestJustaPermissionManagerExecute
 * @notice Comprehensive tests for executeCall() function
 */
contract TestJustaPermissionManagerExecute is BaseTest {
    /*//////////////////////////////////////////////////////////////
                    SUCCESSFUL EXECUTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ExecuteCall_BasicExecution() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();
        JustaPermissionManager.CallPermission memory call = permission.calls[0];

        _approvePermission(permission);

        bytes memory data = abi.encodeWithSelector(target.increment.selector);

        vm.prank(spender);
        manager.executeCall(permission, call, data);

        assertEq(target.counter(), 1);
    }

    function test_ExecuteCall_WithFunctionArguments() public {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({
            target: address(target),
            selector: target.setCounter.selector
        });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](0);

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: address(account),
            spender: spender,
            start: START_TIME,
            end: END_TIME,
            salt: 0,
            calls: calls,
            spends: spends
        });

        _approvePermission(permission);

        bytes memory data = abi.encodeWithSelector(target.setCounter.selector, uint256(42));

        vm.prank(spender);
        manager.executeCall(permission, calls[0], data);

        assertEq(target.counter(), 42);
    }

    function test_ExecuteCall_MultipleTimesInSamePermission() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();
        JustaPermissionManager.CallPermission memory call = permission.calls[0];

        _approvePermission(permission);

        bytes memory data = abi.encodeWithSelector(target.increment.selector);

        // Execute multiple times
        vm.startPrank(spender);
        manager.executeCall(permission, call, data);
        manager.executeCall(permission, call, data);
        manager.executeCall(permission, call, data);
        vm.stopPrank();

        assertEq(target.counter(), 3);
    }

    function test_ExecuteCall_DifferentFunctionsInSamePermission() public {
        JustaPermissionManager.Permission memory permission = _createMultiCallPermission();

        _approvePermission(permission);

        // Execute first call (increment)
        vm.prank(spender);
        manager.executeCall(permission, permission.calls[0], abi.encodeWithSelector(target.increment.selector));

        assertEq(target.counter(), 1);

        // Execute second call (setCounter)
        vm.prank(spender);
        manager.executeCall(permission, permission.calls[1], abi.encodeWithSelector(target.setCounter.selector, 100));

        assertEq(target.counter(), 100);
    }


    /*//////////////////////////////////////////////////////////////
                    VALIDATION ERROR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RevertWhen_ExecuteCall_PermissionNotApproved() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();
        JustaPermissionManager.CallPermission memory call = permission.calls[0];

        bytes memory data = abi.encodeWithSelector(target.increment.selector);

        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(JustaPermissionManager.JustaPermissionManager_UnauthorizedPermission.selector)
        );
        manager.executeCall(permission, call, data);
    }

    function test_RevertWhen_ExecuteCall_PermissionRevoked() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();
        JustaPermissionManager.CallPermission memory call = permission.calls[0];

        _approvePermission(permission);

        // Revoke
        vm.prank(address(account));
        manager.revoke(permission);

        bytes memory data = abi.encodeWithSelector(target.increment.selector);

        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(JustaPermissionManager.JustaPermissionManager_UnauthorizedPermission.selector)
        );
        manager.executeCall(permission, call, data);
    }

    function test_RevertWhen_ExecuteCall_CallerNotSpender() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();
        JustaPermissionManager.CallPermission memory call = permission.calls[0];

        _approvePermission(permission);

        bytes memory data = abi.encodeWithSelector(target.increment.selector);

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_InvalidSender.selector, attacker, spender
            )
        );
        manager.executeCall(permission, call, data);
    }

    function test_RevertWhen_ExecuteCall_BeforeStartTime() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();
        JustaPermissionManager.CallPermission memory call = permission.calls[0];

        _approvePermission(permission);

        vm.warp(START_TIME - 1);

        bytes memory data = abi.encodeWithSelector(target.increment.selector);

        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_BeforePermissionStart.selector,
                uint48(START_TIME - 1),
                START_TIME
            )
        );
        manager.executeCall(permission, call, data);
    }

    function test_RevertWhen_ExecuteCall_AfterEndTime() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();
        JustaPermissionManager.CallPermission memory call = permission.calls[0];

        _approvePermission(permission);

        vm.warp(END_TIME + 1);

        bytes memory data = abi.encodeWithSelector(target.increment.selector);

        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_AfterPermissionEnd.selector,
                uint48(END_TIME + 1),
                END_TIME
            )
        );
        manager.executeCall(permission, call, data);
    }

    function test_RevertWhen_ExecuteCall_InvalidCalldataTooShort() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();
        JustaPermissionManager.CallPermission memory call = permission.calls[0];

        _approvePermission(permission);

        bytes memory data = new bytes(3); // Less than 4 bytes

        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(JustaPermissionManager.JustaPermissionManager_InvalidCalldata.selector)
        );
        manager.executeCall(permission, call, data);
    }

    function test_RevertWhen_ExecuteCall_InvalidCalldataEmpty() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();
        JustaPermissionManager.CallPermission memory call = permission.calls[0];

        _approvePermission(permission);

        bytes memory data = "";

        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(JustaPermissionManager.JustaPermissionManager_InvalidCalldata.selector)
        );
        manager.executeCall(permission, call, data);
    }

    function test_RevertWhen_ExecuteCall_WrongSelector() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();
        JustaPermissionManager.CallPermission memory call = permission.calls[0];

        _approvePermission(permission);

        // Use setCounter selector instead of increment
        bytes memory data = abi.encodeWithSelector(target.setCounter.selector, 100);

        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_UnauthorizedCall.selector,
                call.target,
                target.setCounter.selector
            )
        );
        manager.executeCall(permission, call, data);
    }

    function test_RevertWhen_ExecuteCall_CallNotInPermission() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        _approvePermission(permission);

        // Try to call a different function not in permission
        JustaPermissionManager.CallPermission memory unauthorizedCall = JustaPermissionManager.CallPermission({
            target: address(target),
            selector: target.setCounter.selector
        });

        bytes memory data = abi.encodeWithSelector(target.setCounter.selector, 100);

        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_UnauthorizedCall.selector,
                unauthorizedCall.target,
                unauthorizedCall.selector
            )
        );
        manager.executeCall(permission, unauthorizedCall, data);
    }

    /*//////////////////////////////////////////////////////////////
                    TIME BOUNDARY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ExecuteCall_AtStartTime() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();
        JustaPermissionManager.CallPermission memory call = permission.calls[0];

        _approvePermission(permission);

        vm.warp(START_TIME); // Exactly at start time

        bytes memory data = abi.encodeWithSelector(target.increment.selector);

        vm.prank(spender);
        manager.executeCall(permission, call, data);

        assertEq(target.counter(), 1);
    }

    function test_RevertWhen_ExecuteCall_AtEndTime() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();
        JustaPermissionManager.CallPermission memory call = permission.calls[0];

        _approvePermission(permission);

        vm.warp(END_TIME); // Exactly at end time - should fail

        bytes memory data = abi.encodeWithSelector(target.increment.selector);

        vm.prank(spender);
        vm.expectRevert();
        manager.executeCall(permission, call, data);

    }

    function test_ExecuteCall_JustBeforeEndTime() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();
        JustaPermissionManager.CallPermission memory call = permission.calls[0];

        _approvePermission(permission);

        vm.warp(END_TIME - 1); // Just before end time

        bytes memory data = abi.encodeWithSelector(target.increment.selector);

        vm.prank(spender);
        manager.executeCall(permission, call, data);

        assertEq(target.counter(), 1);
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_ExecuteCall_AtDifferentTimes(uint48 timestamp) public {
        timestamp = uint48(bound(timestamp, START_TIME, END_TIME - 1));

        JustaPermissionManager.Permission memory permission = _createBasicPermission();
        JustaPermissionManager.CallPermission memory call = permission.calls[0];

        _approvePermission(permission);

        vm.warp(timestamp);

        bytes memory data = abi.encodeWithSelector(target.increment.selector);

        vm.prank(spender);
        manager.executeCall(permission, call, data);

        assertEq(target.counter(), 1);
    }
}
