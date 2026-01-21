// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { BaseAccount } from "@account-abstraction/core/BaseAccount.sol";
import { EntryPoint } from "@account-abstraction/core/EntryPoint.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Test } from "forge-std/Test.sol";
import { JustanAccount } from "justanaccount/JustanAccount.sol";
import { PreparePermission } from "script/PreparePermission.s.sol";
import { JustaPermissionManager } from "src/JustaPermissionManager.sol";
import { ERC20Mock } from "test/mocks/ERC20Mock.sol";

/**
 * @title TestSpendLimitEnforcementFlow
 * @notice Integration test for spend limit enforcement across multiple batches.
 * @dev Tests that spend limits are correctly tracked and enforced.
 */
contract TestSpendLimitEnforcementFlow is Test, PreparePermission {

    JustaPermissionManager public manager;
    JustanAccount public justanAccountImpl;
    EntryPoint public entryPoint;
    ERC20Mock public mockToken;

    uint256 public constant INITIAL_BALANCE = 1000 ether;

    function setUp() public {
        entryPoint = new EntryPoint();

        manager = new JustaPermissionManager();
        justanAccountImpl = new JustanAccount(address(entryPoint), address(0));
        mockToken = new ERC20Mock();

        mockToken.mint(TEST_ACCOUNT_ADDRESS, INITIAL_BALANCE);
        vm.deal(TEST_ACCOUNT_ADDRESS, 10 ether);

        vm.signAndAttachDelegation(address(justanAccountImpl), TEST_ACCOUNT_PRIVATE_KEY);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        JustanAccount(TEST_ACCOUNT_ADDRESS).addOwnerAddress(address(manager));
    }

    /**
     * @notice Tests that spend limits are enforced across multiple executions.
     * @dev Verifies:
     *      1. First transfer succeeds (partial spend)
     *      2. Second transfer succeeds (still within limit)
     *      3. Third transfer reverts (exceeds limit)
     */
    function test_ShouldEnforceSpendLimitAcrossBatches(address spender, address recipient) public {
        vm.assume(spender != address(0));
        vm.assume(spender != TEST_ACCOUNT_ADDRESS);
        vm.assume(spender != address(manager));
        vm.assume(recipient != address(0));
        vm.assume(recipient != TEST_ACCOUNT_ADDRESS);

        uint160 allowance = 100 ether;
        uint256 firstTransfer = 40 ether;
        uint256 secondTransfer = 50 ether;
        uint256 thirdTransfer = 20 ether;

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
            6,
            1
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        BaseAccount.Call[] memory calls1 = new BaseAccount.Call[](1);
        calls1[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, firstTransfer)
        });

        vm.prank(spender);
        manager.executeBatch(permission, calls1);

        assertEq(mockToken.balanceOf(recipient), firstTransfer, "First transfer should succeed");

        BaseAccount.Call[] memory calls2 = new BaseAccount.Call[](1);
        calls2[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, secondTransfer)
        });

        vm.prank(spender);
        manager.executeBatch(permission, calls2);

        assertEq(mockToken.balanceOf(recipient), firstTransfer + secondTransfer, "Second transfer should succeed");

        BaseAccount.Call[] memory calls3 = new BaseAccount.Call[](1);
        calls3[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, thirdTransfer)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_ExceededSpendLimit.selector,
                firstTransfer + secondTransfer + thirdTransfer,
                allowance
            )
        );
        vm.prank(spender);
        manager.executeBatch(permission, calls3);

        assertEq(mockToken.balanceOf(recipient), firstTransfer + secondTransfer, "Third transfer should have reverted");
    }

    /**
     * @notice Tests that spend limits are enforced when permission.start == 0 with Forever period.
     */
    function test_ShouldEnforceSpendLimitWithStartZeroAndForeverPeriod(address spender, address recipient) public {
        vm.assume(spender != address(0));
        vm.assume(spender != TEST_ACCOUNT_ADDRESS);
        vm.assume(spender != address(manager));
        vm.assume(recipient != address(0));
        vm.assume(recipient != TEST_ACCOUNT_ADDRESS);

        uint160 allowance = 100 ether;
        uint256 firstTransfer = 60 ether;
        uint256 secondTransfer = 50 ether;

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCall(address(mockToken), TRANSFER_SELECTOR);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(
            address(mockToken),
            allowance,
            JustaPermissionManager.PeriodUnit.Forever,
            1
        );

        JustaPermissionManager.Permission memory permission = createPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            0, // start = 0
            uint48(block.timestamp + 365 days),
            0,
            calls,
            spends
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // First transfer: 60 ether (60/100)
        BaseAccount.Call[] memory calls1 = new BaseAccount.Call[](1);
        calls1[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, firstTransfer)
        });

        vm.prank(spender);
        manager.executeBatch(permission, calls1);
        assertEq(mockToken.balanceOf(recipient), firstTransfer, "First transfer should succeed");

        // Second transfer: 50 ether - should revert (110 > 100)
        BaseAccount.Call[] memory calls2 = new BaseAccount.Call[](1);
        calls2[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, secondTransfer)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_ExceededSpendLimit.selector,
                firstTransfer + secondTransfer,
                allowance
            )
        );

        vm.prank(spender);
        manager.executeBatch(permission, calls2);

        assertEq(mockToken.balanceOf(recipient), firstTransfer, "Second transfer should have reverted");
    }

}
