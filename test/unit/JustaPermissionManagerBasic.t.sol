// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {JustaPermissionManager} from "../../src/JustaPermissionManager.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockJustaAccount} from "../mocks/MockJustaAccount.sol";
import {MockTarget} from "../mocks/MockTarget.sol";

contract TestableJustaPermissionManager is JustaPermissionManager {
    function _execute(address account, address target, uint256 value, bytes memory data) internal override {
        MockJustaAccount(payable(account)).execute(target, value, data);
    }
}

contract JustaPermissionManagerBasicTest is Test {
    TestableJustaPermissionManager public manager;
    MockERC20 public token;
    MockJustaAccount public account;
    MockTarget public target;

    address public accountOwner;
    address public spender;
    address public attacker;

    uint48 public constant START_TIME = 1000;
    uint48 public constant END_TIME = 2000;
    uint48 public constant PERIOD = 100;

    function setUp() public {
        // Deploy contracts
        manager = new TestableJustaPermissionManager();
        token = new MockERC20("Test Token", "TEST", 18);
        target = new MockTarget();

        // Setup accounts
        accountOwner = makeAddr("accountOwner");
        spender = makeAddr("spender");
        attacker = makeAddr("attacker");

        account = new MockJustaAccount(accountOwner);

        // Label addresses
        vm.label(address(manager), "JustaPermissionManager");
        vm.label(address(token), "MockERC20");
        vm.label(address(account), "MockJustaAccount");
        vm.label(address(target), "MockTarget");
        vm.label(accountOwner, "AccountOwner");
        vm.label(spender, "Spender");
        vm.label(attacker, "Attacker");

        // Setup initial balances
        token.mint(address(account), 1000e18);
        vm.deal(address(account), 100 ether);

        // Set consistent block timestamp
        vm.warp(START_TIME);
    }

    // ============================================
    // Helper Functions
    // ============================================

    function _createBasicPermission() internal view returns (JustaPermissionManager.Permission memory) {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({
            target: address(target),
            selector: MockTarget.increment.selector
        });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](0);

        return JustaPermissionManager.Permission({
            account: address(account),
            spender: spender,
            start: START_TIME,
            end: END_TIME,
            salt: 0,
            calls: calls,
            spends: spends
        });
    }

    function _createSpendPermission(uint160 allowance, uint48 period)
        internal
        view
        returns (JustaPermissionManager.Permission memory)
    {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](0);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({token: address(token), allowance: allowance, period: period});

        return JustaPermissionManager.Permission({
            account: address(account),
            spender: spender,
            start: START_TIME,
            end: END_TIME,
            salt: 0,
            calls: calls,
            spends: spends
        });
    }

    // ============================================
    // Test: approve() - Basic functionality
    // ============================================

    function test_Approve_BasicPermission() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();
        bytes32 hash = manager.getHash(permission);

        vm.prank(address(account));
        bool result = manager.approve(permission);

        assertTrue(result);
        assertTrue(manager.isApproved(permission));
    }

    function test_Approve_WithSpendLimits() public {
        JustaPermissionManager.Permission memory permission = _createSpendPermission(uint160(100e18), PERIOD);

        vm.prank(address(account));
        bool result = manager.approve(permission);

        assertTrue(result);
        assertTrue(manager.isApproved(permission));
    }

    // ============================================
    // Test: approve() - Reverts
    // ============================================

    function test_RevertWhen_Approve_CallerNotAccount() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        vm.prank(attacker);
        vm.expectRevert();
        manager.approve(permission);
    }

    function test_RevertWhen_Approve_ZeroSpender() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();
        permission.spender = address(0);

        vm.prank(address(account));
        vm.expectRevert(abi.encodeWithSelector(JustaPermissionManager.JustaPermissionManager_ZeroSpender.selector));
        manager.approve(permission);
    }

    function test_RevertWhen_Approve_InvalidTimeRange() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();
        permission.start = END_TIME;
        permission.end = START_TIME;

        vm.prank(address(account));
        vm.expectRevert();
        manager.approve(permission);
    }

    function test_RevertWhen_Approve_EmptyPermission() public {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](0);
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

        vm.prank(address(account));
        vm.expectRevert(
            abi.encodeWithSelector(JustaPermissionManager.JustaPermissionManager_EmptyPermission.selector)
        );
        manager.approve(permission);
    }

    // ============================================
    // Test: revoke()
    // ============================================

    function test_Revoke_ByAccount() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();
        JustaPermissionManager.CallPermission memory call = permission.calls[0];

        // Approve first
        vm.prank(address(account));
        manager.approve(permission);

        assertTrue(manager.isApproved(permission));

        // Revoke
        vm.prank(address(account));
        manager.revoke(permission);

        // After revoke, permission is still "approved" but marked as revoked
        // Try to use it should fail
        vm.prank(spender);
        vm.expectRevert();
        manager.executeCall(permission, call, abi.encodeWithSelector(MockTarget.increment.selector));
    }

    // ============================================
    // Test: executeCall()
    // ============================================

    function test_ExecuteCall() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();
        JustaPermissionManager.CallPermission memory call = permission.calls[0];

        // Approve permission
        vm.prank(address(account));
        manager.approve(permission);

        // Execute call - data must include the selector
        bytes memory data = abi.encodeWithSelector(MockTarget.increment.selector);

        vm.prank(spender);
        manager.executeCall(permission, call, data);

        // Verify target was called
        assertEq(target.counter(), 1);
    }

    function test_RevertWhen_ExecuteCall_NotApproved() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();
        JustaPermissionManager.CallPermission memory call = permission.calls[0];

        vm.prank(spender);
        vm.expectRevert();
        manager.executeCall(permission, call, abi.encodeWithSelector(MockTarget.increment.selector));
    }

    function test_RevertWhen_ExecuteCall_BeforeStart() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();
        JustaPermissionManager.CallPermission memory call = permission.calls[0];

        // Approve permission
        vm.prank(address(account));
        manager.approve(permission);

        // Warp to before start time
        vm.warp(START_TIME - 1);

        vm.prank(spender);
        vm.expectRevert();
        manager.executeCall(permission, call, abi.encodeWithSelector(MockTarget.increment.selector));
    }

    function test_RevertWhen_ExecuteCall_AfterEnd() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();
        JustaPermissionManager.CallPermission memory call = permission.calls[0];

        // Approve permission
        vm.prank(address(account));
        manager.approve(permission);

        // Warp to after end time
        vm.warp(END_TIME + 1);

        vm.prank(spender);
        vm.expectRevert();
        manager.executeCall(permission, call, abi.encodeWithSelector(MockTarget.increment.selector));
    }

    // ============================================
    // Test: spend()
    // ============================================

    function test_Spend_BasicSpend() public {
        uint160 allowance = 100e18;
        JustaPermissionManager.Permission memory permission = _createSpendPermission(allowance, PERIOD);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        // Approve permission
        vm.prank(address(account));
        manager.approve(permission);

        // Give allowance from account to manager
        vm.prank(address(account));
        token.approve(address(manager), type(uint256).max);

        uint160 spendAmount = 50e18;
        uint256 initialBalance = token.balanceOf(address(account));

        // Execute spend
        vm.prank(spender);
        manager.spend(permission, spendLimit, spendAmount);

        // Verify transfer
        assertEq(token.balanceOf(address(account)), initialBalance - spendAmount);
        assertEq(token.balanceOf(spender), spendAmount);
    }

    function test_Spend_MultipleInSamePeriod() public {
        uint160 allowance = 100e18;
        JustaPermissionManager.Permission memory permission = _createSpendPermission(allowance, PERIOD);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        // Approve permission
        vm.prank(address(account));
        manager.approve(permission);

        // Give allowance
        vm.prank(address(account));
        token.approve(address(manager), type(uint256).max);

        // First spend
        vm.prank(spender);
        manager.spend(permission, spendLimit, 30e18);

        // Second spend in same period
        vm.prank(spender);
        manager.spend(permission, spendLimit, 40e18);

        // Verify total spent
        assertEq(token.balanceOf(spender), 70e18);
    }

    function test_Spend_NewPeriodResetsLimit() public {
        uint160 allowance = 100e18;
        JustaPermissionManager.Permission memory permission = _createSpendPermission(allowance, PERIOD);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        // Approve permission
        vm.prank(address(account));
        manager.approve(permission);

        // Give allowance
        vm.prank(address(account));
        token.approve(address(manager), type(uint256).max);

        // First spend
        vm.prank(spender);
        manager.spend(permission, spendLimit, 90e18);

        // Warp to next period
        vm.warp(START_TIME + PERIOD);

        // Second spend in new period
        vm.prank(spender);
        manager.spend(permission, spendLimit, 90e18);

        // Verify total spent
        assertEq(token.balanceOf(spender), 180e18);
    }

    function test_RevertWhen_Spend_ExceedsLimit() public {
        uint160 allowance = 100e18;
        JustaPermissionManager.Permission memory permission = _createSpendPermission(allowance, PERIOD);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        // Approve permission
        vm.prank(address(account));
        manager.approve(permission);

        // Give allowance
        vm.prank(address(account));
        token.approve(address(manager), type(uint256).max);

        // Try to spend more than allowance
        vm.prank(spender);
        vm.expectRevert();
        manager.spend(permission, spendLimit, 101e18);
    }

    function test_RevertWhen_Spend_NotApproved() public {
        JustaPermissionManager.Permission memory permission = _createSpendPermission(100e18, PERIOD);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        vm.prank(spender);
        vm.expectRevert();
        manager.spend(permission, spendLimit, 50e18);
    }

    // ============================================
    // Test: EIP-712 hashing
    // ============================================

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

    // ============================================
    // Test: Fuzz testing
    // ============================================

    function testFuzz_Spend_WithinLimit(uint160 amount) public {
        uint160 allowance = 100e18;
        amount = uint160(bound(amount, 1, allowance));

        JustaPermissionManager.Permission memory permission = _createSpendPermission(allowance, PERIOD);
        JustaPermissionManager.SpendLimit memory spendLimit = permission.spends[0];

        // Approve permission
        vm.prank(address(account));
        manager.approve(permission);

        // Give allowance
        vm.prank(address(account));
        token.approve(address(manager), type(uint256).max);

        // Execute spend
        vm.prank(spender);
        manager.spend(permission, spendLimit, amount);

        assertEq(token.balanceOf(spender), amount);
    }
}
