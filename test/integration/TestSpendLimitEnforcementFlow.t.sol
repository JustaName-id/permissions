// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { BaseAccount } from "@account-abstraction/core/BaseAccount.sol";
import { EntryPoint } from "@account-abstraction/core/EntryPoint.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { Test } from "forge-std/Test.sol";
import { JustanAccount } from "justanaccount/JustanAccount.sol";
import { PreparePermission } from "script/PreparePermission.s.sol";
import { JustaPermissionManager } from "src/JustaPermissionManager.sol";
import { ERC20IncreaseAllowanceMock } from "test/mocks/ERC20IncreaseAllowanceMock.sol";
import { ERC20Mock } from "test/mocks/ERC20Mock.sol";
import { ERC721Mock } from "test/mocks/ERC721Mock.sol";

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
    ERC721Mock public mockERC721;

    uint256 public constant INITIAL_BALANCE = 1000 ether;

    function setUp() public {
        entryPoint = new EntryPoint();

        manager = new JustaPermissionManager();
        justanAccountImpl = new JustanAccount(address(entryPoint), address(0));
        mockToken = new ERC20Mock();
        mockTokenV2 = new ERC20IncreaseAllowanceMock();
        mockERC721 = new ERC721Mock();

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
            5,
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
            5,
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
            5,
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

        // Verify both approvals were revoked (allowance should be 1 wei dust)
        assertEq(
            mockTokenV2.allowance(TEST_ACCOUNT_ADDRESS, approvalSpender),
            1,
            "Allowance should be revoked to 1 wei dust after batch"
        );

        // Verify spend was tracked
        JustaPermissionManager.SpendLimit memory spendLimit =
            createSpendLimit(address(mockTokenV2), allowance, JustaPermissionManager.PeriodUnit.Forever, 1);
        JustaPermissionManager.PeriodSpend memory periodSpend = manager.getLastUpdatedPeriod(permission, spendLimit);
        assertEq(periodSpend.spend, amount1 + amount2, "Combined spend should be tracked");
    }

    /*//////////////////////////////////////////////////////////////
                    ERC721 transferFrom SKIP
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Tests that ERC721 transferFrom works without a spend limit for the NFT.
     * @dev The parser should detect the NFT via ERC165 and skip spend tracking,
     *      so the call succeeds with only an unrelated ERC20 spend limit.
     */
    function test_ShouldAllowERC721TransferFromWithoutSpendLimit(address spender, address recipient) public {
        vm.assume(spender != address(0));
        vm.assume(spender != TEST_ACCOUNT_ADDRESS);
        vm.assume(spender != address(manager));
        vm.assume(recipient != address(0));
        vm.assume(recipient != TEST_ACCOUNT_ADDRESS);

        uint256 tokenId = 1;
        mockERC721.mint(TEST_ACCOUNT_ADDRESS, tokenId);

        // Permission: call permission for ERC721 transferFrom + ERC20 spend limit (not for NFT)
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

        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({
            target: address(mockERC721),
            value: 0,
            data: abi.encodeWithSelector(IERC721.transferFrom.selector, TEST_ACCOUNT_ADDRESS, recipient, tokenId)
        });

        vm.prank(spender);
        manager.executeBatch(permission, calls);

        assertEq(mockERC721.ownerOf(tokenId), recipient, "NFT should be transferred to recipient");
    }

    /**
     * @notice Tests that a mixed batch with ERC20 and ERC721 transferFrom works correctly.
     * @dev ERC20 transferFrom should be tracked against the spend limit, while
     *      ERC721 transferFrom should be skipped. Both should execute successfully.
     */
    function test_ShouldTrackERC20TransferFromAndSkipERC721InSameBatch(address spender, address recipient) public {
        vm.assume(spender != address(0));
        vm.assume(spender != TEST_ACCOUNT_ADDRESS);
        vm.assume(spender != address(manager));
        vm.assume(recipient != address(0));
        vm.assume(recipient != TEST_ACCOUNT_ADDRESS);

        uint256 tokenId = 1;
        uint256 erc20Amount = 50 ether;
        uint160 allowance = 100 ether;

        mockERC721.mint(TEST_ACCOUNT_ADDRESS, tokenId);

        // Account must approve itself for ERC20 transferFrom
        vm.prank(TEST_ACCOUNT_ADDRESS);
        mockToken.approve(TEST_ACCOUNT_ADDRESS, type(uint256).max);

        // Permission: call permissions for both ERC20 and ERC721 transferFrom
        JustaPermissionManager.CallPermission[] memory callPerms = new JustaPermissionManager.CallPermission[](2);
        callPerms[0] = createCall(address(mockToken), TRANSFER_FROM_SELECTOR);
        callPerms[1] = createCall(address(mockERC721), TRANSFER_FROM_SELECTOR);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(address(mockToken), allowance, JustaPermissionManager.PeriodUnit.Forever, 1);

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

        // Mixed batch: ERC20 transferFrom + ERC721 transferFrom
        BaseAccount.Call[] memory calls = new BaseAccount.Call[](2);
        calls[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transferFrom.selector, TEST_ACCOUNT_ADDRESS, recipient, erc20Amount)
        });
        calls[1] = BaseAccount.Call({
            target: address(mockERC721),
            value: 0,
            data: abi.encodeWithSelector(IERC721.transferFrom.selector, TEST_ACCOUNT_ADDRESS, recipient, tokenId)
        });

        vm.prank(spender);
        manager.executeBatch(permission, calls);

        // Verify ERC20 transfer happened
        assertEq(mockToken.balanceOf(recipient), erc20Amount, "ERC20 should be transferred");

        // Verify NFT transfer happened
        assertEq(mockERC721.ownerOf(tokenId), recipient, "NFT should be transferred");

        // Verify only ERC20 spend was tracked
        JustaPermissionManager.SpendLimit memory spendLimit =
            createSpendLimit(address(mockToken), allowance, JustaPermissionManager.PeriodUnit.Forever, 1);
        JustaPermissionManager.PeriodSpend memory periodSpend = manager.getLastUpdatedPeriod(permission, spendLimit);
        assertEq(periodSpend.spend, erc20Amount, "Only ERC20 spend should be tracked");
    }

    /*//////////////////////////////////////////////////////////////
                MONTH PERIOD ALIGNMENT TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Tests that monthly subscription starting on the 16th resets on the 16th.
     * @dev Verifies permission-start-aligned periods so every period starts on the same
     *      day-of-month as the permission start.
     */
    function test_MonthlyPeriod_ShouldAlignToPermissionStart() public {
        address spender = address(0xBEEF);
        address recipient = address(0xCAFE);

        uint160 allowance = 100 ether;
        uint256 transferAmount = 60 ether;

        // Permission starts Jan 16 2025 00:00:00 UTC
        uint48 permStart = uint48(1_737_000_000); // ~Jan 16, 2025

        // Permission ends Dec 31, 2025
        uint48 permEnd = uint48(permStart + 365 days);

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCall(address(mockToken), TRANSFER_SELECTOR);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(address(mockToken), allowance, JustaPermissionManager.PeriodUnit.Month, 1);

        JustaPermissionManager.Permission memory permission =
            createPermission(TEST_ACCOUNT_ADDRESS, spender, permStart, permEnd, 0, calls, spends);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Warp to Jan 20 2025 (within first period)
        vm.warp(permStart + 4 days);

        BaseAccount.Call[] memory batch = new BaseAccount.Call[](1);
        batch[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount)
        });

        vm.prank(spender);
        manager.executeBatch(permission, batch);
        assertEq(mockToken.balanceOf(recipient), transferAmount, "First period transfer should succeed");

        // Spend up to the limit
        batch[0].data = abi.encodeWithSelector(IERC20.transfer.selector, recipient, allowance - transferAmount);
        vm.prank(spender);
        manager.executeBatch(permission, batch);

        // Should revert if we try to spend more in the same period
        batch[0].data = abi.encodeWithSelector(IERC20.transfer.selector, recipient, 1);
        vm.expectRevert();
        vm.prank(spender);
        manager.executeBatch(permission, batch);

        // Warp past the first period boundary (addMonths(permStart, 1) = Feb 16 at same time)
        // +1 to move past the boundary since currentTimestamp <= periodEnd returns old period
        vm.warp(permStart + 31 days + 1);

        // New period, spend should reset
        batch[0].data = abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount);
        vm.prank(spender);
        manager.executeBatch(permission, batch);

        // Verify the new period spend was tracked separately
        JustaPermissionManager.PeriodSpend memory periodSpend = manager.getLastUpdatedPeriod(permission, spends[0]);
        assertEq(periodSpend.spend, transferAmount, "Second period should only track new spend");
    }

    /**
     * @notice Tests monthly subscription starting on the 31st clamps correctly in February.
     * @dev When a permission starts on the 31st, addMonths should clamp to the last day
     *      of shorter months (e.g., Feb 28/29).
     */
    function test_MonthlyPeriod_ShouldClampDayInShorterMonths() public {
        address spender = address(0xBEEF);
        address recipient = address(0xCAFE);

        uint160 allowance = 100 ether;
        uint256 transferAmount = 50 ether;

        // Permission starts Jan 31 2025 00:00:00 UTC
        uint48 permStart = uint48(1_738_281_600); // Jan 31, 2025 00:00:00 UTC

        // Permission ends Dec 31, 2025
        uint48 permEnd = uint48(permStart + 365 days);

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCall(address(mockToken), TRANSFER_SELECTOR);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(address(mockToken), allowance, JustaPermissionManager.PeriodUnit.Month, 1);

        JustaPermissionManager.Permission memory permission =
            createPermission(TEST_ACCOUNT_ADDRESS, spender, permStart, permEnd, 0, calls, spends);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Warp to Jan 31 (first period)
        vm.warp(permStart);

        BaseAccount.Call[] memory batch = new BaseAccount.Call[](1);
        batch[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount)
        });

        vm.prank(spender);
        manager.executeBatch(permission, batch);
        assertEq(mockToken.balanceOf(recipient), transferAmount, "First period transfer should succeed");

        // Warp past the first period boundary
        // addMonths(Jan 31, 1) clamps to Feb 28 00:00:00 UTC = 1740700800
        // +1 to move past boundary since currentTimestamp <= periodEnd returns old period
        vm.warp(1_740_700_800 + 1);

        // This should be in the second period (Feb 28 is the clamped start)
        batch[0].data = abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount);
        vm.prank(spender);
        manager.executeBatch(permission, batch);

        // Verify the spend was tracked in a new period (reset)
        JustaPermissionManager.PeriodSpend memory periodSpend = manager.getLastUpdatedPeriod(permission, spends[0]);
        assertEq(periodSpend.spend, transferAmount, "February period should have fresh spend");
    }

    /**
     * @notice Tests quarterly (multiplier=3) monthly periods align correctly.
     * @dev Verifies that multi-month multipliers produce correct period boundaries.
     */
    function test_MonthlyPeriod_QuarterlyMultiplier() public {
        address spender = address(0xBEEF);
        address recipient = address(0xCAFE);

        uint160 allowance = 100 ether;
        uint256 transferAmount = 50 ether;

        // Permission starts Jan 15 2025 00:00:00 UTC
        uint48 permStart = uint48(1_736_899_200);
        uint48 permEnd = uint48(permStart + 730 days);

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCall(address(mockToken), TRANSFER_SELECTOR);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        // Quarterly: Month with multiplier 3
        spends[0] = createSpendLimit(address(mockToken), allowance, JustaPermissionManager.PeriodUnit.Month, 3);

        JustaPermissionManager.Permission memory permission =
            createPermission(TEST_ACCOUNT_ADDRESS, spender, permStart, permEnd, 0, calls, spends);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Spend in Q1 (Jan 15 - Apr 15)
        vm.warp(permStart + 30 days);

        BaseAccount.Call[] memory batch = new BaseAccount.Call[](1);
        batch[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount)
        });

        vm.prank(spender);
        manager.executeBatch(permission, batch);
        assertEq(mockToken.balanceOf(recipient), transferAmount, "Q1 transfer should succeed");

        // Still in Q1 — spend the rest
        batch[0].data = abi.encodeWithSelector(IERC20.transfer.selector, recipient, allowance - transferAmount);
        vm.prank(spender);
        manager.executeBatch(permission, batch);

        // Warp to Q2 (Apr 15 2025 = addMonths(permStart, 3))
        // Apr 15 2025 00:00:00 UTC = 1744675200
        vm.warp(1_744_675_200 + 1);

        // New quarter, spend should reset
        batch[0].data = abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount);
        vm.prank(spender);
        manager.executeBatch(permission, batch);

        JustaPermissionManager.PeriodSpend memory periodSpend = manager.getLastUpdatedPeriod(permission, spends[0]);
        assertEq(periodSpend.spend, transferAmount, "Q2 should have fresh spend");
    }

    /**
     * @notice Tests permission starting on Feb 29 (leap year) handles non-leap years.
     * @dev addMonths(Feb 29, 12) should clamp to Feb 28 in a non-leap year.
     */
    function test_MonthlyPeriod_LeapYearStart() public {
        address spender = address(0xBEEF);
        address recipient = address(0xCAFE);

        uint160 allowance = 100 ether;
        uint256 transferAmount = 50 ether;

        // Permission starts Feb 29 2024 00:00:00 UTC (leap year)
        uint48 permStart = uint48(1_709_164_800);
        uint48 permEnd = uint48(permStart + 730 days);

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCall(address(mockToken), TRANSFER_SELECTOR);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(address(mockToken), allowance, JustaPermissionManager.PeriodUnit.Month, 1);

        JustaPermissionManager.Permission memory permission =
            createPermission(TEST_ACCOUNT_ADDRESS, spender, permStart, permEnd, 0, calls, spends);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Spend in first period (Feb 29 - Mar 29)
        vm.warp(permStart);

        BaseAccount.Call[] memory batch = new BaseAccount.Call[](1);
        batch[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount)
        });

        vm.prank(spender);
        manager.executeBatch(permission, batch);

        // Warp to second period: addMonths(Feb 29, 1) = Mar 29
        // Mar 29 2024 00:00:00 UTC = 1711670400
        vm.warp(1_711_670_400 + 1);

        batch[0].data = abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount);
        vm.prank(spender);
        manager.executeBatch(permission, batch);

        JustaPermissionManager.PeriodSpend memory periodSpend = manager.getLastUpdatedPeriod(permission, spends[0]);
        assertEq(periodSpend.spend, transferAmount, "March period should have fresh spend");

        // Now jump ahead to Feb 2025 (non-leap year)
        // addMonths(Feb 29 2024, 12) should clamp to Feb 28 2025 = 1740700800
        vm.warp(1_740_700_800 + 1);

        batch[0].data = abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount);
        vm.prank(spender);
        manager.executeBatch(permission, batch);

        periodSpend = manager.getLastUpdatedPeriod(permission, spends[0]);
        assertEq(periodSpend.spend, transferAmount, "Feb 2025 period should have fresh spend (clamped from Feb 29)");
    }

    /*//////////////////////////////////////////////////////////////
                FIXED-UNIT PERIOD ALIGNMENT TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Tests that daily periods starting at noon reset at noon, not midnight.
     * @dev permStart = Jan 15 2025 12:00:00 UTC. Spend at 08:00 Jan 16 is still period 1.
     *      Spend after 12:00:01 Jan 16 is period 2.
     */
    function test_DayPeriod_ShouldAlignToPermissionStartAtNoon() public {
        address spender = address(0xBEEF);
        address recipient = address(0xCAFE);

        uint160 allowance = 100 ether;
        uint256 transferAmount = 60 ether;

        // Permission starts Jan 15 2025 12:00:00 UTC (noon)
        uint48 permStart = uint48(1_736_942_400);
        uint48 permEnd = uint48(permStart + 30 days);

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCall(address(mockToken), TRANSFER_SELECTOR);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(address(mockToken), allowance, JustaPermissionManager.PeriodUnit.Day, 1);

        JustaPermissionManager.Permission memory permission =
            createPermission(TEST_ACCOUNT_ADDRESS, spender, permStart, permEnd, 0, calls, spends);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Warp to Jan 16 2025 08:00:00 UTC (20h after permStart, still in period 1)
        vm.warp(permStart + 20 hours);

        BaseAccount.Call[] memory batch = new BaseAccount.Call[](1);
        batch[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount)
        });

        vm.prank(spender);
        manager.executeBatch(permission, batch);
        assertEq(mockToken.balanceOf(recipient), transferAmount, "Transfer at 08:00 Jan 16 should succeed in period 1");

        // Spend the rest of the limit in period 1
        batch[0].data = abi.encodeWithSelector(IERC20.transfer.selector, recipient, allowance - transferAmount);
        vm.prank(spender);
        manager.executeBatch(permission, batch);

        // Still in period 1, should revert
        batch[0].data = abi.encodeWithSelector(IERC20.transfer.selector, recipient, 1);
        vm.expectRevert();
        vm.prank(spender);
        manager.executeBatch(permission, batch);

        // Warp past noon boundary: permStart + 86400 + 1 = Jan 16 12:00:01 UTC (period 2)
        vm.warp(permStart + 86_400 + 1);

        // New period — spend should reset
        batch[0].data = abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount);
        vm.prank(spender);
        manager.executeBatch(permission, batch);

        JustaPermissionManager.PeriodSpend memory periodSpend = manager.getLastUpdatedPeriod(permission, spends[0]);
        assertEq(periodSpend.spend, transferAmount, "Period 2 should have fresh spend");
    }

    /**
     * @notice Tests that weekly periods starting Wednesday reset on Wednesday, not Monday.
     * @dev permStart = Wed Jan 15 2025 00:00:00 UTC. Mon Jan 20 is still in period 1.
     *      Wed Jan 22 + 1s is period 2.
     */
    function test_WeekPeriod_ShouldAlignToPermissionStartOnWednesday() public {
        address spender = address(0xBEEF);
        address recipient = address(0xCAFE);

        uint160 allowance = 100 ether;
        uint256 transferAmount = 60 ether;

        // Permission starts Wed Jan 15 2025 00:00:00 UTC
        uint48 permStart = uint48(1_736_899_200);
        uint48 permEnd = uint48(permStart + 60 days);

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCall(address(mockToken), TRANSFER_SELECTOR);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(address(mockToken), allowance, JustaPermissionManager.PeriodUnit.Week, 1);

        JustaPermissionManager.Permission memory permission =
            createPermission(TEST_ACCOUNT_ADDRESS, spender, permStart, permEnd, 0, calls, spends);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Warp to Mon Jan 20 2025 (5 days after permStart, still in period 1)
        vm.warp(permStart + 5 days);

        BaseAccount.Call[] memory batch = new BaseAccount.Call[](1);
        batch[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount)
        });

        vm.prank(spender);
        manager.executeBatch(permission, batch);
        assertEq(mockToken.balanceOf(recipient), transferAmount, "Mon Jan 20 should be in period 1");

        // Spend the rest of the limit
        batch[0].data = abi.encodeWithSelector(IERC20.transfer.selector, recipient, allowance - transferAmount);
        vm.prank(spender);
        manager.executeBatch(permission, batch);

        // Still in period 1, should revert
        batch[0].data = abi.encodeWithSelector(IERC20.transfer.selector, recipient, 1);
        vm.expectRevert();
        vm.prank(spender);
        manager.executeBatch(permission, batch);

        // Warp past Wed Jan 22: permStart + 604800 + 1 (period 2)
        vm.warp(permStart + 604_800 + 1);

        // New period — spend should reset
        batch[0].data = abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount);
        vm.prank(spender);
        manager.executeBatch(permission, batch);

        JustaPermissionManager.PeriodSpend memory periodSpend = manager.getLastUpdatedPeriod(permission, spends[0]);
        assertEq(periodSpend.spend, transferAmount, "Period 2 should have fresh spend");
    }

    /**
     * @notice Tests that hourly periods starting at :30 reset at :30, not :00.
     * @dev permStart = Jan 15 2025 12:30:00 UTC. 40 min later still period 1.
     *      After 3601s, period 2.
     */
    function test_HourPeriod_ShouldAlignToPermissionStartAtHalfPast() public {
        address spender = address(0xBEEF);
        address recipient = address(0xCAFE);

        uint160 allowance = 100 ether;
        uint256 transferAmount = 60 ether;

        // Permission starts Jan 15 2025 12:30:00 UTC
        uint48 permStart = uint48(1_736_944_200);
        uint48 permEnd = uint48(permStart + 1 days);

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCall(address(mockToken), TRANSFER_SELECTOR);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(address(mockToken), allowance, JustaPermissionManager.PeriodUnit.Hour, 1);

        JustaPermissionManager.Permission memory permission =
            createPermission(TEST_ACCOUNT_ADDRESS, spender, permStart, permEnd, 0, calls, spends);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Warp to 40 minutes after permStart (still in period 1: 2400 < 3600)
        vm.warp(permStart + 40 minutes);

        BaseAccount.Call[] memory batch = new BaseAccount.Call[](1);
        batch[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount)
        });

        vm.prank(spender);
        manager.executeBatch(permission, batch);
        assertEq(mockToken.balanceOf(recipient), transferAmount, "40 min after :30 should be in period 1");

        // Spend the rest of the limit
        batch[0].data = abi.encodeWithSelector(IERC20.transfer.selector, recipient, allowance - transferAmount);
        vm.prank(spender);
        manager.executeBatch(permission, batch);

        // Still in period 1, should revert
        batch[0].data = abi.encodeWithSelector(IERC20.transfer.selector, recipient, 1);
        vm.expectRevert();
        vm.prank(spender);
        manager.executeBatch(permission, batch);

        // Warp past the hour boundary: permStart + 3601 (period 2)
        vm.warp(permStart + 3601);

        // New period — spend should reset
        batch[0].data = abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount);
        vm.prank(spender);
        manager.executeBatch(permission, batch);

        JustaPermissionManager.PeriodSpend memory periodSpend = manager.getLastUpdatedPeriod(permission, spends[0]);
        assertEq(periodSpend.spend, transferAmount, "Period 2 should have fresh spend");
    }

    /*//////////////////////////////////////////////////////////////
                    EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Tests that at exactly periodEnd the old period is still active (inclusive boundary).
     * @dev The cached period uses `currentTimestamp <= lastUpdatedPeriod.end`, so the
     *      exact boundary second belongs to the old period. At periodEnd + 1 the new period starts.
     */
    function test_PeriodBoundary_ShouldStayInOldPeriodAtExactEnd() public {
        address spender = address(0xBEEF);
        address recipient = address(0xCAFE);

        uint160 allowance = 100 ether;

        uint48 permStart = uint48(1_736_899_200); // Wed Jan 15 2025 00:00:00 UTC
        uint48 permEnd = uint48(permStart + 30 days);

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCall(address(mockToken), TRANSFER_SELECTOR);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(address(mockToken), allowance, JustaPermissionManager.PeriodUnit.Day, 1);

        JustaPermissionManager.Permission memory permission =
            createPermission(TEST_ACCOUNT_ADDRESS, spender, permStart, permEnd, 0, calls, spends);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        // Warp to permStart and spend the full allowance in period 1
        vm.warp(permStart);

        BaseAccount.Call[] memory batch = new BaseAccount.Call[](1);
        batch[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, uint256(allowance))
        });

        vm.prank(spender);
        manager.executeBatch(permission, batch);

        // At EXACTLY periodEnd (permStart + 86400), should still be in period 1 (inclusive boundary)
        vm.warp(permStart + 86_400);

        batch[0].data = abi.encodeWithSelector(IERC20.transfer.selector, recipient, 1);
        vm.expectRevert();
        vm.prank(spender);
        manager.executeBatch(permission, batch);

        // At periodEnd + 1, should be in period 2 (fresh spend)
        vm.warp(permStart + 86_400 + 1);

        batch[0].data = abi.encodeWithSelector(IERC20.transfer.selector, recipient, uint256(allowance));
        vm.prank(spender);
        manager.executeBatch(permission, batch);

        JustaPermissionManager.PeriodSpend memory periodSpend = manager.getLastUpdatedPeriod(permission, spends[0]);
        assertEq(periodSpend.spend, uint256(allowance), "Period 2 should have fresh spend");
    }

    /**
     * @notice Tests that permission.start=0 with a fixed-unit (Day) period works correctly.
     * @dev With permStart=0, periods align to epoch boundaries (midnight UTC).
     *      Verifies spend limits enforce and reset across period boundaries.
     */
    function test_FixedPeriod_ShouldWorkWithPermStartZero() public {
        address spender = address(0xBEEF);
        address recipient = address(0xCAFE);

        uint160 allowance = 100 ether;
        uint256 transferAmount = 60 ether;

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCall(address(mockToken), TRANSFER_SELECTOR);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(address(mockToken), allowance, JustaPermissionManager.PeriodUnit.Day, 1);

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

        // Spend in the current period
        BaseAccount.Call[] memory batch = new BaseAccount.Call[](1);
        batch[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount)
        });

        vm.prank(spender);
        manager.executeBatch(permission, batch);
        assertEq(mockToken.balanceOf(recipient), transferAmount, "First transfer should succeed");

        // Exhaust the limit
        batch[0].data = abi.encodeWithSelector(IERC20.transfer.selector, recipient, uint256(allowance) - transferAmount);
        vm.prank(spender);
        manager.executeBatch(permission, batch);

        // Should revert in same period
        batch[0].data = abi.encodeWithSelector(IERC20.transfer.selector, recipient, 1);
        vm.expectRevert();
        vm.prank(spender);
        manager.executeBatch(permission, batch);

        // Warp to next day boundary (with permStart=0, periods align to midnight UTC)
        uint256 currentPeriodStart = (block.timestamp / 86_400) * 86_400;
        vm.warp(currentPeriodStart + 86_400 + 1);

        // Fresh period, should succeed
        batch[0].data = abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount);
        vm.prank(spender);
        manager.executeBatch(permission, batch);

        JustaPermissionManager.PeriodSpend memory periodSpend = manager.getLastUpdatedPeriod(permission, spends[0]);
        assertEq(periodSpend.spend, transferAmount, "New period should have fresh spend");
    }

}
