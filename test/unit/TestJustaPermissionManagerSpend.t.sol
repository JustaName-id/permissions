// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseTest} from "../utils/BaseTest.sol";
import {JustaPermissionManager} from "../../src/JustaPermissionManager.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockReentrantToken} from "../mocks/MockReentrantToken.sol";

/**
 * @title TestJustaPermissionManagerSpend
 * @notice Comprehensive tests for spend() function and spend limit management
 */
contract TestJustaPermissionManagerSpend is BaseTest {
    /*//////////////////////////////////////////////////////////////
                    SUCCESSFUL SPENDING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Spend_BasicSpend() public {
        uint160 allowance = 100e18;
        JustaPermissionManager.Permission memory permission = _createSpendPermission(allowance, PERIOD);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        _approvePermission(permission);
        _approveTokenSpending();

        uint160 spendAmount = 50e18;
        uint256 initialBalance = token.balanceOf(address(account));

        vm.prank(spender);
        manager.spend(permission, spendLimit, spendAmount);

        assertEq(token.balanceOf(address(account)), initialBalance - spendAmount);
        assertEq(token.balanceOf(spender), spendAmount);
    }

    function test_Spend_ExactlyAtLimit() public {
        uint160 allowance = 100e18;
        JustaPermissionManager.Permission memory permission = _createSpendPermission(allowance, PERIOD);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        _approvePermission(permission);
        _approveTokenSpending();

        vm.prank(spender);
        manager.spend(permission, spendLimit, allowance);

        assertEq(token.balanceOf(spender), allowance);
    }

    function test_Spend_MultipleSpendsFillingUpLimit() public {
        uint160 allowance = 100e18;
        JustaPermissionManager.Permission memory permission = _createSpendPermission(allowance, PERIOD);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        _approvePermission(permission);
        _approveTokenSpending();

        vm.startPrank(spender);
        manager.spend(permission, spendLimit, 30e18);
        manager.spend(permission, spendLimit, 40e18);
        manager.spend(permission, spendLimit, 30e18); // Total = 100e18
        vm.stopPrank();

        assertEq(token.balanceOf(spender), 100e18);
    }

    function test_Spend_NewPeriodResetsLimit() public {
        uint160 allowance = 100e18;
        JustaPermissionManager.Permission memory permission = _createSpendPermission(allowance, PERIOD);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        _approvePermission(permission);
        _approveTokenSpending();

        // First period: spend 90e18
        vm.prank(spender);
        manager.spend(permission, spendLimit, 90e18);

        // Move to next period
        vm.warp(START_TIME + PERIOD);

        // Second period: spend another 90e18
        vm.prank(spender);
        manager.spend(permission, spendLimit, 90e18);

        assertEq(token.balanceOf(spender), 180e18);
    }

    function test_Spend_MultiplePeriods() public {
        uint160 allowance = 100e18;
        JustaPermissionManager.Permission memory permission = _createSpendPermission(allowance, PERIOD);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        _approvePermission(permission);
        _approveTokenSpending();

        // Period 1
        vm.prank(spender);
        manager.spend(permission, spendLimit, 80e18);

        // Period 2
        vm.warp(START_TIME + PERIOD);
        vm.prank(spender);
        manager.spend(permission, spendLimit, 90e18);

        // Period 3
        vm.warp(START_TIME + 2 * PERIOD);
        vm.prank(spender);
        manager.spend(permission, spendLimit, 70e18);

        assertEq(token.balanceOf(spender), 240e18);
    }


    /*//////////////////////////////////////////////////////////////
                    VALIDATION ERROR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RevertWhen_Spend_PermissionNotApproved() public {
        JustaPermissionManager.Permission memory permission = _createSpendPermission(uint160(100e18), PERIOD);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(JustaPermissionManager.JustaPermissionManager_UnauthorizedPermission.selector)
        );
        manager.spend(permission, spendLimit, 50e18);
    }

    function test_RevertWhen_Spend_PermissionRevoked() public {
        JustaPermissionManager.Permission memory permission = _createSpendPermission(uint160(100e18), PERIOD);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        _approvePermission(permission);
        _approveTokenSpending();

        // Revoke
        vm.prank(address(account));
        manager.revoke(permission);

        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(JustaPermissionManager.JustaPermissionManager_UnauthorizedPermission.selector)
        );
        manager.spend(permission, spendLimit, 50e18);
    }

    function test_RevertWhen_Spend_CallerNotSpender() public {
        JustaPermissionManager.Permission memory permission = _createSpendPermission(uint160(100e18), PERIOD);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        _approvePermission(permission);
        _approveTokenSpending();

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_InvalidSender.selector, attacker, spender
            )
        );
        manager.spend(permission, spendLimit, 50e18);
    }

    function test_RevertWhen_Spend_ZeroValue() public {
        JustaPermissionManager.Permission memory permission = _createSpendPermission(uint160(100e18), PERIOD);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        _approvePermission(permission);
        _approveTokenSpending();

        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(JustaPermissionManager.JustaPermissionManager_ZeroValue.selector));
        manager.spend(permission, spendLimit, 0);
    }

    function test_RevertWhen_Spend_ExceedsLimitInSingleSpend() public {
        uint160 allowance = 100e18;
        JustaPermissionManager.Permission memory permission = _createSpendPermission(allowance, PERIOD);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        _approvePermission(permission);
        _approveTokenSpending();

        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_ExceededSpendLimit.selector, 101e18, allowance
            )
        );
        manager.spend(permission, spendLimit, 101e18);
    }

    function test_RevertWhen_Spend_ExceedsLimitAcrossMultipleSpends() public {
        uint160 allowance = 100e18;
        JustaPermissionManager.Permission memory permission = _createSpendPermission(allowance, PERIOD);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        _approvePermission(permission);
        _approveTokenSpending();

        vm.startPrank(spender);
        manager.spend(permission, spendLimit, 60e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_ExceededSpendLimit.selector, 101e18, allowance
            )
        );
        manager.spend(permission, spendLimit, 41e18);
        vm.stopPrank();
    }

    function test_RevertWhen_Spend_SpendLimitNotInPermission() public {
        JustaPermissionManager.Permission memory permission = _createSpendPermission(uint160(100e18), PERIOD);

        _approvePermission(permission);
        _approveTokenSpending();

        // Create a different spend limit not in permission
        JustaPermissionManager.SpendLimit memory unauthorizedLimit =
            JustaPermissionManager.SpendLimit({token: address(token), allowance: 50e18, period: PERIOD * 2});

        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(JustaPermissionManager.JustaPermissionManager_UnauthorizedPermission.selector)
        );
        manager.spend(permission, unauthorizedLimit, 30e18);
    }

    function test_RevertWhen_Spend_BeforeStartTime() public {
        JustaPermissionManager.Permission memory permission = _createSpendPermission(uint160(100e18), PERIOD);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        _approvePermission(permission);
        _approveTokenSpending();

        vm.warp(START_TIME - 1);

        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_BeforePermissionStart.selector,
                uint48(START_TIME - 1),
                START_TIME
            )
        );
        manager.spend(permission, spendLimit, 50e18);
    }

    function test_RevertWhen_Spend_AfterEndTime() public {
        JustaPermissionManager.Permission memory permission = _createSpendPermission(uint160(100e18), PERIOD);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        _approvePermission(permission);
        _approveTokenSpending();

        vm.warp(END_TIME + 1);

        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_AfterPermissionEnd.selector,
                uint48(END_TIME + 1),
                END_TIME
            )
        );
        manager.spend(permission, spendLimit, 50e18);
    }

    /*//////////////////////////////////////////////////////////////
                    PERIOD BOUNDARY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Spend_AtPeriodBoundary() public {
        uint160 allowance = 100e18;
        JustaPermissionManager.Permission memory permission = _createSpendPermission(allowance, PERIOD);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        _approvePermission(permission);
        _approveTokenSpending();

        // Spend at end of first period
        vm.warp(START_TIME + PERIOD - 1);
        vm.prank(spender);
        manager.spend(permission, spendLimit, 90e18);

        // Spend at start of second period (exactly at boundary)
        vm.warp(START_TIME + PERIOD);
        vm.prank(spender);
        manager.spend(permission, spendLimit, 90e18);

        assertEq(token.balanceOf(spender), 180e18);
    }

    function test_Spend_PartialFinalPeriod() public {
        uint160 allowance = 100e18;
        uint48 customEnd = START_TIME + PERIOD + (PERIOD / 2);

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](0);
        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({token: address(token), allowance: allowance, period: PERIOD});

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: address(account),
            spender: spender,
            start: START_TIME,
            end: customEnd,
            salt: 0,
            calls: calls,
            spends: spends
        });

        _approvePermission(permission);
        _approveTokenSpending();

        // Spend in partial last period
        vm.warp(START_TIME + PERIOD + 10);
        vm.prank(spender);
        manager.spend(permission, spends[0], 50e18);

        assertEq(token.balanceOf(spender), 50e18);
    }

    /*//////////////////////////////////////////////////////////////
                    MULTIPLE SPEND LIMITS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Spend_MultipleSpendLimitsInPermission() public {
        MockERC20 token2 = new MockERC20("Token2", "TK2", 18);
        token2.mint(address(account), 1000e18);

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](0);
        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](2);
        spends[0] = JustaPermissionManager.SpendLimit({token: address(token), allowance: 100e18, period: PERIOD});
        spends[1] = JustaPermissionManager.SpendLimit({token: address(token2), allowance: 50e18, period: PERIOD});

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

        // Approve both tokens
        vm.startPrank(address(account));
        token.approve(address(manager), type(uint256).max);
        token2.approve(address(manager), type(uint256).max);
        vm.stopPrank();

        // Spend from first token
        vm.prank(spender);
        manager.spend(permission, spends[0], 60e18);

        // Spend from second token
        vm.prank(spender);
        manager.spend(permission, spends[1], 30e18);

        assertEq(token.balanceOf(spender), 60e18);
        assertEq(token2.balanceOf(spender), 30e18);
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Spend_WithinLimit(uint160 amount) public {
        uint160 allowance = 100e18;
        amount = uint160(bound(amount, 1, allowance));

        JustaPermissionManager.Permission memory permission = _createSpendPermission(allowance, PERIOD);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        _approvePermission(permission);
        _approveTokenSpending();

        vm.prank(spender);
        manager.spend(permission, spendLimit, amount);

        assertEq(token.balanceOf(spender), amount);
    }

    function testFuzz_Spend_MultiplePeriods(uint8 numPeriods) public {
        numPeriods = uint8(bound(numPeriods, 1, 10));
        uint160 allowance = 100e18;

        JustaPermissionManager.Permission memory permission = _createSpendPermission(allowance, PERIOD);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        _approvePermission(permission);
        _approveTokenSpending();

        // Mint enough tokens
        token.mint(address(account), uint256(numPeriods) * allowance);

        for (uint256 i = 0; i < numPeriods; i++) {
            vm.warp(START_TIME + uint48(i) * PERIOD);

            vm.prank(spender);
            manager.spend(permission, spendLimit, allowance);
        }

        assertEq(token.balanceOf(spender), uint256(numPeriods) * allowance);
    }

    /*//////////////////////////////////////////////////////////////
                    REENTRANCY PROTECTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RevertWhen_Spend_ReentrancyAttack() public {
        MockReentrantToken reentrantToken = new MockReentrantToken();
        reentrantToken.mint(address(account), 1000e18);

        uint160 allowance = 100e18;
        JustaPermissionManager.Permission memory permission = _createSpendPermission(allowance, PERIOD);
        permission.spends[0].token = address(reentrantToken);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        _approvePermission(permission);

        // Approve reentrant token
        vm.prank(address(account));
        reentrantToken.approve(address(manager), type(uint256).max);

        // Setup reentrancy attack
        vm.prank(attacker);
        reentrantToken.setupAttack(
            address(manager),
            permission,
            spendLimit,
            50e18
        );

        // Attempt to spend - should revert due to reentrancy protection
        vm.prank(spender);
        vm.expectRevert(); // Reentrancy() error from ReentrancyGuard
        manager.spend(permission, spendLimit, 50e18);
    }

    /*//////////////////////////////////////////////////////////////
                    NATIVE TOKEN SPENDING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Spend_NativeToken() public {
        uint160 allowance = 10 ether;
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](0);
        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        address nativeToken = manager.NATIVE_TOKEN();
        spends[0] = JustaPermissionManager.SpendLimit({
            token: nativeToken,
            allowance: allowance,
            period: PERIOD
        });

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

        uint160 spendAmount = 5 ether;
        uint256 initialBalance = address(account).balance;
        uint256 spenderInitialBalance = spender.balance;

        vm.prank(spender);
        manager.spend(permission, spends[0], spendAmount);

        assertEq(address(account).balance, initialBalance - spendAmount);
        assertEq(spender.balance, spenderInitialBalance + spendAmount);
    }

    function test_Spend_NativeToken_MultipleSpends() public {
        uint160 allowance = 10 ether;
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](0);
        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        address nativeToken = manager.NATIVE_TOKEN();
        spends[0] = JustaPermissionManager.SpendLimit({
            token: nativeToken,
            allowance: allowance,
            period: PERIOD
        });

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

        vm.startPrank(spender);
        manager.spend(permission, spends[0], 3 ether);
        manager.spend(permission, spends[0], 4 ether);
        vm.stopPrank();

        assertEq(spender.balance, 7 ether);
    }

    function test_Spend_NativeToken_ExceedsLimit() public {
        uint160 allowance = 10 ether;
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](0);
        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        address nativeToken = manager.NATIVE_TOKEN();
        spends[0] = JustaPermissionManager.SpendLimit({
            token: nativeToken,
            allowance: allowance,
            period: PERIOD
        });

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

        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_ExceededSpendLimit.selector,
                11 ether,
                allowance
            )
        );
        manager.spend(permission, spends[0], 11 ether);
    }

    function test_Spend_NativeToken_NewPeriodResets() public {
        uint160 allowance = 10 ether;
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](0);
        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        address nativeToken = manager.NATIVE_TOKEN();
        spends[0] = JustaPermissionManager.SpendLimit({
            token: nativeToken,
            allowance: allowance,
            period: PERIOD
        });

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

        // First period
        vm.prank(spender);
        manager.spend(permission, spends[0], 9 ether);

        // Move to next period
        vm.warp(START_TIME + PERIOD);

        // Second period - should reset
        vm.prank(spender);
        manager.spend(permission, spends[0], 9 ether);

        assertEq(spender.balance, 18 ether);
    }
}
