// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseTest} from "../utils/BaseTest.sol";
import {JustaPermissionManager} from "../../src/JustaPermissionManager.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/**
 * @title TestPermissionFlow
 * @notice Integration tests for complex permission workflows
 */
contract TestPermissionFlow is BaseTest {
    /*//////////////////////////////////////////////////////////////
                    COMPLETE PERMISSION LIFECYCLE
    //////////////////////////////////////////////////////////////*/

    function test_Integration_CompleteCallPermissionLifecycle() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();
        JustaPermissionManager.CallPermission memory call = permission.calls[0];

        // 1. Approve permission
        _approvePermission(permission);
        assertTrue(manager.isApproved(permission));

        // 2. Execute call successfully
        vm.prank(spender);
        manager.executeCall(permission, call, abi.encodeWithSelector(target.increment.selector));
        assertEq(target.counter(), 1);

        // 3. Execute again
        vm.prank(spender);
        manager.executeCall(permission, call, abi.encodeWithSelector(target.increment.selector));
        assertEq(target.counter(), 2);

        // 4. Revoke permission
        vm.prank(address(account));
        manager.revoke(permission);
        assertTrue(manager.isRevoked(permission));

        // 5. Try to use revoked permission - should fail
        vm.prank(spender);
        vm.expectRevert();
        manager.executeCall(permission, call, abi.encodeWithSelector(target.increment.selector));
    }

    function test_Integration_CompleteSpendPermissionLifecycle() public {
        uint160 allowance = 100e18;
        JustaPermissionManager.Permission memory permission = _createSpendPermission(allowance, PERIOD);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        // 1. Approve permission
        _approvePermission(permission);
        _approveTokenSpending();

        // 2. Spend within limit
        vm.prank(spender);
        manager.spend(permission, spendLimit, 30e18);
        assertEq(token.balanceOf(spender), 30e18);

        // 3. Spend more
        vm.prank(spender);
        manager.spend(permission, spendLimit, 40e18);
        assertEq(token.balanceOf(spender), 70e18);

        // 4. Try to exceed limit - should fail
        vm.prank(spender);
        vm.expectRevert();
        manager.spend(permission, spendLimit, 31e18);

        // 5. Move to next period
        vm.warp(START_TIME + PERIOD);

        // 6. Spend in new period
        vm.prank(spender);
        manager.spend(permission, spendLimit, 80e18);
        assertEq(token.balanceOf(spender), 150e18);

        // 7. Revoke by spender
        vm.prank(spender);
        manager.revokeAsSpender(permission);

        // 8. Try to use revoked permission
        vm.prank(spender);
        vm.expectRevert();
        manager.spend(permission, spendLimit, 10e18);
    }

    /*//////////////////////////////////////////////////////////////
                COMBINED PERMISSIONS (CALLS + SPENDS)
    //////////////////////////////////////////////////////////////*/

    function test_Integration_PermissionWithBothCallsAndSpends() public {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({
            target: address(target),
            selector: target.increment.selector
        });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({token: address(token), allowance: 100e18, period: PERIOD});

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
        _approveTokenSpending();

        // Use call permission
        vm.prank(spender);
        manager.executeCall(permission, calls[0], abi.encodeWithSelector(target.increment.selector));
        assertEq(target.counter(), 1);

        // Use spend permission
        vm.prank(spender);
        manager.spend(permission, spends[0], 50e18);
        assertEq(token.balanceOf(spender), 50e18);

        // Revoke affects both
        vm.prank(address(account));
        manager.revoke(permission);

        vm.prank(spender);
        vm.expectRevert();
        manager.executeCall(permission, calls[0], abi.encodeWithSelector(target.increment.selector));

        vm.prank(spender);
        vm.expectRevert();
        manager.spend(permission, spends[0], 10e18);
    }

    /*//////////////////////////////////////////////////////////////
                    MULTIPLE CONCURRENT PERMISSIONS
    //////////////////////////////////////////////////////////////*/

    function test_Integration_MultiplePermissionsForSameSpender() public {
        // Permission 1: Call permission
        JustaPermissionManager.Permission memory permission1 = _createBasicPermission();
        permission1.salt = 0;

        // Permission 2: Spend permission
        JustaPermissionManager.Permission memory permission2 = _createSpendPermission(uint160(100e18), PERIOD);
        permission2.salt = 1;

        // Approve both
        vm.startPrank(address(account));
        manager.approve(permission1);
        manager.approve(permission2);
        vm.stopPrank();

        _approveTokenSpending();

        // Use permission 1
        vm.prank(spender);
        manager.executeCall(
            permission1, permission1.calls[0], abi.encodeWithSelector(target.increment.selector)
        );
        assertEq(target.counter(), 1);

        // Use permission 2
        vm.prank(spender);
        manager.spend(permission2, permission2.spends[0], 50e18);
        assertEq(token.balanceOf(spender), 50e18);

        // Revoke only permission 1
        vm.prank(address(account));
        manager.revoke(permission1);

        // Permission 1 should fail
        vm.prank(spender);
        vm.expectRevert();
        manager.executeCall(
            permission1, permission1.calls[0], abi.encodeWithSelector(target.increment.selector)
        );

        // Permission 2 should still work
        vm.prank(spender);
        manager.spend(permission2, permission2.spends[0], 30e18);
        assertEq(token.balanceOf(spender), 80e18);
    }

    function test_Integration_MultipleSpendsMultipleTokens() public {
        MockERC20 token2 = new MockERC20("Token2", "TK2", 18);
        token2.mint(address(account), 1000e18);

        MockERC20 token3 = new MockERC20("Token3", "TK3", 6);
        token3.mint(address(account), 1000e6);

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](0);
        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](3);
        spends[0] = JustaPermissionManager.SpendLimit({token: address(token), allowance: 100e18, period: PERIOD});
        spends[1] = JustaPermissionManager.SpendLimit({token: address(token2), allowance: 50e18, period: PERIOD});
        spends[2] = JustaPermissionManager.SpendLimit({token: address(token3), allowance: 10e6, period: PERIOD});

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

        // Approve all tokens
        vm.startPrank(address(account));
        token.approve(address(manager), type(uint256).max);
        token2.approve(address(manager), type(uint256).max);
        token3.approve(address(manager), type(uint256).max);
        vm.stopPrank();

        // Spend from each token
        vm.startPrank(spender);
        manager.spend(permission, spends[0], 60e18);
        manager.spend(permission, spends[1], 30e18);
        manager.spend(permission, spends[2], 5e6);
        vm.stopPrank();

        assertEq(token.balanceOf(spender), 60e18);
        assertEq(token2.balanceOf(spender), 30e18);
        assertEq(token3.balanceOf(spender), 5e6);
    }

    /*//////////////////////////////////////////////////////////////
                    TIME-BASED SCENARIOS
    //////////////////////////////////////////////////////////////*/

    function test_Integration_PermissionExpiration() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();
        JustaPermissionManager.CallPermission memory call = permission.calls[0];

        _approvePermission(permission);

        // Use before expiration
        vm.warp(END_TIME - 10);
        vm.prank(spender);
        manager.executeCall(permission, call, abi.encodeWithSelector(target.increment.selector));
        assertEq(target.counter(), 1);

        // Try to use after expiration
        vm.warp(END_TIME + 1);
        vm.prank(spender);
        vm.expectRevert();
        manager.executeCall(permission, call, abi.encodeWithSelector(target.increment.selector));
    }

    function test_Integration_MultiPeriodSpending() public {
        uint160 allowance = 100e18;
        JustaPermissionManager.Permission memory permission = _createSpendPermission(allowance, PERIOD);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        _approvePermission(permission);
        _approveTokenSpending();

        // Mint more tokens for multi-period testing
        token.mint(address(account), 1000e18);

        uint256 totalSpent = 0;

        // Period 1
        vm.prank(spender);
        manager.spend(permission, spendLimit, 80e18);
        totalSpent += 80e18;

        // Period 2
        vm.warp(START_TIME + PERIOD);
        vm.prank(spender);
        manager.spend(permission, spendLimit, 100e18); // Full allowance
        totalSpent += 100e18;

        // Period 3
        vm.warp(START_TIME + 2 * PERIOD);
        vm.prank(spender);
        manager.spend(permission, spendLimit, 60e18);
        totalSpent += 60e18;

        // Period 4
        vm.warp(START_TIME + 3 * PERIOD);
        vm.prank(spender);
        manager.spend(permission, spendLimit, 40e18);
        totalSpent += 40e18;

        assertEq(token.balanceOf(spender), totalSpent);
        assertEq(totalSpent, 280e18);
    }

    /*//////////////////////////////////////////////////////////////
                    FAILURE RECOVERY SCENARIOS
    //////////////////////////////////////////////////////////////*/

    function test_Integration_PartialUseThenRevokeThenNewPermission() public {
        // Original permission
        JustaPermissionManager.Permission memory permission1 = _createSpendPermission(uint160(100e18), PERIOD);
        permission1.salt = 0;

        _approvePermission(permission1);
        _approveTokenSpending();

        // Use partially
        vm.prank(spender);
        manager.spend(permission1, permission1.spends[0], 40e18);

        // Revoke
        vm.prank(address(account));
        manager.revoke(permission1);

        // Create new permission with different salt
        JustaPermissionManager.Permission memory permission2 = _createSpendPermission(uint160(100e18), PERIOD);
        permission2.salt = 1;

        _approvePermission(permission2);

        // Use new permission
        vm.prank(spender);
        manager.spend(permission2, permission2.spends[0], 50e18);

        // Total spent across both permissions
        assertEq(token.balanceOf(spender), 90e18);

        // Old permission still revoked
        assertTrue(manager.isRevoked(permission1));
        assertFalse(manager.isRevoked(permission2));
    }

    /*//////////////////////////////////////////////////////////////
                    EDGE CASE SCENARIOS
    //////////////////////////////////////////////////////////////*/

    function test_Integration_MaxAllowanceSpending() public {
        uint160 maxAllowance = type(uint160).max;
        JustaPermissionManager.Permission memory permission = _createSpendPermission(maxAllowance, PERIOD);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        // Mint enough tokens
        token.mint(address(account), maxAllowance);

        _approvePermission(permission);
        _approveTokenSpending();

        uint160 spendAmount = 1000e18;

        vm.prank(spender);
        manager.spend(permission, spendLimit, spendAmount);

        assertEq(token.balanceOf(spender), spendAmount);
    }

    function test_Integration_VeryShortPeriod() public {
        uint160 allowance = 100e18;
        uint48 shortPeriod = 10; // 10 seconds

        JustaPermissionManager.Permission memory permission = _createSpendPermission(allowance, shortPeriod);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        _approvePermission(permission);
        _approveTokenSpending();

        // Period 1
        vm.prank(spender);
        manager.spend(permission, spendLimit, 50e18);

        // Move to next period (just 10 seconds later)
        vm.warp(START_TIME + shortPeriod);

        // Period 2
        vm.prank(spender);
        manager.spend(permission, spendLimit, 50e18);

        assertEq(token.balanceOf(spender), 100e18);
    }
}
