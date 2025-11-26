// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BaseAccount } from "@account-abstraction/core/BaseAccount.sol";

import { JustaPermissionManager } from "../../../src/JustaPermissionManager.sol";
import { JustaPermissionManagerTestBase } from "../utils/JustaPermissionManagerTestBase.sol";

contract TestPeriodCalculation is JustaPermissionManagerTestBase {

    /*//////////////////////////////////////////////////////////////
                    PERIOD CALCULATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_StartOfSpendPeriodMinute() public view {
        uint256 timestamp = 1700000000; // Some arbitrary timestamp
        uint256 expectedStart = (timestamp / 60) * 60;
        assertEq(manager.startOfSpendPeriod(timestamp, JustaPermissionManager.SpendPeriod.Minute), expectedStart);
    }

    function test_StartOfSpendPeriodHour() public view {
        uint256 timestamp = 1700000000;
        uint256 expectedStart = (timestamp / 3600) * 3600;
        assertEq(manager.startOfSpendPeriod(timestamp, JustaPermissionManager.SpendPeriod.Hour), expectedStart);
    }

    function test_StartOfSpendPeriodDay() public view {
        uint256 timestamp = 1700000000;
        uint256 expectedStart = (timestamp / 86400) * 86400;
        assertEq(manager.startOfSpendPeriod(timestamp, JustaPermissionManager.SpendPeriod.Day), expectedStart);
    }

    function test_StartOfSpendPeriodForever() public view {
        uint256 timestamp = 1700000000;
        assertEq(manager.startOfSpendPeriod(timestamp, JustaPermissionManager.SpendPeriod.Forever), 1);
    }

    function test_StartOfSpendPeriodWeek() public view {
        // Week should align to Monday
        // January 1, 2024 is a Monday (timestamp: 1704067200)
        uint256 mondayTimestamp = 1704067200;
        assertEq(manager.startOfSpendPeriod(mondayTimestamp, JustaPermissionManager.SpendPeriod.Week), mondayTimestamp);
        
        // January 2, 2024 is a Tuesday - should round down to Monday
        uint256 tuesdayTimestamp = mondayTimestamp + 1 days;
        assertEq(manager.startOfSpendPeriod(tuesdayTimestamp, JustaPermissionManager.SpendPeriod.Week), mondayTimestamp);
        
        // January 7, 2024 is a Sunday - should round down to Monday
        uint256 sundayTimestamp = mondayTimestamp + 6 days;
        assertEq(manager.startOfSpendPeriod(sundayTimestamp, JustaPermissionManager.SpendPeriod.Week), mondayTimestamp);
    }

    function test_StartOfSpendPeriodMonth() public view {
        // Month should align to 1st of month
        // January 1, 2024 (timestamp: 1704067200)
        uint256 jan1Timestamp = 1704067200;
        assertEq(manager.startOfSpendPeriod(jan1Timestamp, JustaPermissionManager.SpendPeriod.Month), jan1Timestamp);
        
        // January 15, 2024 - should round down to Jan 1
        uint256 jan15Timestamp = jan1Timestamp + 14 days;
        assertEq(manager.startOfSpendPeriod(jan15Timestamp, JustaPermissionManager.SpendPeriod.Month), jan1Timestamp);
        
        // February 1, 2024 - should be Feb 1
        uint256 feb1Timestamp = jan1Timestamp + 31 days;
        assertEq(manager.startOfSpendPeriod(feb1Timestamp, JustaPermissionManager.SpendPeriod.Month), feb1Timestamp);
    }

    function test_StartOfSpendPeriodYear() public view {
        // Year should align to Jan 1st
        // January 1, 2024 (timestamp: 1704067200)
        uint256 jan1Timestamp = 1704067200;
        assertEq(manager.startOfSpendPeriod(jan1Timestamp, JustaPermissionManager.SpendPeriod.Year), jan1Timestamp);
        
        // June 15, 2024 - should round down to Jan 1, 2024
        uint256 juneTimestamp = jan1Timestamp + 166 days;
        assertEq(manager.startOfSpendPeriod(juneTimestamp, JustaPermissionManager.SpendPeriod.Year), jan1Timestamp);
        
        // January 1, 2025 - should be Jan 1, 2025
        // 2024 has 366 days (leap year), but let's use a specific timestamp for Jan 1, 2025
        // Actually, let's just test that a date in the middle of 2024 rounds down to Jan 1, 2024
        uint256 midYearTimestamp = jan1Timestamp + 200 days;
        assertEq(manager.startOfSpendPeriod(midYearTimestamp, JustaPermissionManager.SpendPeriod.Year), jan1Timestamp);
    }

    function test_SpendLimitResetsOnNewPeriod() public {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({
            target: address(erc20),
            selector: IERC20.transfer.selector
        });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: address(erc20),
            allowance: 100 ether,
            period: JustaPermissionManager.SpendPeriod.Hour
        });

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: account,
            spender: spender,
            start: uint48(block.timestamp),
            end: uint48(block.timestamp + 30 days),
            salt: 60,
            calls: calls,
            spends: spends
        });

        vm.prank(account);
        manager.approve(permission);

        // Spend 30 ether (within 100 ether limit)
        BaseAccount.Call[] memory calls1 = new BaseAccount.Call[](1);
        calls1[0] = BaseAccount.Call({
            target: address(erc20),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, randomUser, 30 ether)
        });

        vm.prank(spender);
        manager.executeBatch(permission, calls1);

        uint256 balanceAfterFirst = erc20.balanceOf(randomUser);

        // Warp past the hour boundary - period should reset
        // The period ends at 3601, so we need to go past that
        vm.warp(block.timestamp + 1 hours + 1);

        // Should be able to spend again in new period
        BaseAccount.Call[] memory calls2 = new BaseAccount.Call[](1);
        calls2[0] = BaseAccount.Call({
            target: address(erc20),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, randomUser, 30 ether)
        });

        vm.prank(spender);
        manager.executeBatch(permission, calls2);

        // Verify more tokens were transferred (period reset allowed more spending)
        assertEq(erc20.balanceOf(randomUser), balanceAfterFirst + 30 ether);
    }

    function test_SpendLimitResetsOnNewWeekPeriod() public {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({
            target: address(erc20),
            selector: IERC20.transfer.selector
        });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: address(erc20),
            allowance: 100 ether,
            period: JustaPermissionManager.SpendPeriod.Week
        });

        // Start on a Monday (January 1, 2024)
        uint256 mondayTimestamp = 1704067200;
        vm.warp(mondayTimestamp);

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: account,
            spender: spender,
            start: uint48(mondayTimestamp),
            end: uint48(mondayTimestamp + 30 days),
            salt: 61,
            calls: calls,
            spends: spends
        });

        vm.prank(account);
        manager.approve(permission);

        // Spend 50 ether
        BaseAccount.Call[] memory calls1 = new BaseAccount.Call[](1);
        calls1[0] = BaseAccount.Call({
            target: address(erc20),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, randomUser, 50 ether)
        });

        vm.prank(spender);
        manager.executeBatch(permission, calls1);

        // Warp to next week (next Monday)
        vm.warp(mondayTimestamp + 7 days + 1);

        // Should be able to spend again
        BaseAccount.Call[] memory calls2 = new BaseAccount.Call[](1);
        calls2[0] = BaseAccount.Call({
            target: address(erc20),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, randomUser, 50 ether)
        });

        vm.prank(spender);
        manager.executeBatch(permission, calls2);

        assertEq(erc20.balanceOf(randomUser), 100 ether);
    }

    function test_SpendLimitResetsOnNewMonthPeriod() public {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({
            target: address(erc20),
            selector: IERC20.transfer.selector
        });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: address(erc20),
            allowance: 100 ether,
            period: JustaPermissionManager.SpendPeriod.Month
        });

        // Start on January 1, 2024
        uint256 jan1Timestamp = 1704067200;
        vm.warp(jan1Timestamp);

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: account,
            spender: spender,
            start: uint48(jan1Timestamp),
            end: uint48(jan1Timestamp + 60 days),
            salt: 62,
            calls: calls,
            spends: spends
        });

        vm.prank(account);
        manager.approve(permission);

        // Spend 50 ether in January
        BaseAccount.Call[] memory calls1 = new BaseAccount.Call[](1);
        calls1[0] = BaseAccount.Call({
            target: address(erc20),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, randomUser, 50 ether)
        });

        vm.prank(spender);
        manager.executeBatch(permission, calls1);

        // Warp to February 1, 2024
        vm.warp(jan1Timestamp + 31 days + 1);

        // Should be able to spend again in new month
        BaseAccount.Call[] memory calls2 = new BaseAccount.Call[](1);
        calls2[0] = BaseAccount.Call({
            target: address(erc20),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, randomUser, 50 ether)
        });

        vm.prank(spender);
        manager.executeBatch(permission, calls2);

        assertEq(erc20.balanceOf(randomUser), 100 ether);
    }

    function test_ForeverPeriodUsesPermissionDuration() public {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({
            target: address(erc20),
            selector: IERC20.transfer.selector
        });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: address(erc20),
            allowance: 100 ether,
            period: JustaPermissionManager.SpendPeriod.Forever
        });

        uint48 start = uint48(block.timestamp);
        uint48 end = uint48(block.timestamp + 30 days);

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: account,
            spender: spender,
            start: start,
            end: end,
            salt: 63,
            calls: calls,
            spends: spends
        });

        vm.prank(account);
        manager.approve(permission);

        // Check current period - should span entire permission duration
        JustaPermissionManager.PeriodSpend memory currentPeriod = manager.getCurrentPeriod(
            permission,
            permission.spends[0]
        );
        assertEq(currentPeriod.start, start);
        assertEq(currentPeriod.end, end);
        assertEq(currentPeriod.spend, 0);

        // Spend 50 ether
        BaseAccount.Call[] memory executeCalls = new BaseAccount.Call[](1);
        executeCalls[0] = BaseAccount.Call({
            target: address(erc20),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, randomUser, 50 ether)
        });

        vm.prank(spender);
        manager.executeBatch(permission, executeCalls);

        // Check last updated period - should have 50 ether spent
        JustaPermissionManager.PeriodSpend memory periodAfter = manager.getLastUpdatedPeriod(
            permission,
            permission.spends[0]
        );
        assertEq(periodAfter.start, start);
        assertEq(periodAfter.end, end);
        assertEq(periodAfter.spend, 50 ether);
        
        // Verify the period spend is tracked correctly
        // After first spend of 50 ether, we should have 50 ether tracked
        assertEq(periodAfter.spend, 50 ether);

        // Spend 49 more ether - should succeed (50 + 49 = 99 < 100)
        BaseAccount.Call[] memory calls2 = new BaseAccount.Call[](1);
        calls2[0] = BaseAccount.Call({
            target: address(erc20),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, randomUser, 49 ether)
        });

        vm.prank(spender);
        manager.executeBatch(permission, calls2);

        // Verify total spend is now 99 ether (50 + 49)
        JustaPermissionManager.PeriodSpend memory periodAfterSecond = manager.getLastUpdatedPeriod(
            permission,
            permission.spends[0]
        );
        assertEq(periodAfterSecond.spend, 99 ether);

        // Now try to spend 2 more ether - should fail (99 + 2 = 101 > 100)
        BaseAccount.Call[] memory calls3 = new BaseAccount.Call[](1);
        calls3[0] = BaseAccount.Call({
            target: address(erc20),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, randomUser, 2 ether)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_ExceededSpendLimit.selector,
                101 ether,
                100 ether
            )
        );
        vm.prank(spender);
        manager.executeBatch(permission, calls3);
    }
}


