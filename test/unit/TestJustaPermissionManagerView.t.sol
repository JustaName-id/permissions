// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseTest} from "../utils/BaseTest.sol";
import {JustaPermissionManager} from "../../src/JustaPermissionManager.sol";

/**
 * @title TestJustaPermissionManagerView
 * @notice Tests for view functions: isApproved(), isRevoked(), getCurrentPeriod(), getLastUpdatedPeriod(), getHash()
 */
contract TestJustaPermissionManagerView is BaseTest {
    /*//////////////////////////////////////////////////////////////
                    IS APPROVED TESTS
    //////////////////////////////////////////////////////////////*/

    function test_IsApproved_NotApprovedYet() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        assertFalse(manager.isApproved(permission));
    }

    function test_IsApproved_AfterApproval() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        _approvePermission(permission);

        assertTrue(manager.isApproved(permission));
    }

    function test_IsApproved_AfterRevoke_StillTrue() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        _approvePermission(permission);

        vm.prank(address(account));
        manager.revoke(permission);

        // isApproved still returns true (check isRevoked separately)
        assertTrue(manager.isApproved(permission));
    }

    /*//////////////////////////////////////////////////////////////
                    IS REVOKED TESTS
    //////////////////////////////////////////////////////////////*/

    function test_IsRevoked_NotRevokedYet() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        assertFalse(manager.isRevoked(permission));
    }

    function test_IsRevoked_AfterRevoke() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        _approvePermission(permission);

        vm.prank(address(account));
        manager.revoke(permission);

        assertTrue(manager.isRevoked(permission));
    }

    function test_IsRevoked_WithoutApproval() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        // Revoke without approving first
        vm.prank(address(account));
        manager.revoke(permission);

        assertTrue(manager.isRevoked(permission));
    }

    function test_IsRevoked_AfterRevokeAsSpender() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        _approvePermission(permission);

        vm.prank(spender);
        manager.revokeAsSpender(permission);

        assertTrue(manager.isRevoked(permission));
    }

    /*//////////////////////////////////////////////////////////////
                    GET HASH TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetHash_Deterministic() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        bytes32 hash1 = manager.getHash(permission);
        bytes32 hash2 = manager.getHash(permission);

        assertEq(hash1, hash2);
    }

    function test_GetHash_DifferentWithDifferentSalt() public {
        JustaPermissionManager.Permission memory permission1 = _createBasicPermission();
        permission1.salt = 0;

        JustaPermissionManager.Permission memory permission2 = _createBasicPermission();
        permission2.salt = 1;

        bytes32 hash1 = manager.getHash(permission1);
        bytes32 hash2 = manager.getHash(permission2);

        assertTrue(hash1 != hash2);
    }

    function test_GetHash_DifferentWithDifferentSpender() public {
        JustaPermissionManager.Permission memory permission1 = _createBasicPermission();
        permission1.spender = spender;

        JustaPermissionManager.Permission memory permission2 = _createBasicPermission();
        permission2.spender = attacker;

        bytes32 hash1 = manager.getHash(permission1);
        bytes32 hash2 = manager.getHash(permission2);

        assertTrue(hash1 != hash2);
    }

    function test_GetHash_DifferentWithDifferentTimeRange() public {
        JustaPermissionManager.Permission memory permission1 = _createBasicPermission();
        permission1.start = START_TIME;
        permission1.end = END_TIME;

        JustaPermissionManager.Permission memory permission2 = _createBasicPermission();
        permission2.start = START_TIME + 100;
        permission2.end = END_TIME + 100;

        bytes32 hash1 = manager.getHash(permission1);
        bytes32 hash2 = manager.getHash(permission2);

        assertTrue(hash1 != hash2);
    }

    /*//////////////////////////////////////////////////////////////
                    GET CURRENT PERIOD TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetCurrentPeriod_FirstPeriod() public {
        uint160 allowance = 100e18;
        JustaPermissionManager.Permission memory permission = _createSpendPermission(allowance, PERIOD);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        vm.warp(START_TIME);

        JustaPermissionManager.PeriodSpend memory period = manager.getCurrentPeriod(permission, spendLimit);

        assertEq(period.start, START_TIME);
        assertEq(period.spend, 0);
    }

    function test_GetCurrentPeriod_MidPermission() public {
        uint160 allowance = 100e18;
        JustaPermissionManager.Permission memory permission = _createSpendPermission(allowance, PERIOD);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        vm.warp(START_TIME + PERIOD + 50);

        JustaPermissionManager.PeriodSpend memory period = manager.getCurrentPeriod(permission, spendLimit);

        assertEq(period.start, START_TIME + PERIOD);
        assertEq(period.spend, 0);
    }

    function test_GetCurrentPeriod_AfterSpending() public {
        uint160 allowance = 100e18;
        JustaPermissionManager.Permission memory permission = _createSpendPermission(allowance, PERIOD);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        _approvePermission(permission);
        _approveTokenSpending();

        // Spend some amount
        vm.prank(spender);
        manager.spend(permission, spendLimit, 30e18);

        JustaPermissionManager.PeriodSpend memory period = manager.getCurrentPeriod(permission, spendLimit);

        assertEq(period.start, START_TIME);
        assertEq(period.spend, 30e18);
    }

    function test_GetCurrentPeriod_MultipleSpends() public {
        uint160 allowance = 100e18;
        JustaPermissionManager.Permission memory permission = _createSpendPermission(allowance, PERIOD);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        _approvePermission(permission);
        _approveTokenSpending();

        // Multiple spends in same period
        vm.startPrank(spender);
        manager.spend(permission, spendLimit, 20e18);
        manager.spend(permission, spendLimit, 30e18);
        vm.stopPrank();

        JustaPermissionManager.PeriodSpend memory period = manager.getCurrentPeriod(permission, spendLimit);

        assertEq(period.start, START_TIME);
        assertEq(period.spend, 50e18);
    }

    function test_GetCurrentPeriod_DifferentPeriod() public {
        uint160 allowance = 100e18;
        JustaPermissionManager.Permission memory permission = _createSpendPermission(allowance, PERIOD);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        _approvePermission(permission);
        _approveTokenSpending();

        // Spend in first period
        vm.prank(spender);
        manager.spend(permission, spendLimit, 40e18);

        // Move to second period
        vm.warp(START_TIME + PERIOD);

        JustaPermissionManager.PeriodSpend memory period = manager.getCurrentPeriod(permission, spendLimit);

        assertEq(period.start, START_TIME + PERIOD);
        assertEq(period.spend, 0); // New period, spend resets
    }

    /*//////////////////////////////////////////////////////////////
                GET LAST UPDATED PERIOD TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetLastUpdatedPeriod_NoSpendYet() public {
        uint160 allowance = 100e18;
        JustaPermissionManager.Permission memory permission = _createSpendPermission(allowance, PERIOD);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        _approvePermission(permission);

        JustaPermissionManager.PeriodSpend memory period = manager.getLastUpdatedPeriod(permission, spendLimit);

        // Should return zero values if never spent
        assertEq(period.start, 0);
        assertEq(period.spend, 0);
    }

    function test_GetLastUpdatedPeriod_AfterFirstSpend() public {
        uint160 allowance = 100e18;
        JustaPermissionManager.Permission memory permission = _createSpendPermission(allowance, PERIOD);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        _approvePermission(permission);
        _approveTokenSpending();

        // First spend
        vm.prank(spender);
        manager.spend(permission, spendLimit, 30e18);

        JustaPermissionManager.PeriodSpend memory period = manager.getLastUpdatedPeriod(permission, spendLimit);

        assertEq(period.start, START_TIME);
        assertEq(period.spend, 30e18);
    }

    function test_GetLastUpdatedPeriod_AfterMultipleSpends() public {
        uint160 allowance = 100e18;
        JustaPermissionManager.Permission memory permission = _createSpendPermission(allowance, PERIOD);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        _approvePermission(permission);
        _approveTokenSpending();

        vm.startPrank(spender);
        manager.spend(permission, spendLimit, 20e18);
        manager.spend(permission, spendLimit, 15e18);
        vm.stopPrank();

        JustaPermissionManager.PeriodSpend memory period = manager.getLastUpdatedPeriod(permission, spendLimit);

        assertEq(period.start, START_TIME);
        assertEq(period.spend, 35e18);
    }

    function test_GetLastUpdatedPeriod_AcrossPeriods() public {
        uint160 allowance = 100e18;
        JustaPermissionManager.Permission memory permission = _createSpendPermission(allowance, PERIOD);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        _approvePermission(permission);
        _approveTokenSpending();

        // Spend in first period
        vm.prank(spender);
        manager.spend(permission, spendLimit, 40e18);

        // Move to second period and spend
        vm.warp(START_TIME + PERIOD);
        vm.prank(spender);
        manager.spend(permission, spendLimit, 50e18);

        JustaPermissionManager.PeriodSpend memory period = manager.getLastUpdatedPeriod(permission, spendLimit);

        // Should return the last updated period (second period)
        assertEq(period.start, START_TIME + PERIOD);
        assertEq(period.spend, 50e18);
    }

    /*//////////////////////////////////////////////////////////////
                    COMBINED VIEW TESTS
    //////////////////////////////////////////////////////////////*/

    function test_View_ApprovedButNotRevoked() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        _approvePermission(permission);

        assertTrue(manager.isApproved(permission));
        assertFalse(manager.isRevoked(permission));
    }

    function test_View_ApprovedAndRevoked() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        _approvePermission(permission);

        vm.prank(address(account));
        manager.revoke(permission);

        assertTrue(manager.isApproved(permission));
        assertTrue(manager.isRevoked(permission));
    }

    function test_View_NotApprovedButRevoked() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        // Revoke without approving
        vm.prank(address(account));
        manager.revoke(permission);

        assertFalse(manager.isApproved(permission));
        assertTrue(manager.isRevoked(permission));
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_GetHash_ConsistentAcrossCalls(uint256 salt) public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();
        permission.salt = salt;

        bytes32 hash1 = manager.getHash(permission);
        bytes32 hash2 = manager.getHash(permission);
        bytes32 hash3 = manager.getHash(permission);

        assertEq(hash1, hash2);
        assertEq(hash2, hash3);
    }

    function testFuzz_GetCurrentPeriod_AtDifferentTimes(uint48 timestamp) public {
        timestamp = uint48(bound(timestamp, START_TIME, END_TIME - 1));

        uint160 allowance = 100e18;
        JustaPermissionManager.Permission memory permission = _createSpendPermission(allowance, PERIOD);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        vm.warp(timestamp);

        JustaPermissionManager.PeriodSpend memory period = manager.getCurrentPeriod(permission, spendLimit);

        // Period start should be within permission range
        assertTrue(period.start >= START_TIME);
        assertTrue(period.start <= END_TIME);
        assertEq(period.spend, 0);
    }
}
