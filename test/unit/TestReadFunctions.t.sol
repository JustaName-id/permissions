// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";

import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { PreparePermission } from "../../script/PreparePermission.s.sol";
import { JustaPermissionManager } from "../../src/JustaPermissionManager.sol";

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
        uint8 multiplier
    ) public view {
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

        assertFalse(manager.isApproved(permission));
    }

    function test_IsApproved_ShouldReturnTrueForApprovedPermission(
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

        assertTrue(manager.isApproved(permission));
    }

    // TODO: check if this is okay to have
    function test_IsApproved_ShouldReturnTrueEvenAfterRevoked(
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
        uint8 multiplier
    ) public view {
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

        assertFalse(manager.isRevoked(permission));
    }

    function test_IsRevoked_ShouldReturnTrueForRevokedPermission(
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
        manager.revoke(permission);

        assertTrue(manager.isRevoked(permission));
    }

    // TODO: check if this is okay to have
    function test_IsRevoked_ShouldReturnTrueForPreventiveRevocation(
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

        // Revoke without approving first (preventive revocation)
        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.revoke(permission);

        assertTrue(manager.isRevoked(permission));
        assertFalse(manager.isApproved(permission));
    }

    /*//////////////////////////////////////////////////////////////
                        getHash() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetHash_ShouldReturnNonZeroHash(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    ) public view {
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

        bytes32 hash = manager.getHash(permission);

        assertTrue(hash != bytes32(0));
    }

    function test_GetHash_ShouldReturnSameHashForSamePermission(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    ) public view {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 6);
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
        uint8 multiplier,
        uint256 salt1,
        uint256 salt2
    ) public view {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 6);
        vm.assume(multiplier > 0);
        vm.assume(salt1 != salt2);

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCall(address(mockToken), selector);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(
            address(mockToken),
            allowance,
            JustaPermissionManager.PeriodUnit(periodUnit),
            multiplier
        );

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
        uint8 multiplier
    ) public view {
        vm.assume(spender1 != address(0));
        vm.assume(spender2 != address(0));
        vm.assume(spender1 != spender2);
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 6);
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
        uint8 multiplier
    ) public view {
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

        JustaPermissionManager.SpendLimit memory spendLimit = createSpendLimit(
            address(mockToken),
            allowance,
            JustaPermissionManager.PeriodUnit(periodUnit),
            multiplier
        );

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

        JustaPermissionManager.SpendLimit memory spendLimit = createSpendLimit(
            address(mockToken),
            allowance,
            JustaPermissionManager.PeriodUnit(periodUnit),
            multiplier
        );

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
        uint8 multiplier
    ) public view {
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

        JustaPermissionManager.SpendLimit memory spendLimit = createSpendLimit(
            address(mockToken),
            allowance,
            JustaPermissionManager.PeriodUnit(periodUnit),
            multiplier
        );

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
            uint48(block.timestamp + 2 days),
            0,
            address(mockToken),
            selector,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        JustaPermissionManager.SpendLimit memory spendLimit = createSpendLimit(
            address(mockToken),
            allowance,
            JustaPermissionManager.PeriodUnit(periodUnit),
            multiplier
        );

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
        uint8 multiplier
    ) public {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 6);
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

        JustaPermissionManager.SpendLimit memory spendLimit = createSpendLimit(
            address(mockToken),
            allowance,
            JustaPermissionManager.PeriodUnit(periodUnit),
            multiplier
        );

        // Warp past permission end
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_AfterPermissionEnd.selector,
                uint48(block.timestamp),
                end
            )
        );

        manager.getCurrentPeriod(permission, spendLimit);
    }
}
