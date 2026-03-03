// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";

import { PreparePermission } from "../../script/PreparePermission.s.sol";
import { JustaPermissionManager } from "../../src/JustaPermissionManager.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";

contract TestReadFunctions is Test, PreparePermission {

    JustaPermissionManager public manager;
    ERC20Mock public mockToken;

    function setUp() public {
        manager = new JustaPermissionManager();
        mockToken = new ERC20Mock();
    }

    /*//////////////////////////////////////////////////////////////
                        CONSTANT VALUE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ShouldReturnCorrectNativeToken() public view {
        assertEq(manager.NATIVE_TOKEN(), NATIVE_TOKEN);
    }

    function test_ShouldReturnCorrectPermit2Address() public view {
        assertEq(manager.PERMIT2(), PERMIT2);
    }

    function test_ShouldReturnCorrectAnyTarget() public view {
        assertEq(manager.ANY_TARGET(), ANY_TARGET);
    }

    function test_ShouldReturnCorrectAnyFnSel() public view {
        assertEq(manager.ANY_FN_SEL(), ANY_FN_SEL);
    }

    function test_ShouldReturnCorrectEmptyCalldataFnSel() public view {
        assertEq(manager.EMPTY_CALLDATA_FN_SEL(), EMPTY_CALLDATA_FN_SEL);
    }

    /*//////////////////////////////////////////////////////////////
                        TYPEHASH TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ShouldReturnCorrectCallPermissionTypehash() public view {
        assertEq(manager.CALL_PERMISSION_TYPEHASH(), CALL_PERMISSION_TYPEHASH);
    }

    function test_ShouldReturnCorrectSpendLimitTypehash() public view {
        assertEq(manager.SPEND_LIMIT_TYPEHASH(), SPEND_LIMIT_TYPEHASH);
    }

    function test_ShouldReturnCorrectPermissionTypehash() public view {
        assertEq(manager.PERMISSION_TYPEHASH(), PERMISSION_TYPEHASH);
    }

    /*//////////////////////////////////////////////////////////////
                        isApproved() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_IsApproved_ShouldReturnFalseForUnapprovedPermission(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint16 multiplier
    )
        public
        view
    {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
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

        assertFalse(manager.isApproved(permission));
    }

    function test_IsApproved_ShouldReturnTrueForApprovedPermission(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint16 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
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

        assertTrue(manager.isApproved(permission));
    }

    function test_IsApproved_ShouldReturnTrueEvenAfterRevoked(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint16 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
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
        manager.revoke(permission);

        assertTrue(manager.isApproved(permission));
        assertTrue(manager.isRevoked(permission));
    }

    /*//////////////////////////////////////////////////////////////
                        isRevoked() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_IsRevoked_ShouldReturnFalseForNonRevokedPermission(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint16 multiplier
    )
        public
        view
    {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
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

        assertFalse(manager.isRevoked(permission));
    }

    function test_IsRevoked_ShouldReturnTrueForRevokedPermission(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint16 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
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
        manager.revoke(permission);

        assertTrue(manager.isRevoked(permission));
    }

    /*//////////////////////////////////////////////////////////////
                        getHash() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetHash_ShouldReturnNonZeroHash(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint16 multiplier
    )
        public
        view
    {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
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

        bytes32 hash = manager.getHash(permission);

        assertTrue(hash != bytes32(0));
    }

    function test_GetHash_ShouldReturnSameHashForSamePermission(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint16 multiplier
    )
        public
        view
    {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        JustaPermissionManager.Permission memory permission1 = createBasicPermission(
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

        JustaPermissionManager.Permission memory permission2 = createBasicPermission(
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

        assertEq(manager.getHash(permission1), manager.getHash(permission2));
    }

    function test_GetHash_ShouldReturnDifferentHashForDifferentSalt(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint16 multiplier,
        uint256 salt1,
        uint256 salt2
    )
        public
        view
    {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);
        vm.assume(salt1 != salt2);

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCall(address(mockToken), selector);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] =
            createSpendLimit(address(mockToken), allowance, JustaPermissionManager.PeriodUnit(periodUnit), multiplier);

        JustaPermissionManager.Permission memory permission1 = createPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            salt1,
            calls,
            spends
        );

        JustaPermissionManager.Permission memory permission2 = createPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            salt2,
            calls,
            spends
        );

        assertTrue(manager.getHash(permission1) != manager.getHash(permission2));
    }

    function test_GetHash_ShouldReturnDifferentHashForDifferentSpender(
        address spender1,
        address spender2,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint16 multiplier
    )
        public
        view
    {
        vm.assume(spender1 != address(0));
        vm.assume(spender2 != address(0));
        vm.assume(spender1 != spender2);
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        JustaPermissionManager.Permission memory permission1 = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender1,
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

        JustaPermissionManager.Permission memory permission2 = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender2,
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

        assertTrue(manager.getHash(permission1) != manager.getHash(permission2));
    }

    /*//////////////////////////////////////////////////////////////
                        getLastUpdatedPeriod() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetLastUpdatedPeriod_ShouldReturnZeroForUnusedPermission(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint16 multiplier
    )
        public
        view
    {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
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

        JustaPermissionManager.SpendLimit memory spendLimit =
            createSpendLimit(address(mockToken), allowance, JustaPermissionManager.PeriodUnit(periodUnit), multiplier);

        JustaPermissionManager.PeriodSpend memory periodSpend = manager.getLastUpdatedPeriod(permission, spendLimit);

        assertEq(periodSpend.start, 0);
        assertEq(periodSpend.end, 0);
        assertEq(periodSpend.spend, 0);
    }

    function test_GetLastUpdatedPeriod_ShouldReturnZeroEvenAfterApproval(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint16 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
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

        JustaPermissionManager.SpendLimit memory spendLimit =
            createSpendLimit(address(mockToken), allowance, JustaPermissionManager.PeriodUnit(periodUnit), multiplier);

        JustaPermissionManager.PeriodSpend memory periodSpend = manager.getLastUpdatedPeriod(permission, spendLimit);

        // Approval doesn't update lastUpdatedPeriod, only executeBatch does
        assertEq(periodSpend.start, 0);
        assertEq(periodSpend.end, 0);
        assertEq(periodSpend.spend, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        getCurrentPeriod() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetCurrentPeriod_ShouldReturnValidPeriod(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint16 multiplier
    )
        public
        view
    {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
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

        JustaPermissionManager.SpendLimit memory spendLimit =
            createSpendLimit(address(mockToken), allowance, JustaPermissionManager.PeriodUnit(periodUnit), multiplier);

        JustaPermissionManager.PeriodSpend memory periodSpend = manager.getCurrentPeriod(permission, spendLimit);

        assertTrue(periodSpend.start > 0);
        assertTrue(periodSpend.end > periodSpend.start);
        assertEq(periodSpend.spend, 0);
    }

    function test_GetCurrentPeriod_ShouldRevertIfBeforePermissionStart(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint16 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp + 1 days),
            uint48(block.timestamp + 2 days),
            0,
            address(mockToken),
            selector,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        JustaPermissionManager.SpendLimit memory spendLimit =
            createSpendLimit(address(mockToken), allowance, JustaPermissionManager.PeriodUnit(periodUnit), multiplier);

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_BeforePermissionStart.selector,
                uint48(block.timestamp),
                uint48(block.timestamp + 1 days)
            )
        );

        manager.getCurrentPeriod(permission, spendLimit);
    }

    function test_GetCurrentPeriod_ShouldRevertIfAfterPermissionEnd(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint16 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        uint48 start = uint48(block.timestamp);
        uint48 end = uint48(block.timestamp + 1 days);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            start,
            end,
            0,
            address(mockToken),
            selector,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        JustaPermissionManager.SpendLimit memory spendLimit =
            createSpendLimit(address(mockToken), allowance, JustaPermissionManager.PeriodUnit(periodUnit), multiplier);

        // Calculate expected timestamp after warp BEFORE warping
        uint48 expectedTimestampAfterWarp = uint48(block.timestamp + 2 days);

        // Warp past permission end
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_AfterPermissionEnd.selector,
                expectedTimestampAfterWarp,
                end
            )
        );

        manager.getCurrentPeriod(permission, spendLimit);
    }

    /*//////////////////////////////////////////////////////////////
                    startOfSpendPeriod() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_StartOfSpendPeriod_ForeverReturnsOne(
        uint48 permStart,
        uint48 timestamp,
        uint16 multiplier
    )
        public
        view
    {
        vm.assume(permStart > 0);
        vm.assume(timestamp >= permStart);
        vm.assume(multiplier > 0);

        uint256 result = manager.startOfSpendPeriod(
            uint256(timestamp), JustaPermissionManager.PeriodUnit.Forever, multiplier, uint256(permStart)
        );
        assertEq(result, 1);
    }

    function test_StartOfSpendPeriod_FixedUnits_AtPermStartReturnPermStart(
        uint48 permStart,
        uint16 multiplier
    )
        public
        view
    {
        vm.assume(permStart > 0);
        vm.assume(multiplier > 0);

        assertEq(
            manager.startOfSpendPeriod(
                uint256(permStart), JustaPermissionManager.PeriodUnit.Minute, multiplier, uint256(permStart)
            ),
            uint256(permStart)
        );
        assertEq(
            manager.startOfSpendPeriod(
                uint256(permStart), JustaPermissionManager.PeriodUnit.Hour, multiplier, uint256(permStart)
            ),
            uint256(permStart)
        );
        assertEq(
            manager.startOfSpendPeriod(
                uint256(permStart), JustaPermissionManager.PeriodUnit.Day, multiplier, uint256(permStart)
            ),
            uint256(permStart)
        );
        assertEq(
            manager.startOfSpendPeriod(
                uint256(permStart), JustaPermissionManager.PeriodUnit.Week, multiplier, uint256(permStart)
            ),
            uint256(permStart)
        );
    }

    function test_StartOfSpendPeriod_FixedUnit_ShouldAlignToPermStart(
        uint48 permStart,
        uint8 periodUnit,
        uint16 multiplier,
        uint48 elapsed
    )
        public
        view
    {
        vm.assume(permStart > 0);
        vm.assume(periodUnit <= 3);
        vm.assume(multiplier > 0);
        vm.assume(elapsed > 0);

        uint256 duration;
        if (periodUnit == 0) {
            duration = 60 * uint256(multiplier);
        } else if (periodUnit == 1) {
            duration = 3600 * uint256(multiplier);
        } else if (periodUnit == 2) {
            duration = 86_400 * uint256(multiplier);
        } else {
            duration = 604_800 * uint256(multiplier);
        }

        uint256 timestamp = uint256(permStart) + uint256(elapsed);

        uint256 result = manager.startOfSpendPeriod(
            timestamp, JustaPermissionManager.PeriodUnit(periodUnit), multiplier, uint256(permStart)
        );

        uint256 expected = uint256(permStart) + (uint256(elapsed) / duration) * duration;
        assertEq(result, expected);
        assertTrue(result <= timestamp);
        assertTrue(result + duration > timestamp);
    }

    function test_StartOfSpendPeriod_LargeMultiplier(uint16 multiplier, uint48 permStart, uint48 elapsed) public view {
        vm.assume(multiplier > 255);
        vm.assume(permStart > 0);
        vm.assume(elapsed > 0);

        uint256 duration = 60 * uint256(multiplier);
        uint256 timestamp = uint256(permStart) + uint256(elapsed);

        uint256 result = manager.startOfSpendPeriod(
            timestamp, JustaPermissionManager.PeriodUnit.Minute, multiplier, uint256(permStart)
        );

        uint256 expected = uint256(permStart) + (uint256(elapsed) / duration) * duration;
        assertEq(result, expected);
    }

    function test_StartOfSpendPeriod_MaxMultiplier() public view {
        // multiplier=65535 (max uint16) with Minute
        uint256 permStart = 1_736_899_200;
        uint256 periodDuration = uint256(65_535) * 60; // 3932100 seconds
        // Midway through period 0
        uint256 timestamp = permStart + periodDuration / 2;

        uint256 result =
            manager.startOfSpendPeriod(timestamp, JustaPermissionManager.PeriodUnit.Minute, 65_535, permStart);
        assertEq(result, permStart, "Max uint16 multiplier should not overflow in period 0");

        // Just past period 0
        uint256 timestamp2 = permStart + periodDuration + 1;

        uint256 result2 =
            manager.startOfSpendPeriod(timestamp2, JustaPermissionManager.PeriodUnit.Minute, 65_535, permStart);
        assertEq(result2, permStart + periodDuration, "Max uint16 multiplier: period 1 start");
    }

    function test_StartOfSpendPeriod_Month_ViaPublicFunction() public view {
        // Permission starts Jan 15 2025 00:00:00 UTC
        uint256 permStart = 1_736_899_200;
        // Timestamp = Feb 20 2025 00:00:00 UTC = 1740009600
        // monthsElapsed = (2025*12+2) - (2025*12+1) = 1 → periodIndex = 1/1 = 1
        // periodStart = addMonths(Jan 15, 1) = Feb 15 2025 00:00:00 UTC = 1739577600
        uint256 timestamp = 1_740_009_600;

        uint256 result = manager.startOfSpendPeriod(timestamp, JustaPermissionManager.PeriodUnit.Month, 1, permStart);
        assertEq(result, 1_739_577_600, "Month period should return Feb 15 (addMonths(Jan 15, 1))");
    }

    function test_StartOfSpendPeriod_FixedUnit_WithPermStartZero(
        uint48 timestamp,
        uint8 periodUnit,
        uint16 multiplier
    )
        public
        view
    {
        vm.assume(timestamp > 0);
        vm.assume(periodUnit <= 3);
        vm.assume(multiplier > 0);

        uint256 duration;
        if (periodUnit == 0) {
            duration = 60 * uint256(multiplier);
        } else if (periodUnit == 1) {
            duration = 3600 * uint256(multiplier);
        } else if (periodUnit == 2) {
            duration = 86_400 * uint256(multiplier);
        } else {
            duration = 604_800 * uint256(multiplier);
        }

        uint256 result =
            manager.startOfSpendPeriod(uint256(timestamp), JustaPermissionManager.PeriodUnit(periodUnit), multiplier, 0);

        // With permStart=0, periods align to epoch
        uint256 expected = (uint256(timestamp) / duration) * duration;
        assertEq(result, expected);
        assertTrue(result <= uint256(timestamp));
        assertTrue(result + duration > uint256(timestamp));
    }

    function test_StartOfSpendPeriod_Month_WithPermStartZero() public view {
        // permStart = 0 → Jan 1, 1970 00:00:00 UTC
        // timestamp = Jan 15 2025 00:00:00 UTC = 1736899200
        // monthsElapsed = (2025*12+1) - (1970*12+1) = 660
        // periodStart = addMonths(0, 660) = Jan 1 2025 00:00:00 UTC = 1735689600
        uint256 result = manager.startOfSpendPeriod(1_736_899_200, JustaPermissionManager.PeriodUnit.Month, 1, 0);
        assertEq(result, 1_735_689_600, "Month with permStart=0 should produce Jan 1 2025");
    }

    function test_StartOfSpendPeriod_Month_ShouldHandleAddMonthsOvershoot() public view {
        // permStart = Jan 31 2025 12:00:00 UTC = 1738324800
        // timestamp = Feb 20 2025 00:00:00 UTC = 1740009600
        // monthsElapsed = 1, periodIndex = 1
        // addMonths(Jan 31 12:00, 1) = Feb 28 12:00 = 1740744000
        // 1740744000 > 1740009600 → overshoot, periodIndex -= 1 = 0
        // periodStart = addMonths(Jan 31 12:00, 0) = Jan 31 12:00 = 1738324800
        uint256 result =
            manager.startOfSpendPeriod(1_740_009_600, JustaPermissionManager.PeriodUnit.Month, 1, 1_738_324_800);
        assertEq(result, 1_738_324_800, "Month overshoot should fall back to previous period");
    }

    /*//////////////////////////////////////////////////////////////
                getCurrentPeriod() ALIGNMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetCurrentPeriod_ShouldAlignBoundsToPermissionStart(
        address spender,
        uint160 allowance,
        uint16 multiplier,
        uint48 permStart
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(allowance > 0);
        vm.assume(multiplier > 0);
        vm.assume(permStart > 0);

        uint256 duration = 86_400 * uint256(multiplier);
        vm.assume(uint256(permStart) + duration + 30 days <= type(uint48).max);

        uint48 permEnd = uint48(uint256(permStart) + duration + 30 days);

        vm.warp(permStart);

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCall(address(mockToken), TRANSFER_SELECTOR);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(address(mockToken), allowance, JustaPermissionManager.PeriodUnit.Day, multiplier);

        JustaPermissionManager.Permission memory permission =
            createPermission(TEST_ACCOUNT_ADDRESS, spender, permStart, permEnd, 0, calls, spends);

        JustaPermissionManager.PeriodSpend memory period = manager.getCurrentPeriod(permission, spends[0]);

        assertEq(period.start, permStart);
        assertEq(period.end, uint48(uint256(permStart) + duration));
        assertEq(period.spend, 0);
    }

    function test_GetCurrentPeriod_WeekShouldAlignToPermStart_NotMonday(
        address spender,
        uint160 allowance,
        uint16 multiplier,
        uint48 permStart
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(allowance > 0);
        vm.assume(multiplier > 0);
        vm.assume(permStart > 0);

        uint256 duration = 604_800 * uint256(multiplier);
        vm.assume(uint256(permStart) + duration + 60 days <= type(uint48).max);

        uint48 permEnd = uint48(uint256(permStart) + duration + 60 days);

        vm.warp(permStart);

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCall(address(mockToken), TRANSFER_SELECTOR);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(address(mockToken), allowance, JustaPermissionManager.PeriodUnit.Week, multiplier);

        JustaPermissionManager.Permission memory permission =
            createPermission(TEST_ACCOUNT_ADDRESS, spender, permStart, permEnd, 0, calls, spends);

        JustaPermissionManager.PeriodSpend memory period = manager.getCurrentPeriod(permission, spends[0]);

        assertEq(period.start, permStart);
        assertEq(period.end, uint48(uint256(permStart) + duration));
    }

    function test_GetCurrentPeriod_ForeverShouldSpanEntirePermission(
        address spender,
        uint160 allowance,
        uint48 permStart,
        uint48 permDuration
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(allowance > 0);
        vm.assume(permStart > 0);
        vm.assume(permDuration > 0);
        vm.assume(uint256(permStart) + uint256(permDuration) <= type(uint48).max);

        uint48 permEnd = uint48(uint256(permStart) + uint256(permDuration));

        vm.warp(permStart);

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCall(address(mockToken), TRANSFER_SELECTOR);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(address(mockToken), allowance, JustaPermissionManager.PeriodUnit.Forever, 1);

        JustaPermissionManager.Permission memory permission =
            createPermission(TEST_ACCOUNT_ADDRESS, spender, permStart, permEnd, 0, calls, spends);

        JustaPermissionManager.PeriodSpend memory period = manager.getCurrentPeriod(permission, spends[0]);

        assertEq(period.start, permStart);
        assertEq(period.end, permEnd);
        assertEq(period.spend, 0);
    }

}
