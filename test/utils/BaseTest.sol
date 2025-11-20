// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {JustaPermissionManager} from "../../src/JustaPermissionManager.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockJustaAccount} from "../mocks/MockJustaAccount.sol";
import {MockTarget} from "../mocks/MockTarget.sol";

/**
 * @title BaseTest
 * @notice Base test contract with shared utilities and helper functions
 */
abstract contract BaseTest is Test {
    // Testable wrapper that uses MockJustaAccount for execution
    TestableJustaPermissionManager public manager;
    MockERC20 public token;
    MockJustaAccount public account;
    MockTarget public target;

    // Test actors
    address public accountOwner;
    address public spender;
    address public attacker;

    // Time constants
    uint48 public constant START_TIME = 1000;
    uint48 public constant END_TIME = 2000;
    uint48 public constant PERIOD = 100;

    // Events
    event PermissionApproved(bytes32 indexed permissionHash, JustaPermissionManager.Permission permission);
    event PermissionRevoked(bytes32 indexed permissionHash);
    event CallExecuted(
        bytes32 indexed permissionHash, address indexed target, bytes4 indexed selector, bytes returnData
    );
    event SpendLimitUsed(
        bytes32 indexed permissionHash,
        bytes32 indexed spendLimitHash,
        address indexed token,
        uint160 value,
        uint48 periodStart,
        uint48 periodEnd
    );

    function setUp() public virtual {
        // Deploy contracts
        manager = new TestableJustaPermissionManager();
        token = new MockERC20("Test Token", "TEST", 18);
        target = new MockTarget();

        // Setup accounts
        accountOwner = makeAddr("accountOwner");
        spender = makeAddr("spender");
        attacker = makeAddr("attacker");

        account = new MockJustaAccount(accountOwner);

        // Label addresses for better traces
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

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

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

    function _createMultiCallPermission() internal view returns (JustaPermissionManager.Permission memory) {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](2);
        calls[0] = JustaPermissionManager.CallPermission({
            target: address(target),
            selector: MockTarget.increment.selector
        });
        calls[1] = JustaPermissionManager.CallPermission({
            target: address(target),
            selector: MockTarget.setCounter.selector
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

    function _createEmptyPermission() internal view returns (JustaPermissionManager.Permission memory) {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](0);
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

    function _approvePermission(JustaPermissionManager.Permission memory permission) internal {
        vm.prank(address(account));
        manager.approve(permission);
    }

    function _approveTokenSpending() internal {
        vm.prank(address(account));
        token.approve(address(manager), type(uint256).max);
    }
}

/**
 * @title TestableJustaPermissionManager
 * @notice Wrapper that uses MockJustaAccount for testing
 */
contract TestableJustaPermissionManager is JustaPermissionManager {
    function _execute(address account, address target, uint256 value, bytes memory data) internal override {
        MockJustaAccount(payable(account)).execute(target, value, data);
    }
}
