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
import { ERC20IncreaseAllowanceMock } from "test/mocks/ERC20IncreaseAllowanceMock.sol";

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
    ERC20IncreaseAllowanceMock public mockTokenV2;

    uint256 public constant INITIAL_BALANCE = 1000 ether;

    function setUp() public {
        entryPoint = new EntryPoint();

        manager = new JustaPermissionManager();
        justanAccountImpl = new JustanAccount(address(entryPoint), address(0));
        mockToken = new ERC20Mock();
        mockTokenV2 = new ERC20IncreaseAllowanceMock();

        mockToken.mint(TEST_ACCOUNT_ADDRESS, INITIAL_BALANCE);
        mockTokenV2.mint(TEST_ACCOUNT_ADDRESS, INITIAL_BALANCE);
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
    function test_ShouldEnforceSpendLimitWithStartZeroAndForeverPeriod(
        address spender,
        address recipient
    )
        public
    {
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
        spends[0] = createSpendLimit(address(mockToken), allowance, JustaPermissionManager.PeriodUnit.Forever, 1);

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

    /**
     * @notice Tests that ERC20 transfers revert when permission has empty spends array.
     * @dev Verifies that attempting to transfer tokens without configured spend limits
     *      reverts with NoSpendPermissions error.
     */
    function test_ShouldRevertERC20TransferWithEmptySpends(address spender, address recipient) public {
        vm.assume(spender != address(0));
        vm.assume(spender != TEST_ACCOUNT_ADDRESS);
        vm.assume(spender != address(manager));
        vm.assume(recipient != address(0));
        vm.assume(recipient != TEST_ACCOUNT_ADDRESS);

        // Create permission with calls but NO spend limits
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCall(address(mockToken), TRANSFER_SELECTOR);

        JustaPermissionManager.SpendLimit[] memory emptySpends = new JustaPermissionManager.SpendLimit[](0);

        JustaPermissionManager.Permission memory permission = createPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            calls,
            emptySpends
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Attempt to transfer tokens - should revert
        BaseAccount.Call[] memory transferCalls = new BaseAccount.Call[](1);
        transferCalls[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, 1 ether)
        });

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_NoSpendPermissions.selector);

        vm.prank(spender);
        manager.executeBatch(permission, transferCalls);
    }

    /**
     * @notice Tests that native ETH transfers revert when permission has empty spends array.
     * @dev Verifies that attempting to send ETH without configured spend limits
     *      reverts with NoSpendPermissions error.
     */
    function test_ShouldRevertNativeETHTransferWithEmptySpends(address spender) public {
        vm.assume(spender != address(0));
        vm.assume(spender != TEST_ACCOUNT_ADDRESS);
        vm.assume(spender != address(manager));

        address payable recipient = payable(address(0xBEEF));

        // Create permission with calls but NO spend limits
        // Using ANY_TARGET and EMPTY_CALLDATA_FN_SEL to allow plain ETH transfers
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCall(recipient, EMPTY_CALLDATA_FN_SEL);

        JustaPermissionManager.SpendLimit[] memory emptySpends = new JustaPermissionManager.SpendLimit[](0);

        JustaPermissionManager.Permission memory permission = createPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            calls,
            emptySpends
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        BaseAccount.Call[] memory ethCalls = new BaseAccount.Call[](1);
        ethCalls[0] = BaseAccount.Call({ target: recipient, value: 1 ether, data: "" });

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_NoSpendPermissions.selector);

        vm.prank(spender);
        manager.executeBatch(permission, ethCalls);
    }

    /*//////////////////////////////////////////////////////////////
                    increaseAllowance SPEND TRACKING
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Tests that increaseAllowance is enforced against spend limits.
     * @dev Verifies:
     *      1. First increaseAllowance within limit succeeds
     *      2. Second increaseAllowance that exceeds limit reverts
     */
    function test_ShouldEnforceSpendLimitForIncreaseAllowance(address spender, address approvalSpender) public {
        vm.assume(spender != address(0));
        vm.assume(spender != TEST_ACCOUNT_ADDRESS);
        vm.assume(spender != address(manager));
        vm.assume(approvalSpender != address(0));

        uint160 allowance = 100 ether;
        uint256 firstAmount = 60 ether;
        uint256 secondAmount = 50 ether;

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            address(mockTokenV2),
            INCREASE_ALLOWANCE_SELECTOR,
            address(mockTokenV2),
            allowance,
            6,
            1
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // First increaseAllowance: 60 ether (within 100 ether limit)
        BaseAccount.Call[] memory calls1 = new BaseAccount.Call[](1);
        calls1[0] = BaseAccount.Call({
            target: address(mockTokenV2),
            value: 0,
            data: abi.encodeWithSelector(bytes4(0x39509351), approvalSpender, firstAmount)
        });

        vm.prank(spender);
        manager.executeBatch(permission, calls1);

        // Second increaseAllowance: 50 ether — total 110 > 100, should revert
        BaseAccount.Call[] memory calls2 = new BaseAccount.Call[](1);
        calls2[0] = BaseAccount.Call({
            target: address(mockTokenV2),
            value: 0,
            data: abi.encodeWithSelector(bytes4(0x39509351), approvalSpender, secondAmount)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_ExceededSpendLimit.selector,
                firstAmount + secondAmount,
                allowance
            )
        );

        vm.prank(spender);
        manager.executeBatch(permission, calls2);
    }

    /**
     * @notice Tests that approve + increaseAllowance in the same batch both count toward the spend limit.
     * @dev Verifies the combined amount is tracked and both approvals are revoked post-batch.
     */
    function test_ShouldTrackMixedApproveAndIncreaseAllowanceInSameBatch(
        address spender,
        address approvalSpender
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(spender != TEST_ACCOUNT_ADDRESS);
        vm.assume(spender != address(manager));
        vm.assume(approvalSpender != address(0));

        uint160 allowance = 100 ether;
        uint256 approveAmount = 30 ether;
        uint256 increaseAmount = 80 ether;

        // Permission allows both approve and increaseAllowance on the V2 token
        JustaPermissionManager.CallPermission[] memory callPerms = new JustaPermissionManager.CallPermission[](2);
        callPerms[0] = createCall(address(mockTokenV2), APPROVE_SELECTOR);
        callPerms[1] = createCall(address(mockTokenV2), INCREASE_ALLOWANCE_SELECTOR);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(address(mockTokenV2), allowance, JustaPermissionManager.PeriodUnit.Forever, 1);

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

        // Batch: approve(30) + increaseAllowance(80) = 110 > 100 limit
        BaseAccount.Call[] memory calls = new BaseAccount.Call[](2);
        calls[0] = BaseAccount.Call({
            target: address(mockTokenV2),
            value: 0,
            data: abi.encodeWithSelector(IERC20.approve.selector, approvalSpender, approveAmount)
        });
        calls[1] = BaseAccount.Call({
            target: address(mockTokenV2),
            value: 0,
            data: abi.encodeWithSelector(bytes4(0x39509351), approvalSpender, increaseAmount)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_ExceededSpendLimit.selector,
                approveAmount + increaseAmount,
                allowance
            )
        );

        vm.prank(spender);
        manager.executeBatch(permission, calls);
    }

    /**
     * @notice Tests that multiple increaseAllowance calls in one batch accumulate against spend limit.
     * @dev Verifies:
     *      1. Two increaseAllowance calls within limit succeed
     *      2. Both approvals are revoked after execution
     */
    function test_ShouldAccumulateMultipleIncreaseAllowanceCallsInBatch(
        address spender,
        address approvalSpender
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(spender != TEST_ACCOUNT_ADDRESS);
        vm.assume(spender != address(manager));
        vm.assume(approvalSpender != address(0));

        uint160 allowance = 100 ether;
        uint256 amount1 = 30 ether;
        uint256 amount2 = 40 ether;

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            0,
            address(mockTokenV2),
            INCREASE_ALLOWANCE_SELECTOR,
            address(mockTokenV2),
            allowance,
            6,
            1
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Two increaseAllowance calls: 30 + 40 = 70, within 100 limit
        BaseAccount.Call[] memory calls = new BaseAccount.Call[](2);
        calls[0] = BaseAccount.Call({
            target: address(mockTokenV2),
            value: 0,
            data: abi.encodeWithSelector(bytes4(0x39509351), approvalSpender, amount1)
        });
        calls[1] = BaseAccount.Call({
            target: address(mockTokenV2),
            value: 0,
            data: abi.encodeWithSelector(bytes4(0x39509351), approvalSpender, amount2)
        });

        vm.prank(spender);
        manager.executeBatch(permission, calls);

        // Verify both approvals were revoked (allowance should be 0)
        assertEq(
            mockTokenV2.allowance(TEST_ACCOUNT_ADDRESS, approvalSpender),
            0,
            "Allowance should be revoked after batch"
        );

        // Verify spend was tracked
        JustaPermissionManager.SpendLimit memory spendLimit =
            createSpendLimit(address(mockTokenV2), allowance, JustaPermissionManager.PeriodUnit(6), 1);
        JustaPermissionManager.PeriodSpend memory periodSpend =
            manager.getLastUpdatedPeriod(permission, spendLimit);
        assertEq(periodSpend.spend, amount1 + amount2, "Combined spend should be tracked");
    }

}
