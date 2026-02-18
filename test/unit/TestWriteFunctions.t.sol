// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";

import { ICallChecker } from "../../src/interfaces/ICallChecker.sol";
import { BaseAccount } from "@account-abstraction/core/BaseAccount.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import { PreparePermission } from "../../script/PreparePermission.s.sol";
import { JustaPermissionManager } from "../../src/JustaPermissionManager.sol";
import { ERC1155Mock } from "../mocks/ERC1155Mock.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { ERC721Mock } from "../mocks/ERC721Mock.sol";

contract TestWriteFunctions is Test, PreparePermission {

    JustaPermissionManager public manager;
    ERC20Mock public mockToken;
    ERC721Mock public mockERC721;
    ERC1155Mock public mockERC1155;

    function setUp() public {
        manager = new JustaPermissionManager();
        mockToken = new ERC20Mock();
        mockERC721 = new ERC721Mock();
        mockERC1155 = new ERC1155Mock();
    }

    /*//////////////////////////////////////////////////////////////
                        approve() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Approve_RevertIfNotAccountOwner(
        address sender,
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(sender != TEST_ACCOUNT_ADDRESS);
        vm.assume(sender != address(0));
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

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_InvalidSender.selector, sender, TEST_ACCOUNT_ADDRESS
            )
        );

        vm.prank(sender);
        manager.approve(permission);
    }

    function test_Approve_RevertIfZeroSpender(
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            address(0),
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

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_ZeroSpender.selector);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);
    }

    function test_Approve_RevertIfStartAfterEnd(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
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
            uint48(block.timestamp),
            0,
            address(mockToken),
            selector,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_InvalidStartEnd.selector,
                uint48(block.timestamp + 1 days),
                uint48(block.timestamp)
            )
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);
    }

    function test_Approve_RevertIfStartEqualsEnd(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        uint48 timestamp = uint48(block.timestamp);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            timestamp,
            timestamp,
            0,
            address(mockToken),
            selector,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_InvalidStartEnd.selector, timestamp, timestamp
            )
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);
    }

    function test_Approve_RevertIfEmptyCallsArray(
        address spender,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](0);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(
            address(mockToken), allowance, JustaPermissionManager.PeriodUnit(periodUnit), multiplier
        );

        JustaPermissionManager.Permission memory permission = createPermission(
            TEST_ACCOUNT_ADDRESS, spender, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0, calls, spends
        );

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_EmptyPermission.selector);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);
    }

    function test_Approve_RevertIfCallTargetsSelf(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
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
            address(manager),
            selector,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_CannotTargetSelf.selector);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);
    }

    function test_Approve_RevertIfCallTargetsAccount(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
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
            TEST_ACCOUNT_ADDRESS,
            selector,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_CannotTargetAccount.selector);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);
    }

    function test_Approve_RevertIfCallTargetIsZero(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
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
            address(0),
            selector,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_ZeroTarget.selector);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);
    }

    function test_Approve_RevertIfCallSelectorIsZero(
        address spender,
        address target,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(target != address(0));
        vm.assume(target != address(manager));
        vm.assume(target != TEST_ACCOUNT_ADDRESS);
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            target,
            bytes4(0),
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_ZeroSelector.selector);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);
    }

    function test_Approve_RevertIfSpendTokenIsZero(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
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
            address(0),
            allowance,
            periodUnit,
            multiplier
        );

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_ZeroToken.selector);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);
    }

    function test_Approve_RevertIfSpendAllowanceIsZero(
        address spender,
        bytes4 selector,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
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
            0,
            periodUnit,
            multiplier
        );

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_ZeroAllowance.selector);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);
    }

    function test_Approve_RevertIfSpendMultiplierIsZero(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);

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
            0
        );

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_ZeroMultiplier.selector);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);
    }

    function test_Approve_RevertIfSpendTokenIsERC721(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
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
            address(mockERC721),
            allowance,
            periodUnit,
            multiplier
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_ERC721TokenNotSupported.selector, address(mockERC721)
            )
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);
    }

    function test_Approve_RevertIfSpendTokenIsERC1155(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
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
            address(mockERC1155),
            allowance,
            periodUnit,
            multiplier
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_ERC1155TokenNotSupported.selector, address(mockERC1155)
            )
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);
    }

    function test_Approve_RevertIfDuplicateSpendLimits(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCall(address(mockToken), selector);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](2);
        spends[0] = createSpendLimit(
            address(mockToken), allowance, JustaPermissionManager.PeriodUnit(periodUnit), multiplier
        );
        spends[1] = createSpendLimit(
            address(mockToken), allowance, JustaPermissionManager.PeriodUnit(periodUnit), multiplier
        );

        JustaPermissionManager.Permission memory permission = createPermission(
            TEST_ACCOUNT_ADDRESS, spender, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0, calls, spends
        );

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_DuplicateSpendLimit.selector);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);
    }

    function test_Approve_RevertIfAlreadyRevoked(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
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

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_UnauthorizedPermission.selector);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);
    }

    function test_Approve_ShouldReturnTrueIfAlreadyApproved(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
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
        bool result = manager.approve(permission);

        assertTrue(result);
    }

    function test_Approve_ShouldApprovePermissionAndEmitEvent(
        address spender,
        bytes4 selector,
        address checker,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);
        // Checker can be address(0) or any valid address except manager and account
        vm.assume(checker != address(manager));
        vm.assume(checker != TEST_ACCOUNT_ADDRESS);
        if (checker != address(0)) {
            vm.assume(uint160(checker) > 0xff); // Exclude precompiles
        }

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCallWithChecker(address(mockToken), selector, checker);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(
            address(mockToken), allowance, JustaPermissionManager.PeriodUnit(periodUnit), multiplier
        );

        JustaPermissionManager.Permission memory permission = createPermission(
            TEST_ACCOUNT_ADDRESS, spender, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0, calls, spends
        );

        // Deploy code at checker address if non-zero
        if (checker != address(0)) {
            vm.etch(checker, hex"00");
        }

        bytes32 expectedHash = manager.getHash(permission);

        vm.expectEmit(true, false, false, true, address(manager));
        emit JustaPermissionManager.PermissionApproved(expectedHash, permission);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        bool result = manager.approve(permission);

        assertTrue(result);
        assertTrue(manager.isApproved(permission));
    }

    function test_Approve_RevertIfCheckerTargetsSelf(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCallWithChecker(address(mockToken), selector, address(manager));

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(
            address(mockToken), allowance, JustaPermissionManager.PeriodUnit(periodUnit), multiplier
        );

        JustaPermissionManager.Permission memory permission = createPermission(
            TEST_ACCOUNT_ADDRESS, spender, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0, calls, spends
        );

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_CannotTargetSelf.selector);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);
    }

    function test_Approve_RevertIfCheckerTargetsAccount(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCallWithChecker(address(mockToken), selector, TEST_ACCOUNT_ADDRESS);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(
            address(mockToken), allowance, JustaPermissionManager.PeriodUnit(periodUnit), multiplier
        );

        JustaPermissionManager.Permission memory permission = createPermission(
            TEST_ACCOUNT_ADDRESS, spender, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0, calls, spends
        );

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_CannotTargetAccount.selector);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);
    }

    function test_Approve_RevertIfCheckerHasNoCode(
        address spender,
        address eoaChecker,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);
        // Ensure eoaChecker is not a contract (no code) and not special addresses
        vm.assume(eoaChecker != address(0));
        vm.assume(eoaChecker != address(manager));
        vm.assume(eoaChecker != TEST_ACCOUNT_ADDRESS);
        vm.assume(eoaChecker.code.length == 0);

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCallWithChecker(address(mockToken), selector, eoaChecker);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(
            address(mockToken), allowance, JustaPermissionManager.PeriodUnit(periodUnit), multiplier
        );

        JustaPermissionManager.Permission memory permission = createPermission(
            TEST_ACCOUNT_ADDRESS, spender, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0, calls, spends
        );

        vm.expectRevert(
            abi.encodeWithSelector(JustaPermissionManager.JustaPermissionManager_CheckerHasNoCode.selector, eoaChecker)
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);
    }

    /*//////////////////////////////////////////////////////////////
                        revoke() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Revoke_RevertIfNotAccountOwner(
        address sender,
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(sender != TEST_ACCOUNT_ADDRESS);
        vm.assume(sender != address(0));
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

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_InvalidSender.selector, sender, TEST_ACCOUNT_ADDRESS
            )
        );

        vm.prank(sender);
        manager.revoke(permission);
    }

    function test_Revoke_RevertIfNotApproved(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
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

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_UnauthorizedPermission.selector);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.revoke(permission);
    }

    function test_Revoke_ShouldBeIdempotent(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
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

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.revoke(permission);

        assertTrue(manager.isRevoked(permission));
    }

    function test_Revoke_ShouldRevokeAndEmitEvent(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
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

        bytes32 expectedHash = manager.getHash(permission);

        vm.expectEmit(true, false, false, false, address(manager));
        emit JustaPermissionManager.PermissionRevoked(expectedHash);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.revoke(permission);

        assertTrue(manager.isRevoked(permission));
    }

    /*//////////////////////////////////////////////////////////////
                        revokeAsSpender() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RevokeAsSpender_RevertIfNotSpender(
        address sender,
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(sender != spender);
        vm.assume(sender != address(0));
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

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_InvalidSender.selector, sender, spender
            )
        );

        vm.prank(sender);
        manager.revokeAsSpender(permission);
    }

    function test_RevokeAsSpender_RevertIfNotApproved(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
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

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_UnauthorizedPermission.selector);

        vm.prank(spender);
        manager.revokeAsSpender(permission);
    }

    function test_RevokeAsSpender_ShouldBeIdempotent(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
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

        vm.prank(spender);
        manager.revokeAsSpender(permission);

        assertTrue(manager.isRevoked(permission));

        vm.prank(spender);
        manager.revokeAsSpender(permission);

        assertTrue(manager.isRevoked(permission));
    }

    function test_RevokeAsSpender_ShouldRevokeAndEmitEvent(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
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

        bytes32 expectedHash = manager.getHash(permission);

        vm.expectEmit(true, false, false, false, address(manager));
        emit JustaPermissionManager.PermissionRevoked(expectedHash);

        vm.prank(spender);
        manager.revokeAsSpender(permission);

        assertTrue(manager.isRevoked(permission));
    }

    /*//////////////////////////////////////////////////////////////
                        executeBatch() TESTS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                        PERMISSION VALIDATION
    //////////////////////////////////////////////////////////////*/

    function test_ExecuteBatch_RevertIfNotSpender(
        address sender,
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(sender != spender);
        vm.assume(sender != address(0));
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

        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({ target: address(mockToken), value: 0, data: abi.encodeWithSelector(selector) });

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_InvalidSender.selector, sender, spender
            )
        );

        vm.prank(sender);
        manager.executeBatch(permission, calls);
    }

    function test_ExecuteBatch_RevertIfNotApproved(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
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

        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({ target: address(mockToken), value: 0, data: abi.encodeWithSelector(selector) });

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_UnauthorizedPermission.selector);

        vm.prank(spender);
        manager.executeBatch(permission, calls);
    }

    function test_ExecuteBatch_RevertIfRevoked(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
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

        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({ target: address(mockToken), value: 0, data: abi.encodeWithSelector(selector) });

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_UnauthorizedPermission.selector);

        vm.prank(spender);
        manager.executeBatch(permission, calls);
    }

    function test_ExecuteBatch_RevertIfBeforeStart(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        uint48 futureStart = uint48(block.timestamp + 1 days);
        uint48 futureEnd = uint48(block.timestamp + 2 days);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            futureStart,
            futureEnd,
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

        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({ target: address(mockToken), value: 0, data: abi.encodeWithSelector(selector) });

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_BeforePermissionStart.selector,
                uint48(block.timestamp),
                futureStart
            )
        );

        vm.prank(spender);
        manager.executeBatch(permission, calls);
    }

    function test_ExecuteBatch_RevertIfAfterEnd(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        uint48 pastStart = uint48(block.timestamp);
        uint48 pastEnd = uint48(block.timestamp + 1 days);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            pastStart,
            pastEnd,
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

        uint48 warpedTimestamp = uint48(block.timestamp + 2 days);
        vm.warp(warpedTimestamp);

        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({ target: address(mockToken), value: 0, data: abi.encodeWithSelector(selector) });

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_AfterPermissionEnd.selector, warpedTimestamp, pastEnd
            )
        );

        vm.prank(spender);
        manager.executeBatch(permission, calls);
    }

    function test_ExecuteBatch_RevertIfCallTargetsSelf(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
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

        // Try to call the manager itself
        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({ target: address(manager), value: 0, data: abi.encodeWithSelector(selector) });

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_CannotTargetSelf.selector);

        vm.prank(spender);
        manager.executeBatch(permission, calls);
    }

    function test_ExecuteBatch_RevertIfCallTargetsAccount(
        address spender,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
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

        // Try to call the account itself
        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({ target: TEST_ACCOUNT_ADDRESS, value: 0, data: abi.encodeWithSelector(selector) });

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_CannotTargetAccount.selector);

        vm.prank(spender);
        manager.executeBatch(permission, calls);
    }

    /*//////////////////////////////////////////////////////////////
                        CALL AUTHORIZATION
    //////////////////////////////////////////////////////////////*/

    function test_ExecuteBatch_RevertIfUnauthorizedCall(
        address spender,
        bytes4 permittedSelector,
        bytes4 attemptedSelector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(permittedSelector != bytes4(0));
        vm.assume(attemptedSelector != bytes4(0));
        vm.assume(permittedSelector != attemptedSelector);
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
            permittedSelector,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Try to call with a different selector
        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] =
            BaseAccount.Call({ target: address(mockToken), value: 0, data: abi.encodeWithSelector(attemptedSelector) });

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_UnauthorizedCall.selector,
                address(mockToken),
                attemptedSelector
            )
        );

        vm.prank(spender);
        manager.executeBatch(permission, calls);
    }

    function test_ExecuteBatch_ShouldAllowAnyTargetWildcard(
        address spender,
        address randomTarget,
        bytes4 selector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(randomTarget != address(0));
        vm.assume(randomTarget != address(manager));
        vm.assume(randomTarget != TEST_ACCOUNT_ADDRESS);
        vm.assume(selector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        // Create permission with ANY_TARGET wildcard
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCall(ANY_TARGET, selector);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(NATIVE_TOKEN, allowance, JustaPermissionManager.PeriodUnit(periodUnit), multiplier);

        JustaPermissionManager.Permission memory permission = createPermission(
            TEST_ACCOUNT_ADDRESS, spender, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0, calls, spends
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Mock the account's executeBatch to succeed
        vm.mockCall(TEST_ACCOUNT_ADDRESS, abi.encodeWithSelector(BaseAccount.executeBatch.selector), "");

        // Execute with random target - should succeed due to ANY_TARGET
        BaseAccount.Call[] memory executeCalls = new BaseAccount.Call[](1);
        executeCalls[0] = BaseAccount.Call({ target: randomTarget, value: 0, data: abi.encodeWithSelector(selector) });

        vm.prank(spender);
        manager.executeBatch(permission, executeCalls);
    }

    function test_ExecuteBatch_ShouldAllowAnySelectorWildcard(
        address spender,
        bytes4 randomSelector,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(randomSelector != bytes4(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        // Create permission with ANY_FN_SEL wildcard
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCall(address(mockToken), ANY_FN_SEL);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(NATIVE_TOKEN, allowance, JustaPermissionManager.PeriodUnit(periodUnit), multiplier);

        JustaPermissionManager.Permission memory permission = createPermission(
            TEST_ACCOUNT_ADDRESS, spender, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0, calls, spends
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Mock the account's executeBatch to succeed
        vm.mockCall(TEST_ACCOUNT_ADDRESS, abi.encodeWithSelector(BaseAccount.executeBatch.selector), "");

        // Execute with random selector - should succeed due to ANY_FN_SEL
        BaseAccount.Call[] memory executeCalls = new BaseAccount.Call[](1);
        executeCalls[0] =
            BaseAccount.Call({ target: address(mockToken), value: 0, data: abi.encodeWithSelector(randomSelector) });

        vm.prank(spender);
        manager.executeBatch(permission, executeCalls);
    }

    function test_ExecuteBatch_ShouldAllowEmptyCalldataWithSpecialSelector(
        address spender,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        // Create permission with EMPTY_CALLDATA_FN_SEL
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCall(address(mockToken), EMPTY_CALLDATA_FN_SEL);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(NATIVE_TOKEN, allowance, JustaPermissionManager.PeriodUnit(periodUnit), multiplier);

        JustaPermissionManager.Permission memory permission = createPermission(
            TEST_ACCOUNT_ADDRESS, spender, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0, calls, spends
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Mock the account's executeBatch to succeed
        vm.mockCall(TEST_ACCOUNT_ADDRESS, abi.encodeWithSelector(BaseAccount.executeBatch.selector), "");

        // Execute with empty calldata - should succeed due to EMPTY_CALLDATA_FN_SEL
        BaseAccount.Call[] memory executeCalls = new BaseAccount.Call[](1);
        executeCalls[0] = BaseAccount.Call({ target: address(mockToken), value: 0, data: "" });

        vm.prank(spender);
        manager.executeBatch(permission, executeCalls);
    }

    function test_ExecuteBatch_ShouldRevertOnInvalidCalldataLength(
        address spender,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        // Create permission with EMPTY_CALLDATA_FN_SEL (closest match for partial calldata)
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCall(address(mockToken), EMPTY_CALLDATA_FN_SEL);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(NATIVE_TOKEN, allowance, JustaPermissionManager.PeriodUnit(periodUnit), multiplier);

        JustaPermissionManager.Permission memory permission = createPermission(
            TEST_ACCOUNT_ADDRESS, spender, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0, calls, spends
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        BaseAccount.Call[] memory executeCalls = new BaseAccount.Call[](1);

        // 1 byte of calldata should revert
        executeCalls[0] = BaseAccount.Call({ target: address(mockToken), value: 0, data: hex"aa" });
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(JustaPermissionManager.JustaPermissionManager_InvalidCalldataLength.selector, 1));
        manager.executeBatch(permission, executeCalls);

        // 2 bytes of calldata should revert
        executeCalls[0] = BaseAccount.Call({ target: address(mockToken), value: 0, data: hex"aabb" });
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(JustaPermissionManager.JustaPermissionManager_InvalidCalldataLength.selector, 2));
        manager.executeBatch(permission, executeCalls);

        // 3 bytes of calldata should revert
        executeCalls[0] = BaseAccount.Call({ target: address(mockToken), value: 0, data: hex"aabbcc" });
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(JustaPermissionManager.JustaPermissionManager_InvalidCalldataLength.selector, 3));
        manager.executeBatch(permission, executeCalls);
    }

    /*//////////////////////////////////////////////////////////////
                        CALL CHECKER VALIDATION
    //////////////////////////////////////////////////////////////*/

    function test_ExecuteBatch_ShouldSucceedWithCheckerApproval(
        address spender,
        address recipient,
        address checker,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(recipient != address(0));
        vm.assume(recipient != TEST_ACCOUNT_ADDRESS);
        vm.assume(checker != address(0));
        vm.assume(checker != address(manager));
        vm.assume(checker != TEST_ACCOUNT_ADDRESS);
        vm.assume(uint160(checker) > 0xff); // Exclude precompiles
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        uint160 transferAmount = allowance / 2;
        vm.assume(transferAmount > 0);

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCallWithChecker(address(mockToken), TRANSFER_SELECTOR, checker);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(
            address(mockToken), allowance, JustaPermissionManager.PeriodUnit(periodUnit), multiplier
        );

        JustaPermissionManager.Permission memory permission = createPermission(
            TEST_ACCOUNT_ADDRESS, spender, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0, calls, spends
        );

        // Deploy code at checker address
        vm.etch(checker, hex"00");

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Mock checker to return true
        vm.mockCall(checker, abi.encodeWithSelector(ICallChecker.canExecute.selector), abi.encode(true));

        // Mock the account's executeBatch to succeed
        vm.mockCall(TEST_ACCOUNT_ADDRESS, abi.encodeWithSelector(BaseAccount.executeBatch.selector), "");

        BaseAccount.Call[] memory executeCalls = new BaseAccount.Call[](1);
        executeCalls[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount)
        });

        // Should succeed because checker returns true
        vm.prank(spender);
        manager.executeBatch(permission, executeCalls);
    }

    function test_ExecuteBatch_RevertIfCheckerRejectsCall(
        address spender,
        address recipient,
        address checker,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(recipient != address(0));
        vm.assume(recipient != TEST_ACCOUNT_ADDRESS);
        vm.assume(checker != address(0));
        vm.assume(checker != address(manager));
        vm.assume(checker != TEST_ACCOUNT_ADDRESS);
        vm.assume(uint160(checker) > 0xff); // Exclude precompiles
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        uint160 transferAmount = allowance / 2;
        vm.assume(transferAmount > 0);

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCallWithChecker(address(mockToken), TRANSFER_SELECTOR, checker);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(
            address(mockToken), allowance, JustaPermissionManager.PeriodUnit(periodUnit), multiplier
        );

        JustaPermissionManager.Permission memory permission = createPermission(
            TEST_ACCOUNT_ADDRESS, spender, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0, calls, spends
        );

        // Deploy code at checker address
        vm.etch(checker, hex"00");

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Mock checker to return false
        vm.mockCall(checker, abi.encodeWithSelector(ICallChecker.canExecute.selector), abi.encode(false));

        BaseAccount.Call[] memory executeCalls = new BaseAccount.Call[](1);
        executeCalls[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_CheckerRejectedCall.selector,
                address(mockToken),
                TRANSFER_SELECTOR,
                checker
            )
        );

        vm.prank(spender);
        manager.executeBatch(permission, executeCalls);
    }

    function test_ExecuteBatch_ShouldPassCorrectParamsToChecker(
        address spender,
        address recipient,
        address checker,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(recipient != address(0));
        vm.assume(recipient != TEST_ACCOUNT_ADDRESS);
        vm.assume(checker != address(0));
        vm.assume(checker != address(manager));
        vm.assume(checker != TEST_ACCOUNT_ADDRESS);
        vm.assume(uint160(checker) > 0xff); // Exclude precompiles
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        uint160 transferAmount = allowance / 2;
        vm.assume(transferAmount > 0);

        uint256 callValue = 0;

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCallWithChecker(address(mockToken), TRANSFER_SELECTOR, checker);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(
            address(mockToken), allowance, JustaPermissionManager.PeriodUnit(periodUnit), multiplier
        );

        JustaPermissionManager.Permission memory permission = createPermission(
            TEST_ACCOUNT_ADDRESS, spender, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0, calls, spends
        );

        // Deploy code at checker address
        vm.etch(checker, hex"00");

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        bytes32 permissionHash = manager.getHash(permission);
        bytes memory callData = abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount);

        // Mock checker to return true
        vm.mockCall(checker, abi.encodeWithSelector(ICallChecker.canExecute.selector), abi.encode(true));

        // Expect checker to be called with correct params
        vm.expectCall(
            checker,
            abi.encodeWithSelector(
                ICallChecker.canExecute.selector,
                permissionHash,
                TEST_ACCOUNT_ADDRESS,
                spender,
                address(mockToken),
                callValue,
                callData
            )
        );

        vm.mockCall(TEST_ACCOUNT_ADDRESS, abi.encodeWithSelector(BaseAccount.executeBatch.selector), "");

        BaseAccount.Call[] memory executeCalls = new BaseAccount.Call[](1);
        executeCalls[0] = BaseAccount.Call({ target: address(mockToken), value: callValue, data: callData });

        vm.prank(spender);
        manager.executeBatch(permission, executeCalls);
    }

    function test_ExecuteBatch_ShouldWorkWithoutChecker(
        address spender,
        address recipient,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(recipient != address(0));
        vm.assume(recipient != TEST_ACCOUNT_ADDRESS);
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        uint160 transferAmount = allowance / 2;
        vm.assume(transferAmount > 0);

        // Create permission with no checker (address(0))
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCall(address(mockToken), TRANSFER_SELECTOR);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(
            address(mockToken), allowance, JustaPermissionManager.PeriodUnit(periodUnit), multiplier
        );

        JustaPermissionManager.Permission memory permission = createPermission(
            TEST_ACCOUNT_ADDRESS, spender, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0, calls, spends
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        vm.mockCall(TEST_ACCOUNT_ADDRESS, abi.encodeWithSelector(BaseAccount.executeBatch.selector), "");

        BaseAccount.Call[] memory executeCalls = new BaseAccount.Call[](1);
        executeCalls[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount)
        });

        vm.prank(spender);
        manager.executeBatch(permission, executeCalls);
    }

    function test_ExecuteBatch_ShouldCheckAllCallsWithCheckersBeforeExecution(
        address spender,
        address recipient1,
        address recipient2,
        address checker1,
        address checker2,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(recipient1 != address(0));
        vm.assume(recipient2 != address(0));
        vm.assume(recipient1 != TEST_ACCOUNT_ADDRESS);
        vm.assume(recipient2 != TEST_ACCOUNT_ADDRESS);
        vm.assume(checker1 != address(0));
        vm.assume(checker1 != address(manager));
        vm.assume(checker1 != TEST_ACCOUNT_ADDRESS);
        vm.assume(uint160(checker1) > 0xff); // Exclude precompiles
        vm.assume(checker2 != address(0));
        vm.assume(checker2 != address(manager));
        vm.assume(checker2 != TEST_ACCOUNT_ADDRESS);
        vm.assume(uint160(checker2) > 0xff); // Exclude precompiles
        vm.assume(checker1 != checker2);
        vm.assume(allowance > 10);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        uint160 transferAmount = allowance / 4;
        vm.assume(transferAmount > 0);

        // Two calls with different selectors so each matches a different CallPermission
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](2);
        calls[0] = createCallWithChecker(address(mockToken), TRANSFER_SELECTOR, checker1);
        calls[1] = createCallWithChecker(address(mockToken), APPROVE_SELECTOR, checker2);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(
            address(mockToken), allowance, JustaPermissionManager.PeriodUnit(periodUnit), multiplier
        );

        JustaPermissionManager.Permission memory permission = createPermission(
            TEST_ACCOUNT_ADDRESS, spender, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0, calls, spends
        );

        // Deploy code at checker addresses
        vm.etch(checker1, hex"00");
        vm.etch(checker2, hex"00");

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // First checker approves, second checker rejects
        vm.mockCall(checker1, abi.encodeWithSelector(ICallChecker.canExecute.selector), abi.encode(true));
        vm.mockCall(checker2, abi.encodeWithSelector(ICallChecker.canExecute.selector), abi.encode(false));

        BaseAccount.Call[] memory executeCalls = new BaseAccount.Call[](2);
        // First call uses transfer (checker1)
        executeCalls[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient1, transferAmount)
        });
        // Second call uses approve (checker2)
        executeCalls[1] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.approve.selector, recipient2, transferAmount)
        });

        // Should fail-fast on second call's checker rejection
        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_CheckerRejectedCall.selector,
                address(mockToken),
                APPROVE_SELECTOR,
                checker2
            )
        );

        vm.prank(spender);
        manager.executeBatch(permission, executeCalls);
    }

    function test_ExecuteBatch_ShouldAllowMixedCheckerCalls(
        address spender,
        address recipient1,
        address recipient2,
        address checker,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(recipient1 != address(0));
        vm.assume(recipient2 != address(0));
        vm.assume(recipient1 != TEST_ACCOUNT_ADDRESS);
        vm.assume(recipient2 != TEST_ACCOUNT_ADDRESS);
        vm.assume(checker != address(0));
        vm.assume(checker != address(manager));
        vm.assume(checker != TEST_ACCOUNT_ADDRESS);
        vm.assume(uint160(checker) > 0xff); // Exclude precompiles
        vm.assume(allowance > 10);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        uint160 transferAmount = allowance / 4;
        vm.assume(transferAmount > 0);

        // One call with checker, one without
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](2);
        calls[0] = createCallWithChecker(address(mockToken), TRANSFER_SELECTOR, checker);
        calls[1] = createCall(address(mockToken), TRANSFER_SELECTOR); // No checker

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(
            address(mockToken), allowance, JustaPermissionManager.PeriodUnit(periodUnit), multiplier
        );

        JustaPermissionManager.Permission memory permission = createPermission(
            TEST_ACCOUNT_ADDRESS, spender, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0, calls, spends
        );

        // Deploy code at checker address
        vm.etch(checker, hex"00");

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Mock checker to return true
        vm.mockCall(checker, abi.encodeWithSelector(ICallChecker.canExecute.selector), abi.encode(true));

        // Mock the account's executeBatch to succeed
        vm.mockCall(TEST_ACCOUNT_ADDRESS, abi.encodeWithSelector(BaseAccount.executeBatch.selector), "");

        BaseAccount.Call[] memory executeCalls = new BaseAccount.Call[](2);
        executeCalls[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient1, transferAmount)
        });
        executeCalls[1] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient2, transferAmount)
        });

        // Should succeed - first call passes checker, second has no checker
        vm.prank(spender);
        manager.executeBatch(permission, executeCalls);
    }

    /*//////////////////////////////////////////////////////////////
                    MULTIPLE MATCHING CHECKERS (AND LOGIC)
    //////////////////////////////////////////////////////////////*/

    function test_ExecuteBatch_MultipleMatchingCheckers_BothApprove(
        address spender,
        address recipient,
        address checker1,
        address checker2,
        uint160 allowance
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(recipient != address(0));
        vm.assume(recipient != TEST_ACCOUNT_ADDRESS);
        vm.assume(checker1 != address(0));
        vm.assume(checker1 != address(manager));
        vm.assume(checker1 != TEST_ACCOUNT_ADDRESS);
        vm.assume(checker1 != address(vm)); // Exclude Foundry VM
        vm.assume(checker2 != address(0));
        vm.assume(checker2 != address(manager));
        vm.assume(checker2 != TEST_ACCOUNT_ADDRESS);
        vm.assume(checker2 != address(vm)); // Exclude Foundry VM
        vm.assume(checker1 != checker2);
        vm.assume(uint160(checker1) > 0xff); // Exclude precompiles
        vm.assume(uint160(checker2) > 0xff); // Exclude precompiles
        vm.assume(allowance > 0);

        uint160 transferAmount = allowance / 2;
        vm.assume(transferAmount > 0);

        // Two CallPermissions that BOTH match the same call (token.transfer)
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](2);
        calls[0] = createCallWithChecker(address(mockToken), TRANSFER_SELECTOR, checker1); // Specific
        calls[1] = createCallWithChecker(ANY_TARGET, ANY_FN_SEL, checker2); // Wildcard

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(address(mockToken), allowance, JustaPermissionManager.PeriodUnit.Forever, 1);

        JustaPermissionManager.Permission memory permission = createPermission(
            TEST_ACCOUNT_ADDRESS, spender, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0, calls, spends
        );

        // Deploy code at checker addresses
        vm.etch(checker1, hex"00");
        vm.etch(checker2, hex"00");

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Both checkers approve
        vm.mockCall(checker1, abi.encodeWithSelector(ICallChecker.canExecute.selector), abi.encode(true));
        vm.mockCall(checker2, abi.encodeWithSelector(ICallChecker.canExecute.selector), abi.encode(true));

        // Expect BOTH checkers to be called
        vm.expectCall(checker1, abi.encodeWithSelector(ICallChecker.canExecute.selector));
        vm.expectCall(checker2, abi.encodeWithSelector(ICallChecker.canExecute.selector));

        vm.mockCall(TEST_ACCOUNT_ADDRESS, abi.encodeWithSelector(BaseAccount.executeBatch.selector), "");

        BaseAccount.Call[] memory executeCalls = new BaseAccount.Call[](1);
        executeCalls[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount)
        });

        vm.prank(spender);
        manager.executeBatch(permission, executeCalls);
    }

    function test_ExecuteBatch_MultipleMatchingCheckers_AnyRejectsReverts(
        address spender,
        address recipient,
        address checker1,
        address checker2,
        uint160 allowance
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(recipient != address(0));
        vm.assume(recipient != TEST_ACCOUNT_ADDRESS);
        vm.assume(checker1 != address(0));
        vm.assume(checker1 != address(manager));
        vm.assume(checker1 != TEST_ACCOUNT_ADDRESS);
        vm.assume(checker1 != address(vm)); // Exclude Foundry VM
        vm.assume(checker2 != address(0));
        vm.assume(checker2 != address(manager));
        vm.assume(checker2 != TEST_ACCOUNT_ADDRESS);
        vm.assume(checker2 != address(vm)); // Exclude Foundry VM
        vm.assume(checker1 != checker2);
        vm.assume(uint160(checker1) > 0xff); // Exclude precompiles
        vm.assume(uint160(checker2) > 0xff); // Exclude precompiles
        vm.assume(allowance > 0);

        uint160 transferAmount = allowance / 2;
        vm.assume(transferAmount > 0);

        // Two CallPermissions that BOTH match the same call
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](2);
        calls[0] = createCallWithChecker(address(mockToken), TRANSFER_SELECTOR, checker1); // Specific
        calls[1] = createCallWithChecker(ANY_TARGET, ANY_FN_SEL, checker2); // Wildcard

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(address(mockToken), allowance, JustaPermissionManager.PeriodUnit.Forever, 1);

        JustaPermissionManager.Permission memory permission = createPermission(
            TEST_ACCOUNT_ADDRESS, spender, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0, calls, spends
        );

        // Deploy code at checker addresses
        vm.etch(checker1, hex"00");
        vm.etch(checker2, hex"00");

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // First checker approves, second checker REJECTS
        vm.mockCall(checker1, abi.encodeWithSelector(ICallChecker.canExecute.selector), abi.encode(true));
        vm.mockCall(checker2, abi.encodeWithSelector(ICallChecker.canExecute.selector), abi.encode(false));

        BaseAccount.Call[] memory executeCalls = new BaseAccount.Call[](1);
        executeCalls[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount)
        });

        // Should revert because checker2 rejects
        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_CheckerRejectedCall.selector,
                address(mockToken),
                TRANSFER_SELECTOR,
                checker2
            )
        );

        vm.prank(spender);
        manager.executeBatch(permission, executeCalls);
    }

    function test_ExecuteBatch_WildcardCheckerRunsWhenSpecificHasNoChecker(
        address spender,
        address recipient,
        address wildcardChecker,
        uint160 allowance
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(recipient != address(0));
        vm.assume(recipient != TEST_ACCOUNT_ADDRESS);
        vm.assume(wildcardChecker != address(0));
        vm.assume(wildcardChecker != address(manager));
        vm.assume(wildcardChecker != TEST_ACCOUNT_ADDRESS);
        vm.assume(uint160(wildcardChecker) > 0xff); // Exclude precompiles
        vm.assume(allowance > 0);

        uint160 transferAmount = allowance / 2;
        vm.assume(transferAmount > 0);

        // Specific with NO checker, wildcard WITH checker
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](2);
        calls[0] = createCall(address(mockToken), TRANSFER_SELECTOR); // Specific - address(0) checker
        calls[1] = createCallWithChecker(ANY_TARGET, ANY_FN_SEL, wildcardChecker); // Wildcard with checker

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(address(mockToken), allowance, JustaPermissionManager.PeriodUnit.Forever, 1);

        JustaPermissionManager.Permission memory permission = createPermission(
            TEST_ACCOUNT_ADDRESS, spender, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0, calls, spends
        );

        // Deploy code at wildcard checker address
        vm.etch(wildcardChecker, hex"00");

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Wildcard checker approves
        vm.mockCall(wildcardChecker, abi.encodeWithSelector(ICallChecker.canExecute.selector), abi.encode(true));

        // Expect wildcard checker to be called
        vm.expectCall(wildcardChecker, abi.encodeWithSelector(ICallChecker.canExecute.selector));

        vm.mockCall(TEST_ACCOUNT_ADDRESS, abi.encodeWithSelector(BaseAccount.executeBatch.selector), "");

        BaseAccount.Call[] memory executeCalls = new BaseAccount.Call[](1);
        executeCalls[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount)
        });

        vm.prank(spender);
        manager.executeBatch(permission, executeCalls);
    }

    /*//////////////////////////////////////////////////////////////
                        SPEND LIMIT ERRORS
    //////////////////////////////////////////////////////////////*/

    function test_ExecuteBatch_RevertIfNoSpendPermissionForToken(
        address spender,
        address recipient,
        uint160 transferAmount,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(recipient != address(0));
        vm.assume(recipient != TEST_ACCOUNT_ADDRESS);
        vm.assume(transferAmount > 0);
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        // Create a second mock token that is NOT in the spend limits
        ERC20Mock secondToken = new ERC20Mock();

        // Permission only allows spending mockToken, not secondToken
        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            address(secondToken),
            TRANSFER_SELECTOR,
            address(mockToken), // Spend limit is for mockToken
            allowance,
            periodUnit,
            multiplier
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Mock the account's executeBatch to succeed
        vm.mockCall(TEST_ACCOUNT_ADDRESS, abi.encodeWithSelector(BaseAccount.executeBatch.selector), "");

        // Try to transfer secondToken which has no spend permission
        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({
            target: address(secondToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount)
        });

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_NoSpendPermissions.selector);

        vm.prank(spender);
        manager.executeBatch(permission, calls);
    }

    function test_ExecuteBatch_RevertIfExceededSpendLimit(
        address spender,
        address recipient,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(recipient != address(0));
        vm.assume(recipient != TEST_ACCOUNT_ADDRESS);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        uint160 allowance = 100;
        uint160 transferAmount = 101; // Exceeds allowance

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            address(mockToken),
            TRANSFER_SELECTOR,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Mock the account's executeBatch to succeed
        vm.mockCall(TEST_ACCOUNT_ADDRESS, abi.encodeWithSelector(BaseAccount.executeBatch.selector), "");

        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_ExceededSpendLimit.selector, transferAmount, allowance
            )
        );

        vm.prank(spender);
        manager.executeBatch(permission, calls);
    }

    function test_ExecuteBatch_RevertIfSpendValueOverflow(
        address spender,
        address recipient,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(recipient != address(0));
        vm.assume(recipient != TEST_ACCOUNT_ADDRESS);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        uint160 allowance = type(uint160).max;

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            address(mockToken),
            TRANSFER_SELECTOR,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Mock the account's executeBatch to succeed
        vm.mockCall(TEST_ACCOUNT_ADDRESS, abi.encodeWithSelector(BaseAccount.executeBatch.selector), "");

        // First transfer uses half the allowance
        uint256 firstTransfer = uint256(type(uint160).max) / 2 + 1;

        BaseAccount.Call[] memory calls1 = new BaseAccount.Call[](1);
        calls1[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, firstTransfer)
        });

        vm.prank(spender);
        manager.executeBatch(permission, calls1);

        // Second transfer would cause overflow when added to previous spend
        uint256 secondTransfer = uint256(type(uint160).max) / 2 + 1;

        BaseAccount.Call[] memory calls2 = new BaseAccount.Call[](1);
        calls2[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, secondTransfer)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_SpendValueOverflow.selector,
                firstTransfer + secondTransfer
            )
        );

        vm.prank(spender);
        manager.executeBatch(permission, calls2);
    }

    function test_ExecuteBatch_RevertIfApprovalRevocationFailed(
        address spender,
        address approvalSpender,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(approvalSpender != address(0));
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        uint160 allowance = 1000;
        uint160 approveAmount = 100;

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            address(mockToken),
            APPROVE_SELECTOR,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Mock the account's executeBatch to succeed (but doesn't actually revoke approval)
        vm.mockCall(TEST_ACCOUNT_ADDRESS, abi.encodeWithSelector(BaseAccount.executeBatch.selector), "");

        // Mock allowance to return non-zero (approval wasn't revoked)
        vm.mockCall(
            address(mockToken),
            abi.encodeWithSelector(IERC20.allowance.selector, TEST_ACCOUNT_ADDRESS, approvalSpender),
            abi.encode(uint256(approveAmount))
        );

        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.approve.selector, approvalSpender, approveAmount)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_ApprovalRevocationFailed.selector,
                address(mockToken),
                approvalSpender
            )
        );

        vm.prank(spender);
        manager.executeBatch(permission, calls);
    }

    /*//////////////////////////////////////////////////////////////
                        TOKEN SPEND TRACKING
    //////////////////////////////////////////////////////////////*/

    function test_ExecuteBatch_ShouldTrackNativeTokenSpend(
        address spender,
        address recipient,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(recipient != address(0));
        vm.assume(recipient != TEST_ACCOUNT_ADDRESS);
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        uint256 sendValue = uint256(allowance) / 2;
        vm.assume(sendValue > 0);

        // Create permission with native token spend limit
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCall(recipient, EMPTY_CALLDATA_FN_SEL);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(NATIVE_TOKEN, allowance, JustaPermissionManager.PeriodUnit(periodUnit), multiplier);

        JustaPermissionManager.Permission memory permission = createPermission(
            TEST_ACCOUNT_ADDRESS, spender, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0, calls, spends
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Mock the account's executeBatch to succeed
        vm.mockCall(TEST_ACCOUNT_ADDRESS, abi.encodeWithSelector(BaseAccount.executeBatch.selector), "");

        // Execute with native value
        BaseAccount.Call[] memory executeCalls = new BaseAccount.Call[](1);
        executeCalls[0] = BaseAccount.Call({ target: recipient, value: sendValue, data: "" });

        vm.prank(spender);
        manager.executeBatch(permission, executeCalls);

        // Verify spend was tracked by checking the period spend
        JustaPermissionManager.PeriodSpend memory periodSpend = manager.getLastUpdatedPeriod(permission, spends[0]);
        assertEq(periodSpend.spend, sendValue);
    }

    function test_ExecuteBatch_ShouldTrackERC20Transfer(
        address spender,
        address recipient,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(recipient != address(0));
        vm.assume(recipient != TEST_ACCOUNT_ADDRESS);
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        uint160 transferAmount = allowance / 2;
        vm.assume(transferAmount > 0);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            address(mockToken),
            TRANSFER_SELECTOR,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Mock the account's executeBatch to succeed
        vm.mockCall(TEST_ACCOUNT_ADDRESS, abi.encodeWithSelector(BaseAccount.executeBatch.selector), "");

        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount)
        });

        vm.prank(spender);
        manager.executeBatch(permission, calls);

        // Verify spend was tracked
        JustaPermissionManager.SpendLimit memory spendLimit = createSpendLimit(
            address(mockToken), allowance, JustaPermissionManager.PeriodUnit(periodUnit), multiplier
        );
        JustaPermissionManager.PeriodSpend memory periodSpend = manager.getLastUpdatedPeriod(permission, spendLimit);
        assertEq(periodSpend.spend, transferAmount);
    }

    function test_ExecuteBatch_ShouldTrackERC20TransferFrom(
        address spender,
        address recipient,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(recipient != address(0));
        vm.assume(recipient != TEST_ACCOUNT_ADDRESS);
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        uint160 transferAmount = allowance / 2;
        vm.assume(transferAmount > 0);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            address(mockToken),
            TRANSFER_FROM_SELECTOR,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Mock the account's executeBatch to succeed
        vm.mockCall(TEST_ACCOUNT_ADDRESS, abi.encodeWithSelector(BaseAccount.executeBatch.selector), "");

        // transferFrom where account is the sender
        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transferFrom.selector, TEST_ACCOUNT_ADDRESS, recipient, transferAmount)
        });

        vm.prank(spender);
        manager.executeBatch(permission, calls);

        // Verify spend was tracked
        JustaPermissionManager.SpendLimit memory spendLimit = createSpendLimit(
            address(mockToken), allowance, JustaPermissionManager.PeriodUnit(periodUnit), multiplier
        );
        JustaPermissionManager.PeriodSpend memory periodSpend = manager.getLastUpdatedPeriod(permission, spendLimit);
        assertEq(periodSpend.spend, transferAmount);
    }

    function test_ExecuteBatch_ShouldTrackSelfToSelfTransfer(
        address spender,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        uint160 transferAmount = allowance / 2;
        vm.assume(transferAmount > 0);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            address(mockToken),
            TRANSFER_FROM_SELECTOR,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Mock the account's executeBatch to succeed
        vm.mockCall(TEST_ACCOUNT_ADDRESS, abi.encodeWithSelector(BaseAccount.executeBatch.selector), "");

        // transferFrom where account transfers to itself
        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(
                IERC20.transferFrom.selector, TEST_ACCOUNT_ADDRESS, TEST_ACCOUNT_ADDRESS, transferAmount
            )
        });

        vm.prank(spender);
        manager.executeBatch(permission, calls);

        // Verify spend IS tracked
        JustaPermissionManager.SpendLimit memory spendLimit = createSpendLimit(
            address(mockToken), allowance, JustaPermissionManager.PeriodUnit(periodUnit), multiplier
        );
        JustaPermissionManager.PeriodSpend memory periodSpend = manager.getLastUpdatedPeriod(permission, spendLimit);
        assertEq(periodSpend.spend, transferAmount);
    }

    function test_ExecuteBatch_ShouldTrackERC20Approve(
        address spender,
        address approvalSpender,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(approvalSpender != address(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        uint160 approveAmount = allowance / 2;
        vm.assume(approveAmount > 0);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            address(mockToken),
            APPROVE_SELECTOR,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Mock the account's executeBatch to succeed
        vm.mockCall(TEST_ACCOUNT_ADDRESS, abi.encodeWithSelector(BaseAccount.executeBatch.selector), "");

        // Mock allowance to return 0 (simulating successful revocation)
        vm.mockCall(
            address(mockToken),
            abi.encodeWithSelector(IERC20.allowance.selector, TEST_ACCOUNT_ADDRESS, approvalSpender),
            abi.encode(uint256(0))
        );

        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.approve.selector, approvalSpender, approveAmount)
        });

        vm.prank(spender);
        manager.executeBatch(permission, calls);

        // Verify approve amount was tracked as spend
        JustaPermissionManager.SpendLimit memory spendLimit = createSpendLimit(
            address(mockToken), allowance, JustaPermissionManager.PeriodUnit(periodUnit), multiplier
        );
        JustaPermissionManager.PeriodSpend memory periodSpend = manager.getLastUpdatedPeriod(permission, spendLimit);
        assertEq(periodSpend.spend, approveAmount);
    }

    function test_ExecuteBatch_ShouldRevokeERC20ApprovalsAfterExecution(
        address spender,
        address approvalSpender,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(approvalSpender != address(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        uint160 approveAmount = allowance / 2;
        vm.assume(approveAmount > 0);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            address(mockToken),
            APPROVE_SELECTOR,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Mock the account's executeBatch to succeed
        vm.mockCall(TEST_ACCOUNT_ADDRESS, abi.encodeWithSelector(BaseAccount.executeBatch.selector), "");

        // Mock allowance to return 1 (simulating successful revocation to 1 wei dust)
        vm.mockCall(
            address(mockToken),
            abi.encodeWithSelector(IERC20.allowance.selector, TEST_ACCOUNT_ADDRESS, approvalSpender),
            abi.encode(uint256(1))
        );

        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.approve.selector, approvalSpender, approveAmount)
        });

        // This should succeed because allowance returns 1 (revocation to dust successful)
        vm.prank(spender);
        manager.executeBatch(permission, calls);
    }

    function test_ExecuteBatch_ShouldTrackIncreaseAllowanceSpend(
        address spender,
        address approvalSpender,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(approvalSpender != address(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        uint160 approveAmount = allowance / 2;
        vm.assume(approveAmount > 0);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            address(mockToken),
            INCREASE_ALLOWANCE_SELECTOR,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Mock the account's executeBatch to succeed
        vm.mockCall(TEST_ACCOUNT_ADDRESS, abi.encodeWithSelector(BaseAccount.executeBatch.selector), "");

        // Mock allowance to return 0 (simulating successful revocation)
        vm.mockCall(
            address(mockToken),
            abi.encodeWithSelector(IERC20.allowance.selector, TEST_ACCOUNT_ADDRESS, approvalSpender),
            abi.encode(uint256(0))
        );

        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(bytes4(0x39509351), approvalSpender, approveAmount)
        });

        vm.prank(spender);
        manager.executeBatch(permission, calls);

        // Verify increaseAllowance amount was tracked as spend
        JustaPermissionManager.SpendLimit memory spendLimit = createSpendLimit(
            address(mockToken), allowance, JustaPermissionManager.PeriodUnit(periodUnit), multiplier
        );
        JustaPermissionManager.PeriodSpend memory periodSpend = manager.getLastUpdatedPeriod(permission, spendLimit);
        assertEq(periodSpend.spend, approveAmount);
    }

    function test_ExecuteBatch_ShouldRevokeIncreaseAllowanceAfterExecution(
        address spender,
        address approvalSpender,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(approvalSpender != address(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        uint160 approveAmount = allowance / 2;
        vm.assume(approveAmount > 0);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            address(mockToken),
            INCREASE_ALLOWANCE_SELECTOR,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Mock the account's executeBatch to succeed
        vm.mockCall(TEST_ACCOUNT_ADDRESS, abi.encodeWithSelector(BaseAccount.executeBatch.selector), "");

        // Mock allowance to return 1 (simulating successful revocation to 1 wei dust)
        vm.mockCall(
            address(mockToken),
            abi.encodeWithSelector(IERC20.allowance.selector, TEST_ACCOUNT_ADDRESS, approvalSpender),
            abi.encode(uint256(1))
        );

        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(bytes4(0x39509351), approvalSpender, approveAmount)
        });

        // This should succeed because allowance returns 1 (revocation to dust successful)
        vm.prank(spender);
        manager.executeBatch(permission, calls);
    }

    function test_ExecuteBatch_ShouldRevertIfIncreaseAllowanceRevocationFails(
        address spender,
        address approvalSpender,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(approvalSpender != address(0));
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        uint160 allowance = 1000;
        uint160 approveAmount = 100;

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            address(mockToken),
            INCREASE_ALLOWANCE_SELECTOR,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Mock the account's executeBatch to succeed (but doesn't actually revoke approval)
        vm.mockCall(TEST_ACCOUNT_ADDRESS, abi.encodeWithSelector(BaseAccount.executeBatch.selector), "");

        // Mock allowance to return non-zero (approval wasn't revoked)
        vm.mockCall(
            address(mockToken),
            abi.encodeWithSelector(IERC20.allowance.selector, TEST_ACCOUNT_ADDRESS, approvalSpender),
            abi.encode(uint256(approveAmount))
        );

        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(bytes4(0x39509351), approvalSpender, approveAmount)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_ApprovalRevocationFailed.selector,
                address(mockToken),
                approvalSpender
            )
        );

        vm.prank(spender);
        manager.executeBatch(permission, calls);
    }

    function test_ExecuteBatch_ShouldSkipZeroValueIncreaseAllowance(
        address spender,
        address approvalSpender,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(approvalSpender != address(0));
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
            INCREASE_ALLOWANCE_SELECTOR,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Mock the account's executeBatch to succeed
        vm.mockCall(TEST_ACCOUNT_ADDRESS, abi.encodeWithSelector(BaseAccount.executeBatch.selector), "");

        // increaseAllowance with addedValue = 0 should be skipped
        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(bytes4(0x39509351), approvalSpender, uint256(0))
        });

        vm.prank(spender);
        manager.executeBatch(permission, calls);

        // Verify no spend was tracked
        JustaPermissionManager.SpendLimit memory spendLimit = createSpendLimit(
            address(mockToken), allowance, JustaPermissionManager.PeriodUnit(periodUnit), multiplier
        );
        JustaPermissionManager.PeriodSpend memory periodSpend = manager.getLastUpdatedPeriod(permission, spendLimit);
        assertEq(periodSpend.spend, 0);
    }

    function test_ExecuteBatch_ShouldTrackPermit2Approve(
        address spender,
        address permit2Spender,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(permit2Spender != address(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        uint160 approveAmount = allowance / 2;
        vm.assume(approveAmount > 0);

        // Create permission with Permit2 approve selector
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCall(PERMIT2, PERMIT2_APPROVE_SELECTOR);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(
            address(mockToken), allowance, JustaPermissionManager.PeriodUnit(periodUnit), multiplier
        );

        JustaPermissionManager.Permission memory permission = createPermission(
            TEST_ACCOUNT_ADDRESS, spender, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0, calls, spends
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Mock the account's executeBatch to succeed
        vm.mockCall(TEST_ACCOUNT_ADDRESS, abi.encodeWithSelector(BaseAccount.executeBatch.selector), "");

        // Permit2 approve(address token, address spender, uint160 amount, uint48 expiration)
        BaseAccount.Call[] memory executeCalls = new BaseAccount.Call[](1);
        executeCalls[0] = BaseAccount.Call({
            target: PERMIT2,
            value: 0,
            data: abi.encodeWithSelector(
                PERMIT2_APPROVE_SELECTOR,
                address(mockToken),
                permit2Spender,
                approveAmount,
                uint48(block.timestamp + 1 days)
            )
        });

        vm.prank(spender);
        manager.executeBatch(permission, executeCalls);

        // Verify Permit2 approve amount was tracked as spend
        JustaPermissionManager.PeriodSpend memory periodSpend = manager.getLastUpdatedPeriod(permission, spends[0]);
        assertEq(periodSpend.spend, approveAmount);
    }

    function test_ExecuteBatch_ShouldRevokePermit2ApprovalsAfterExecution(
        address spender,
        address permit2Spender,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(permit2Spender != address(0));
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        uint160 approveAmount = allowance / 2;
        vm.assume(approveAmount > 0);

        // Create permission with Permit2 approve selector
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCall(PERMIT2, PERMIT2_APPROVE_SELECTOR);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(
            address(mockToken), allowance, JustaPermissionManager.PeriodUnit(periodUnit), multiplier
        );

        JustaPermissionManager.Permission memory permission = createPermission(
            TEST_ACCOUNT_ADDRESS, spender, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0, calls, spends
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Mock the account's executeBatch to succeed
        vm.mockCall(TEST_ACCOUNT_ADDRESS, abi.encodeWithSelector(BaseAccount.executeBatch.selector), "");

        // Permit2 approve call
        BaseAccount.Call[] memory executeCalls = new BaseAccount.Call[](1);
        executeCalls[0] = BaseAccount.Call({
            target: PERMIT2,
            value: 0,
            data: abi.encodeWithSelector(
                PERMIT2_APPROVE_SELECTOR,
                address(mockToken),
                permit2Spender,
                approveAmount,
                uint48(block.timestamp + 1 days)
            )
        });

        // This should succeed - lockdown is called via executeBatch mock
        vm.prank(spender);
        manager.executeBatch(permission, executeCalls);
    }

    /*//////////////////////////////////////////////////////////////
                        PERIOD MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function test_ExecuteBatch_ShouldCreateNewPeriodOnFirstSpend(
        address spender,
        address recipient,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(recipient != address(0));
        vm.assume(recipient != TEST_ACCOUNT_ADDRESS);
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        uint160 transferAmount = allowance / 2;
        vm.assume(transferAmount > 0);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            address(mockToken),
            TRANSFER_SELECTOR,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Check that period doesn't exist before execution
        JustaPermissionManager.SpendLimit memory spendLimit = createSpendLimit(
            address(mockToken), allowance, JustaPermissionManager.PeriodUnit(periodUnit), multiplier
        );
        JustaPermissionManager.PeriodSpend memory periodBefore = manager.getLastUpdatedPeriod(permission, spendLimit);
        assertEq(periodBefore.start, 0);

        // Mock the account's executeBatch to succeed
        vm.mockCall(TEST_ACCOUNT_ADDRESS, abi.encodeWithSelector(BaseAccount.executeBatch.selector), "");

        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount)
        });

        vm.prank(spender);
        manager.executeBatch(permission, calls);

        // Check that period was created
        JustaPermissionManager.PeriodSpend memory periodAfter = manager.getLastUpdatedPeriod(permission, spendLimit);
        assertTrue(periodAfter.start > 0);
        assertEq(periodAfter.spend, transferAmount);
    }

    function test_ExecuteBatch_ShouldAccumulateSpendInSamePeriod(
        address spender,
        address recipient,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(recipient != address(0));
        vm.assume(recipient != TEST_ACCOUNT_ADDRESS);
        vm.assume(allowance > 10);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        uint160 firstTransfer = allowance / 4;
        uint160 secondTransfer = allowance / 4;
        vm.assume(firstTransfer > 0);
        vm.assume(secondTransfer > 0);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            address(mockToken),
            TRANSFER_SELECTOR,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Mock the account's executeBatch to succeed
        vm.mockCall(TEST_ACCOUNT_ADDRESS, abi.encodeWithSelector(BaseAccount.executeBatch.selector), "");

        // First transfer
        BaseAccount.Call[] memory calls1 = new BaseAccount.Call[](1);
        calls1[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, firstTransfer)
        });

        vm.prank(spender);
        manager.executeBatch(permission, calls1);

        // Second transfer in same period
        BaseAccount.Call[] memory calls2 = new BaseAccount.Call[](1);
        calls2[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, secondTransfer)
        });

        vm.prank(spender);
        manager.executeBatch(permission, calls2);

        // Verify spend accumulated
        JustaPermissionManager.SpendLimit memory spendLimit = createSpendLimit(
            address(mockToken), allowance, JustaPermissionManager.PeriodUnit(periodUnit), multiplier
        );
        JustaPermissionManager.PeriodSpend memory periodSpend = manager.getLastUpdatedPeriod(permission, spendLimit);
        assertEq(periodSpend.spend, firstTransfer + secondTransfer);
    }

    function test_ExecuteBatch_ShouldResetSpendOnNewPeriod(
        address spender,
        address recipient,
        uint160 allowance,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(recipient != address(0));
        vm.assume(recipient != TEST_ACCOUNT_ADDRESS);
        vm.assume(allowance > 10);
        vm.assume(multiplier > 0);

        uint160 transferAmount = allowance / 2;
        vm.assume(transferAmount > 0);

        // Use Minute period for easy time manipulation
        uint8 periodUnit = 0; // Minute

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            address(mockToken),
            TRANSFER_SELECTOR,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Mock the account's executeBatch to succeed
        vm.mockCall(TEST_ACCOUNT_ADDRESS, abi.encodeWithSelector(BaseAccount.executeBatch.selector), "");

        // First transfer
        BaseAccount.Call[] memory calls1 = new BaseAccount.Call[](1);
        calls1[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount)
        });

        vm.prank(spender);
        manager.executeBatch(permission, calls1);

        JustaPermissionManager.SpendLimit memory spendLimit = createSpendLimit(
            address(mockToken), allowance, JustaPermissionManager.PeriodUnit(periodUnit), multiplier
        );

        // Check spend in first period
        JustaPermissionManager.PeriodSpend memory firstPeriod = manager.getLastUpdatedPeriod(permission, spendLimit);
        assertEq(firstPeriod.spend, transferAmount);

        // Warp to next period (advance by multiplier * 60 seconds + 1)
        vm.warp(block.timestamp + uint256(multiplier) * 60 + 1);

        // Second transfer in new period
        BaseAccount.Call[] memory calls2 = new BaseAccount.Call[](1);
        calls2[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount)
        });

        vm.prank(spender);
        manager.executeBatch(permission, calls2);

        // Verify spend was reset in new period
        JustaPermissionManager.PeriodSpend memory secondPeriod = manager.getLastUpdatedPeriod(permission, spendLimit);
        assertEq(secondPeriod.spend, transferAmount); // Only this period's transfer
        assertTrue(secondPeriod.start > firstPeriod.start); // Different period
    }

    /*//////////////////////////////////////////////////////////////
                        HAPPY PATH & EVENTS
    //////////////////////////////////////////////////////////////*/

    function test_ExecuteBatch_ShouldExecuteSingleCall(
        address spender,
        address recipient,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(recipient != address(0));
        vm.assume(recipient != TEST_ACCOUNT_ADDRESS);
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        uint160 transferAmount = allowance / 2;
        vm.assume(transferAmount > 0);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            address(mockToken),
            TRANSFER_SELECTOR,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Mock the account's executeBatch to succeed
        vm.mockCall(TEST_ACCOUNT_ADDRESS, abi.encodeWithSelector(BaseAccount.executeBatch.selector), "");

        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount)
        });

        // Should not revert
        vm.prank(spender);
        manager.executeBatch(permission, calls);
    }

    function test_ExecuteBatch_ShouldExecuteMultipleCalls(
        address spender,
        address recipient1,
        address recipient2,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(recipient1 != address(0));
        vm.assume(recipient2 != address(0));
        vm.assume(recipient1 != TEST_ACCOUNT_ADDRESS);
        vm.assume(recipient2 != TEST_ACCOUNT_ADDRESS);
        vm.assume(allowance > 10);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        uint160 transferAmount1 = allowance / 4;
        uint160 transferAmount2 = allowance / 4;
        vm.assume(transferAmount1 > 0);
        vm.assume(transferAmount2 > 0);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            address(mockToken),
            TRANSFER_SELECTOR,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Mock the account's executeBatch to succeed
        vm.mockCall(TEST_ACCOUNT_ADDRESS, abi.encodeWithSelector(BaseAccount.executeBatch.selector), "");

        // Multiple calls in one batch
        BaseAccount.Call[] memory calls = new BaseAccount.Call[](2);
        calls[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient1, transferAmount1)
        });
        calls[1] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient2, transferAmount2)
        });

        // Should not revert
        vm.prank(spender);
        manager.executeBatch(permission, calls);

        // Verify total spend was tracked
        JustaPermissionManager.SpendLimit memory spendLimit = createSpendLimit(
            address(mockToken), allowance, JustaPermissionManager.PeriodUnit(periodUnit), multiplier
        );
        JustaPermissionManager.PeriodSpend memory periodSpend = manager.getLastUpdatedPeriod(permission, spendLimit);
        assertEq(periodSpend.spend, transferAmount1 + transferAmount2);
    }

    function test_ExecuteBatch_ShouldEmitCallsExecutedEvent(
        address spender,
        address recipient,
        uint160 allowance,
        uint8 periodUnit,
        uint8 multiplier
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(recipient != address(0));
        vm.assume(recipient != TEST_ACCOUNT_ADDRESS);
        vm.assume(allowance > 0);
        vm.assume(periodUnit <= 5);
        vm.assume(multiplier > 0);

        uint160 transferAmount = allowance / 2;
        vm.assume(transferAmount > 0);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            address(mockToken),
            TRANSFER_SELECTOR,
            address(mockToken),
            allowance,
            periodUnit,
            multiplier
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Mock the account's executeBatch to succeed
        vm.mockCall(TEST_ACCOUNT_ADDRESS, abi.encodeWithSelector(BaseAccount.executeBatch.selector), "");

        bytes32 expectedHash = manager.getHash(permission);

        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount)
        });

        vm.expectEmit(true, false, false, false, address(manager));
        emit JustaPermissionManager.CallsExecuted(expectedHash);

        vm.prank(spender);
        manager.executeBatch(permission, calls);
    }

    /*//////////////////////////////////////////////////////////////
                    ERC721 transferFrom SKIP
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Tests that ERC721 transferFrom is skipped during calldata parsing.
     * @dev ERC721 shares the 0x23b872dd selector with ERC20 transferFrom.
     *      The parser must detect NFT contracts via ERC165 and skip them to
     *      avoid misinterpreting tokenId as an ERC20 amount.
     */
    function test_ExecuteBatch_ShouldSkipERC721TransferFrom(address spender, address recipient) public {
        vm.assume(spender != address(0));
        vm.assume(spender != TEST_ACCOUNT_ADDRESS);
        vm.assume(spender != address(manager));
        vm.assume(recipient != address(0));
        vm.assume(recipient != TEST_ACCOUNT_ADDRESS);

        uint256 tokenId = 42;

        // Permission: call permission for ERC721 transferFrom + ERC20 spend limit (not for the NFT)
        JustaPermissionManager.CallPermission[] memory callPerms = new JustaPermissionManager.CallPermission[](1);
        callPerms[0] = createCall(address(mockERC721), TRANSFER_FROM_SELECTOR);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(address(mockToken), 100 ether, JustaPermissionManager.PeriodUnit.Forever, 1);

        JustaPermissionManager.Permission memory permission = createPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            callPerms,
            spends
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Build ERC721 transferFrom call
        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({
            target: address(mockERC721),
            value: 0,
            data: abi.encodeWithSelector(IERC721.transferFrom.selector, TEST_ACCOUNT_ADDRESS, recipient, tokenId)
        });

        // Mock the actual execution on the account so it doesn't revert
        vm.mockCall(
            TEST_ACCOUNT_ADDRESS,
            abi.encodeWithSelector(BaseAccount.executeBatch.selector, calls),
            abi.encode()
        );

        // Should NOT revert with NoSpendPermissions
        vm.prank(spender);
        manager.executeBatch(permission, calls);
    }

}
