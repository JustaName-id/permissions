// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { BaseAccount } from "@account-abstraction/core/BaseAccount.sol";
import { EntryPoint } from "@account-abstraction/core/EntryPoint.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Test } from "forge-std/Test.sol";
import { JustanAccount } from "justanaccount/JustanAccount.sol";
import { PreparePermission } from "script/PreparePermission.s.sol";
import { JustaPermissionManager } from "src/JustaPermissionManager.sol";
import { CallCheckerMock } from "test/mocks/CallCheckerMock.sol";
import { ERC20Mock } from "test/mocks/ERC20Mock.sol";

contract TestCallCheckerFlow is Test, PreparePermission {

    JustaPermissionManager public manager;
    JustanAccount public justanAccountImpl;
    EntryPoint public entryPoint;
    ERC20Mock public mockToken;
    CallCheckerMock public checker;

    uint256 public constant INITIAL_BALANCE = 1000 ether;

    function setUp() public {
        entryPoint = new EntryPoint();

        manager = new JustaPermissionManager();
        justanAccountImpl = new JustanAccount(address(entryPoint), address(0));
        mockToken = new ERC20Mock();
        checker = new CallCheckerMock();

        mockToken.mint(TEST_ACCOUNT_ADDRESS, INITIAL_BALANCE);
        vm.deal(TEST_ACCOUNT_ADDRESS, 10 ether);

        vm.signAndAttachDelegation(address(justanAccountImpl), TEST_ACCOUNT_PRIVATE_KEY);

        vm.prank(TEST_ACCOUNT_ADDRESS);
        JustanAccount(TEST_ACCOUNT_ADDRESS).addOwnerAddress(address(manager));
    }

    ////////////////////////////////////////////////////////////////////////
    // FLOW 1: BASIC CHECKER FLOW
    ////////////////////////////////////////////////////////////////////////

    /**
     * @notice Tests that execution succeeds when checker approves.
     * @dev Verifies real tokens are transferred when checker returns true.
     */
    function test_ShouldExecuteWhenCheckerApproves(
        address spender,
        address recipient,
        uint256 transferAmount,
        uint160 allowance
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(spender != TEST_ACCOUNT_ADDRESS);
        vm.assume(spender != address(manager));
        vm.assume(recipient != address(0));
        vm.assume(recipient != TEST_ACCOUNT_ADDRESS);
        vm.assume(transferAmount > 0);
        vm.assume(transferAmount <= INITIAL_BALANCE);
        vm.assume(allowance >= transferAmount);

        // Checker will approve
        checker.setShouldApprove(true);

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCallWithChecker(address(mockToken), TRANSFER_SELECTOR, address(checker));

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(address(mockToken), allowance, JustaPermissionManager.PeriodUnit.Forever, 1);

        JustaPermissionManager.Permission memory permission = createPermission(
            TEST_ACCOUNT_ADDRESS, spender, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0, calls, spends
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        BaseAccount.Call[] memory executeCalls = new BaseAccount.Call[](1);
        executeCalls[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount)
        });

        uint256 accountBalanceBefore = mockToken.balanceOf(TEST_ACCOUNT_ADDRESS);
        uint256 recipientBalanceBefore = mockToken.balanceOf(recipient);

        vm.prank(spender);
        manager.executeBatch(permission, executeCalls);

        uint256 accountBalanceAfter = mockToken.balanceOf(TEST_ACCOUNT_ADDRESS);
        uint256 recipientBalanceAfter = mockToken.balanceOf(recipient);

        assertEq(
            accountBalanceAfter,
            accountBalanceBefore - transferAmount,
            "Account balance should decrease by transfer amount"
        );
        assertEq(
            recipientBalanceAfter,
            recipientBalanceBefore + transferAmount,
            "Recipient balance should increase by transfer amount"
        );
    }

    /**
     * @notice Tests that execution reverts when checker rejects.
     * @dev Verifies CheckerRejectedCall error is thrown with correct params.
     */
    function test_ShouldRevertWhenCheckerRejects(
        address spender,
        address recipient,
        uint256 transferAmount,
        uint160 allowance
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(spender != TEST_ACCOUNT_ADDRESS);
        vm.assume(spender != address(manager));
        vm.assume(recipient != address(0));
        vm.assume(recipient != TEST_ACCOUNT_ADDRESS);
        vm.assume(transferAmount > 0);
        vm.assume(transferAmount <= INITIAL_BALANCE);
        vm.assume(allowance >= transferAmount);

        // Checker will reject
        checker.setShouldApprove(false);

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCallWithChecker(address(mockToken), TRANSFER_SELECTOR, address(checker));

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(address(mockToken), allowance, JustaPermissionManager.PeriodUnit.Forever, 1);

        JustaPermissionManager.Permission memory permission = createPermission(
            TEST_ACCOUNT_ADDRESS, spender, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0, calls, spends
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

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
                address(checker)
            )
        );

        vm.prank(spender);
        manager.executeBatch(permission, executeCalls);
    }

    /**
     * @notice Tests that checker receives correct parameters.
     * @dev Uses vm.expectCall to verify all params are passed correctly.
     */
    function test_ShouldPassCorrectParamsToChecker(
        address spender,
        address recipient,
        uint256 transferAmount,
        uint160 allowance
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(spender != TEST_ACCOUNT_ADDRESS);
        vm.assume(spender != address(manager));
        vm.assume(recipient != address(0));
        vm.assume(recipient != TEST_ACCOUNT_ADDRESS);
        vm.assume(transferAmount > 0);
        vm.assume(transferAmount <= INITIAL_BALANCE);
        vm.assume(allowance >= transferAmount);

        checker.setShouldApprove(true);

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCallWithChecker(address(mockToken), TRANSFER_SELECTOR, address(checker));

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(address(mockToken), allowance, JustaPermissionManager.PeriodUnit.Forever, 1);

        JustaPermissionManager.Permission memory permission = createPermission(
            TEST_ACCOUNT_ADDRESS, spender, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0, calls, spends
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        bytes32 permissionHash = manager.getHash(permission);
        bytes memory callData = abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount);

        BaseAccount.Call[] memory executeCalls = new BaseAccount.Call[](1);
        executeCalls[0] = BaseAccount.Call({ target: address(mockToken), value: 0, data: callData });

        // Expect checker to be called with correct params
        vm.expectCall(
            address(checker),
            abi.encodeCall(
                checker.canExecute, (permissionHash, TEST_ACCOUNT_ADDRESS, spender, address(mockToken), 0, callData)
            )
        );

        vm.prank(spender);
        manager.executeBatch(permission, executeCalls);
    }

    ////////////////////////////////////////////////////////////////////////
    // FLOW 2: CHECKER + SPEND LIMIT COMBINATION
    ////////////////////////////////////////////////////////////////////////

    /**
     * @notice Tests that execution reverts when checker approves but spend limit is exceeded.
     * @dev Checker returns true, but transfer amount exceeds allowance.
     */
    function test_ShouldRevertIfCheckerApprovesButSpendLimitExceeded(
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
        uint256 transferAmount = 150 ether; // Exceeds allowance

        // Checker will approve
        checker.setShouldApprove(true);

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCallWithChecker(address(mockToken), TRANSFER_SELECTOR, address(checker));

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(address(mockToken), allowance, JustaPermissionManager.PeriodUnit.Forever, 1);

        JustaPermissionManager.Permission memory permission = createPermission(
            TEST_ACCOUNT_ADDRESS, spender, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0, calls, spends
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        BaseAccount.Call[] memory executeCalls = new BaseAccount.Call[](1);
        executeCalls[0] = BaseAccount.Call({
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
        manager.executeBatch(permission, executeCalls);
    }

    /**
     * @notice Tests that execution reverts when within spend limit but checker rejects.
     * @dev Transfer amount is within allowance, but checker returns false.
     */
    function test_ShouldRevertIfWithinSpendLimitButCheckerRejects(address spender, address recipient) public {
        vm.assume(spender != address(0));
        vm.assume(spender != TEST_ACCOUNT_ADDRESS);
        vm.assume(spender != address(manager));
        vm.assume(recipient != address(0));
        vm.assume(recipient != TEST_ACCOUNT_ADDRESS);

        uint160 allowance = 100 ether;
        uint256 transferAmount = 50 ether; // Within allowance

        // Checker will reject
        checker.setShouldApprove(false);

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCallWithChecker(address(mockToken), TRANSFER_SELECTOR, address(checker));

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(address(mockToken), allowance, JustaPermissionManager.PeriodUnit.Forever, 1);

        JustaPermissionManager.Permission memory permission = createPermission(
            TEST_ACCOUNT_ADDRESS, spender, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0, calls, spends
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

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
                address(checker)
            )
        );

        vm.prank(spender);
        manager.executeBatch(permission, executeCalls);
    }

    /**
     * @notice Tests that execution succeeds when both checker approves and within spend limit.
     * @dev Verifies real tokens are transferred when both conditions are met.
     */
    function test_ShouldSucceedWhenBothCheckerAndSpendLimitPass(address spender, address recipient) public {
        vm.assume(spender != address(0));
        vm.assume(spender != TEST_ACCOUNT_ADDRESS);
        vm.assume(spender != address(manager));
        vm.assume(recipient != address(0));
        vm.assume(recipient != TEST_ACCOUNT_ADDRESS);

        uint160 allowance = 100 ether;
        uint256 transferAmount = 50 ether; // Within allowance

        // Checker will approve
        checker.setShouldApprove(true);

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCallWithChecker(address(mockToken), TRANSFER_SELECTOR, address(checker));

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(address(mockToken), allowance, JustaPermissionManager.PeriodUnit.Forever, 1);

        JustaPermissionManager.Permission memory permission = createPermission(
            TEST_ACCOUNT_ADDRESS, spender, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0, calls, spends
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        BaseAccount.Call[] memory executeCalls = new BaseAccount.Call[](1);
        executeCalls[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount)
        });

        uint256 accountBalanceBefore = mockToken.balanceOf(TEST_ACCOUNT_ADDRESS);
        uint256 recipientBalanceBefore = mockToken.balanceOf(recipient);

        vm.prank(spender);
        manager.executeBatch(permission, executeCalls);

        uint256 accountBalanceAfter = mockToken.balanceOf(TEST_ACCOUNT_ADDRESS);
        uint256 recipientBalanceAfter = mockToken.balanceOf(recipient);

        assertEq(
            accountBalanceAfter,
            accountBalanceBefore - transferAmount,
            "Account balance should decrease by transfer amount"
        );
        assertEq(
            recipientBalanceAfter,
            recipientBalanceBefore + transferAmount,
            "Recipient balance should increase by transfer amount"
        );
    }

}
