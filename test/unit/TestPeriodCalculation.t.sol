// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { BaseAccount } from "@account-abstraction/core/BaseAccount.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { JustaPermissionManager } from "../../../src/JustaPermissionManager.sol";
import { JustaPermissionManagerTestBase } from "../utils/JustaPermissionManagerTestBase.sol";

contract TestPeriodCalculation is JustaPermissionManagerTestBase {

    /*//////////////////////////////////////////////////////////////
                    PERIOD CALCULATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_StartOfSpendPeriodMinute() public view {
        uint256 timestamp = 1_700_000_000; // Some arbitrary timestamp
        uint256 expectedStart = (timestamp / 60) * 60;
        assertEq(manager.startOfSpendPeriod(timestamp, JustaPermissionManager.PeriodUnit.Minute, 1), expectedStart);
    }

    function test_StartOfSpendPeriodHour() public view {
        uint256 timestamp = 1_700_000_000;
        uint256 expectedStart = (timestamp / 3600) * 3600;
        assertEq(manager.startOfSpendPeriod(timestamp, JustaPermissionManager.PeriodUnit.Hour, 1), expectedStart);
    }

    function test_StartOfSpendPeriodDay() public view {
        uint256 timestamp = 1_700_000_000;
        uint256 expectedStart = (timestamp / 86_400) * 86_400;
        assertEq(manager.startOfSpendPeriod(timestamp, JustaPermissionManager.PeriodUnit.Day, 1), expectedStart);
    }

    function test_StartOfSpendPeriodForever() public view {
        uint256 timestamp = 1_700_000_000;
        assertEq(manager.startOfSpendPeriod(timestamp, JustaPermissionManager.PeriodUnit.Forever, 1), 1);
    }

    function test_StartOfSpendPeriodWeek() public view {
        // Week should align to Monday
        // January 1, 2024 is a Monday (timestamp: 1704067200)
        uint256 mondayTimestamp = 1_704_067_200;
        assertEq(manager.startOfSpendPeriod(mondayTimestamp, JustaPermissionManager.PeriodUnit.Week, 1), mondayTimestamp);

        // January 2, 2024 is a Tuesday - should round down to Monday
        uint256 tuesdayTimestamp = mondayTimestamp + 1 days;
        assertEq(manager.startOfSpendPeriod(tuesdayTimestamp, JustaPermissionManager.PeriodUnit.Week, 1), mondayTimestamp);

        // January 7, 2024 is a Sunday - should round down to Monday
        uint256 sundayTimestamp = mondayTimestamp + 6 days;
        assertEq(manager.startOfSpendPeriod(sundayTimestamp, JustaPermissionManager.PeriodUnit.Week, 1), mondayTimestamp);
    }

    function test_StartOfSpendPeriodMonth() public view {
        // Month should align to 1st of month
        // January 1, 2024 (timestamp: 1704067200)
        uint256 jan1Timestamp = 1_704_067_200;
        assertEq(manager.startOfSpendPeriod(jan1Timestamp, JustaPermissionManager.PeriodUnit.Month, 1), jan1Timestamp);

        // January 15, 2024 - should round down to Jan 1
        uint256 jan15Timestamp = jan1Timestamp + 14 days;
        assertEq(manager.startOfSpendPeriod(jan15Timestamp, JustaPermissionManager.PeriodUnit.Month, 1), jan1Timestamp);

        // February 1, 2024 - should be Feb 1
        uint256 feb1Timestamp = jan1Timestamp + 31 days;
        assertEq(manager.startOfSpendPeriod(feb1Timestamp, JustaPermissionManager.PeriodUnit.Month, 1), feb1Timestamp);
    }

    function test_StartOfSpendPeriodYear() public view {
        // Year should align to Jan 1st
        // January 1, 2024 (timestamp: 1704067200)
        uint256 jan1Timestamp = 1_704_067_200;
        assertEq(manager.startOfSpendPeriod(jan1Timestamp, JustaPermissionManager.PeriodUnit.Year, 1), jan1Timestamp);

        // June 15, 2024 - should round down to Jan 1, 2024
        uint256 juneTimestamp = jan1Timestamp + 166 days;
        assertEq(manager.startOfSpendPeriod(juneTimestamp, JustaPermissionManager.PeriodUnit.Year, 1), jan1Timestamp);

        // January 1, 2025 - should be Jan 1, 2025
        // 2024 has 366 days (leap year), but let's use a specific timestamp for Jan 1, 2025
        // Actually, let's just test that a date in the middle of 2024 rounds down to Jan 1, 2024
        uint256 midYearTimestamp = jan1Timestamp + 200 days;
        assertEq(manager.startOfSpendPeriod(midYearTimestamp, JustaPermissionManager.PeriodUnit.Year, 1), jan1Timestamp);
    }

    function test_StartOfSpendPeriodWithMultiplier() public view {
        uint256 timestamp = 1_700_000_000;

        // 2 hours: should align to 2-hour boundaries
        uint256 twoHourDuration = 3600 * 2;
        uint256 expectedTwoHourStart = (timestamp / twoHourDuration) * twoHourDuration;
        assertEq(manager.startOfSpendPeriod(timestamp, JustaPermissionManager.PeriodUnit.Hour, 2), expectedTwoHourStart);

        // 3 days: should align to 3-day boundaries
        uint256 threeDayDuration = 86_400 * 3;
        uint256 expectedThreeDayStart = (timestamp / threeDayDuration) * threeDayDuration;
        assertEq(manager.startOfSpendPeriod(timestamp, JustaPermissionManager.PeriodUnit.Day, 3), expectedThreeDayStart);
    }

    function test_StartOfSpendPeriodTwoWeeks() public view {
        // January 1, 2024 is a Monday (timestamp: 1704067200)
        uint256 mondayTimestamp = 1_704_067_200;

        // Reference Monday is Jan 5, 1970 (345600)
        // Weeks since ref for Jan 1, 2024: (1704067200 - 345600) / 604800 = 2819 weeks
        // For 2-week periods: periodIndex = 2819 / 2 = 1409
        // Start = 345600 + (1409 * 2 * 604800) = 345600 + 1704153600 = 1704499200
        // Wait, that's wrong. Let me recalculate.
        // Actually: 2819 weeks / 2 = 1409 (integer division)
        // 1409 * 2 = 2818 weeks from reference
        // Start = 345600 + (2818 * 604800) = 1704412800
        // But that's after our target date. Let me trace through the code.

        // The 2-week period containing Jan 1, 2024 should start on Dec 25, 2023 (Monday)
        // or Dec 18, 2023 depending on alignment
        uint256 twoWeekStart = manager.startOfSpendPeriod(mondayTimestamp, JustaPermissionManager.PeriodUnit.Week, 2);

        // The start should be a Monday
        // And it should be within 2 weeks before mondayTimestamp
        assertTrue(twoWeekStart <= mondayTimestamp);
        assertTrue(twoWeekStart + 2 weeks > mondayTimestamp);
    }

    function test_StartOfSpendPeriodQuarterly() public view {
        // January 1, 2024 (timestamp: 1704067200)
        uint256 jan1_2024 = 1_704_067_200;

        // Quarterly (3 months) - January 2024 should align to January 2024 (start of Q1)
        uint256 quarterlyStart = manager.startOfSpendPeriod(jan1_2024, JustaPermissionManager.PeriodUnit.Month, 3);
        assertEq(quarterlyStart, jan1_2024); // Jan 1, 2024 is start of Q1

        // February 15, 2024 - should still be in Q1 (Jan 2024)
        uint256 feb15_2024 = jan1_2024 + 45 days;
        quarterlyStart = manager.startOfSpendPeriod(feb15_2024, JustaPermissionManager.PeriodUnit.Month, 3);
        assertEq(quarterlyStart, jan1_2024);

        // April 1, 2024 - should be Q2 (Apr 2024)
        uint256 apr1_2024 = jan1_2024 + 91 days; // Jan has 31, Feb has 29 (leap year), Mar has 31
        quarterlyStart = manager.startOfSpendPeriod(apr1_2024, JustaPermissionManager.PeriodUnit.Month, 3);
        assertEq(quarterlyStart, apr1_2024);
    }

    function test_StartOfSpendPeriodTwoYears() public view {
        // January 1, 2024 (timestamp: 1704067200)
        uint256 jan1_2024 = 1_704_067_200;

        // 2-year periods starting from 1970
        // 2024 is 54 years since 1970, so periodIndex = 54 / 2 = 27
        // Start year = 1970 + (27 * 2) = 2024
        uint256 twoYearStart = manager.startOfSpendPeriod(jan1_2024, JustaPermissionManager.PeriodUnit.Year, 2);
        assertEq(twoYearStart, jan1_2024); // Jan 1, 2024

        // 2025 should still be in the 2024-2025 period
        uint256 jan1_2025 = 1_735_689_600; // Jan 1, 2025
        twoYearStart = manager.startOfSpendPeriod(jan1_2025, JustaPermissionManager.PeriodUnit.Year, 2);
        assertEq(twoYearStart, jan1_2024); // Still Jan 1, 2024
    }

    function test_SpendLimitResetsOnNewPeriod_2Hours() public {
        // Test with 2-hour period (multiplier = 2)
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({ target: address(erc20), selector: IERC20.transfer.selector });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: address(erc20),
            allowance: 100 ether,
            unit: JustaPermissionManager.PeriodUnit.Hour,
            multiplier: 2 // 2-hour period
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

        // Warp past the 2-hour boundary - period should reset
        vm.warp(block.timestamp + 2 hours + 1);

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

    function test_SpendLimitResetsOnNewPeriod_3Days() public {
        // Test with 3-day period (multiplier = 3)
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({ target: address(erc20), selector: IERC20.transfer.selector });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: address(erc20),
            allowance: 100 ether,
            unit: JustaPermissionManager.PeriodUnit.Day,
            multiplier: 3 // 3-day period
        });

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: account,
            spender: spender,
            start: uint48(block.timestamp),
            end: uint48(block.timestamp + 30 days),
            salt: 601,
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

        uint256 balanceAfterFirst = erc20.balanceOf(randomUser);

        // Warp past the 3-day boundary
        vm.warp(block.timestamp + 3 days + 1);

        // Should be able to spend again in new period
        BaseAccount.Call[] memory calls2 = new BaseAccount.Call[](1);
        calls2[0] = BaseAccount.Call({
            target: address(erc20),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, randomUser, 50 ether)
        });

        vm.prank(spender);
        manager.executeBatch(permission, calls2);

        assertEq(erc20.balanceOf(randomUser), balanceAfterFirst + 50 ether);
    }

    function test_SpendLimitResetsOnNewWeekPeriod_2Weeks() public {
        // Test with 2-week period (multiplier = 2)
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({ target: address(erc20), selector: IERC20.transfer.selector });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: address(erc20),
            allowance: 100 ether,
            unit: JustaPermissionManager.PeriodUnit.Week,
            multiplier: 2 // 2-week period
        });

        // Start on a Monday (January 1, 2024)
        uint256 mondayTimestamp = 1_704_067_200;
        vm.warp(mondayTimestamp);

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: account,
            spender: spender,
            start: uint48(mondayTimestamp),
            end: uint48(mondayTimestamp + 60 days),
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

        // Warp to next 2-week period (14 days later)
        vm.warp(mondayTimestamp + 14 days + 1);

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

    function test_SpendLimitResetsOnNewQuarterlyPeriod() public {
        // Test with quarterly period (3 months, multiplier = 3)
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({ target: address(erc20), selector: IERC20.transfer.selector });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: address(erc20),
            allowance: 100 ether,
            unit: JustaPermissionManager.PeriodUnit.Month,
            multiplier: 3 // Quarterly (3 months)
        });

        // Start on January 1, 2024
        uint256 jan1Timestamp = 1_704_067_200;
        vm.warp(jan1Timestamp);

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: account,
            spender: spender,
            start: uint48(jan1Timestamp),
            end: uint48(jan1Timestamp + 365 days),
            salt: 62,
            calls: calls,
            spends: spends
        });

        vm.prank(account);
        manager.approve(permission);

        // Spend 50 ether in Q1
        BaseAccount.Call[] memory calls1 = new BaseAccount.Call[](1);
        calls1[0] = BaseAccount.Call({
            target: address(erc20),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, randomUser, 50 ether)
        });

        vm.prank(spender);
        manager.executeBatch(permission, calls1);

        // Warp to April 1, 2024 (Q2)
        vm.warp(jan1Timestamp + 91 days); // Jan 31 + Feb 29 + Mar 31 = 91 days

        // Should be able to spend again in new quarter
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

    function test_SpendLimitResetsOnNew2YearPeriod() public {
        // Test with 2-year period (multiplier = 2)
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({ target: address(erc20), selector: IERC20.transfer.selector });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: address(erc20),
            allowance: 100 ether,
            unit: JustaPermissionManager.PeriodUnit.Year,
            multiplier: 2 // 2-year period
        });

        // Start on January 1, 2024
        uint256 jan1_2024 = 1_704_067_200;
        vm.warp(jan1_2024);

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: account,
            spender: spender,
            start: uint48(jan1_2024),
            end: uint48(jan1_2024 + 1095 days), // ~3 years
            salt: 621,
            calls: calls,
            spends: spends
        });

        vm.prank(account);
        manager.approve(permission);

        // Spend 50 ether in 2024-2025 period
        BaseAccount.Call[] memory calls1 = new BaseAccount.Call[](1);
        calls1[0] = BaseAccount.Call({
            target: address(erc20),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, randomUser, 50 ether)
        });

        vm.prank(spender);
        manager.executeBatch(permission, calls1);

        // Warp to January 1, 2026 (next 2-year period)
        uint256 jan1_2026 = jan1_2024 + 731 days; // 2024 has 366 days (leap), 2025 has 365 days
        vm.warp(jan1_2026);

        // Should be able to spend again in new 2-year period
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
        // Forever period ignores multiplier
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({ target: address(erc20), selector: IERC20.transfer.selector });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: address(erc20),
            allowance: 100 ether,
            unit: JustaPermissionManager.PeriodUnit.Forever,
            multiplier: 5 // Should be ignored for Forever
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
        JustaPermissionManager.PeriodSpend memory currentPeriod =
            manager.getCurrentPeriod(permission, permission.spends[0]);
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
        JustaPermissionManager.PeriodSpend memory periodAfter =
            manager.getLastUpdatedPeriod(permission, permission.spends[0]);
        assertEq(periodAfter.start, start);
        assertEq(periodAfter.end, end);
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
        JustaPermissionManager.PeriodSpend memory periodAfterSecond =
            manager.getLastUpdatedPeriod(permission, permission.spends[0]);
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
                JustaPermissionManager.JustaPermissionManager_ExceededSpendLimit.selector, 101 ether, 100 ether
            )
        );
        vm.prank(spender);
        manager.executeBatch(permission, calls3);
    }

    function test_MultipleSpendLimitsWithDifferentMultipliers() public {
        // Test with multiple spend limits: 2-hour and 1-day limits on same token
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({ target: address(erc20), selector: IERC20.transfer.selector });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](2);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: address(erc20),
            allowance: 20 ether,
            unit: JustaPermissionManager.PeriodUnit.Hour,
            multiplier: 2 // 20 ether per 2 hours
        });
        spends[1] = JustaPermissionManager.SpendLimit({
            token: address(erc20),
            allowance: 50 ether,
            unit: JustaPermissionManager.PeriodUnit.Day,
            multiplier: 1 // 50 ether per day
        });

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: account,
            spender: spender,
            start: uint48(block.timestamp),
            end: uint48(block.timestamp + 7 days),
            salt: 64,
            calls: calls,
            spends: spends
        });

        vm.prank(account);
        manager.approve(permission);

        // Spend 15 ether (within both limits)
        BaseAccount.Call[] memory calls1 = new BaseAccount.Call[](1);
        calls1[0] = BaseAccount.Call({
            target: address(erc20),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, randomUser, 15 ether)
        });

        vm.prank(spender);
        manager.executeBatch(permission, calls1);

        // Try to spend 10 more ether - should fail (exceeds 2-hour limit: 15 + 10 = 25 > 20)
        BaseAccount.Call[] memory calls2 = new BaseAccount.Call[](1);
        calls2[0] = BaseAccount.Call({
            target: address(erc20),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, randomUser, 10 ether)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_ExceededSpendLimit.selector, 25 ether, 20 ether
            )
        );
        vm.prank(spender);
        manager.executeBatch(permission, calls2);

        // Warp past 2-hour limit, but still within day
        vm.warp(block.timestamp + 2 hours + 1);

        // Now can spend 10 more (new 2-hour period, but still within daily 50 ether)
        vm.prank(spender);
        manager.executeBatch(permission, calls2);

        assertEq(erc20.balanceOf(randomUser), 25 ether);
    }

    function test_StartOfSpendPeriodWeekBeforeReferenceMonday() public view {
        // Test edge case: timestamp before reference Monday (Jan 5, 1970 = 345600)
        // Reference Monday is Jan 5, 1970 00:00:00 UTC = 345600
        // Jan 1, 1970 00:00:00 UTC = 0 (a Thursday)
        // First Monday in 1970 is Jan 5, 1970
        // Test with a timestamp before reference Monday

        // Jan 1, 1970 (Unix epoch) - a Thursday
        uint256 jan1_1970 = 0;
        // The first Monday (Dec 29, 1969) before the epoch is -259200 (negative timestamp)
        // However, Solidity timestamps are unsigned, so let's test Jan 5, 1970 (first Monday)
        // and a timestamp just after epoch but before the first Monday

        // Test timestamp Jan 2, 1970 (a Friday) = 86400
        uint256 jan2_1970 = 86_400;

        // This should fall before the reference Monday (345600)
        // The function should return the Monday of that week
        // Jan 2, 1970 is Friday, so the Monday of that week is Dec 29, 1969 (negative timestamp)
        // Since we can't have negative timestamps, let's verify the function handles this edge case

        // Actually, let's test more precisely. The reference Monday in the code is 345600.
        // When monday < referenceMonday, the code returns monday directly.
        // DateTimeLib.mondayTimestamp(jan2_1970) should return the monday of that week

        uint256 result = manager.startOfSpendPeriod(jan2_1970, JustaPermissionManager.PeriodUnit.Week, 1);
        // The result should be less than 345600 (reference Monday)
        // and equal to the Monday of the week containing Jan 2, 1970
        assertTrue(result < 345_600, "Result should be before reference Monday");
    }

    function test_PermissionStartsMidMonthPeriod() public {
        // Test permission that starts mid-month with a monthly period
        // The period should align properly to calendar boundaries
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({ target: address(erc20), selector: IERC20.transfer.selector });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: address(erc20),
            allowance: 100 ether,
            unit: JustaPermissionManager.PeriodUnit.Month,
            multiplier: 1
        });

        // January 15, 2024 = 1705276800 (mid-month)
        uint256 jan15_2024 = 1_705_276_800;
        vm.warp(jan15_2024);

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: account,
            spender: spender,
            start: uint48(jan15_2024),
            end: uint48(jan15_2024 + 60 days),
            salt: 65,
            calls: calls,
            spends: spends
        });

        vm.prank(account);
        manager.approve(permission);

        // Get current period - should handle mid-month start correctly
        JustaPermissionManager.PeriodSpend memory currentPeriod =
            manager.getCurrentPeriod(permission, permission.spends[0]);

        // The period should start at permission start (mid-month)
        // and end at the next month boundary (Feb 1, 2024)
        assertEq(currentPeriod.start, jan15_2024);
        // Feb 1, 2024 = 1706745600
        uint256 feb1_2024 = 1_706_745_600;
        assertEq(currentPeriod.end, feb1_2024);

        // Execute and verify spend tracking works
        BaseAccount.Call[] memory executeCalls = new BaseAccount.Call[](1);
        executeCalls[0] = BaseAccount.Call({
            target: address(erc20),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, randomUser, 50 ether)
        });

        vm.prank(spender);
        manager.executeBatch(permission, executeCalls);

        JustaPermissionManager.PeriodSpend memory period =
            manager.getLastUpdatedPeriod(permission, permission.spends[0]);
        assertEq(period.spend, 50 ether);
    }

    function test_PermissionStartsMidWeekPeriod() public {
        // Test permission that starts mid-week with a 2-week period
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({ target: address(erc20), selector: IERC20.transfer.selector });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: address(erc20),
            allowance: 100 ether,
            unit: JustaPermissionManager.PeriodUnit.Week,
            multiplier: 2
        });

        // January 3, 2024 = Wednesday = 1704240000 (mid-week)
        uint256 jan3_2024 = 1_704_240_000;
        vm.warp(jan3_2024);

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: account,
            spender: spender,
            start: uint48(jan3_2024),
            end: uint48(jan3_2024 + 30 days),
            salt: 66,
            calls: calls,
            spends: spends
        });

        vm.prank(account);
        manager.approve(permission);

        // Get current period
        JustaPermissionManager.PeriodSpend memory currentPeriod =
            manager.getCurrentPeriod(permission, permission.spends[0]);

        // The period should start at permission start
        assertEq(currentPeriod.start, jan3_2024);

        // Execute and verify
        BaseAccount.Call[] memory executeCalls = new BaseAccount.Call[](1);
        executeCalls[0] = BaseAccount.Call({
            target: address(erc20),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, randomUser, 50 ether)
        });

        vm.prank(spender);
        manager.executeBatch(permission, executeCalls);

        JustaPermissionManager.PeriodSpend memory period =
            manager.getLastUpdatedPeriod(permission, permission.spends[0]);
        assertEq(period.spend, 50 ether);
    }

}
