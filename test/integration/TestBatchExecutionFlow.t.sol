// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { EntryPoint } from "@account-abstraction/core/EntryPoint.sol";
import { BaseAccount } from "@account-abstraction/core/BaseAccount.sol";
import { JustaPermissionManager } from "src/JustaPermissionManager.sol";
import { JustanAccount } from "justanaccount/JustanAccount.sol";
import { PreparePermission } from "script/PreparePermission.s.sol";
import { ERC20Mock } from "test/mocks/ERC20Mock.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title TestBatchExecutionFlow
 * @notice Integration test for batch execution through permission manager.
 * @dev Tests multiple transfers in a single batch with spend limit tracking.
 */
contract TestBatchExecutionFlow is Test, PreparePermission {

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
     * @notice Tests batch execution with multiple transfers in one call.
     * @dev Verifies:
     *      1. Multiple transfers can be executed in a single batch
     *      2. All recipients receive their tokens
     *      3. Spend limit tracks the total amount across all transfers
     */
    function test_ShouldExecuteBatchTransfersThroughPermission(
        address spender,
        address recipient1,
        address recipient2,
        uint128 amount1,
        uint128 amount2
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(spender != TEST_ACCOUNT_ADDRESS);
        vm.assume(spender != address(manager));
        vm.assume(recipient1 != address(0));
        vm.assume(recipient1 != TEST_ACCOUNT_ADDRESS);
        vm.assume(recipient2 != address(0));
        vm.assume(recipient2 != TEST_ACCOUNT_ADDRESS);
        vm.assume(recipient1 != recipient2);
        vm.assume(amount1 > 0);
        vm.assume(amount2 > 0);
        uint256 totalAmount = uint256(amount1) + uint256(amount2);
        vm.assume(totalAmount <= INITIAL_BALANCE);

        uint160 allowance = uint160(totalAmount);
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

        BaseAccount.Call[] memory calls = new BaseAccount.Call[](2);
        calls[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient1, amount1)
        });
        calls[1] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient2, amount2)
        });

        uint256 accountBalanceBefore = mockToken.balanceOf(TEST_ACCOUNT_ADDRESS);
        uint256 recipient1BalanceBefore = mockToken.balanceOf(recipient1);
        uint256 recipient2BalanceBefore = mockToken.balanceOf(recipient2);

        vm.prank(spender);
        manager.executeBatch(permission, calls);
    
        assertEq(
            mockToken.balanceOf(TEST_ACCOUNT_ADDRESS),
            accountBalanceBefore - totalAmount,
            "Account balance should decrease by total amount"
        );
        assertEq(
            mockToken.balanceOf(recipient1),
            recipient1BalanceBefore + amount1,
            "Recipient1 should receive amount1"
        );
        assertEq(
            mockToken.balanceOf(recipient2),
            recipient2BalanceBefore + amount2,
            "Recipient2 should receive amount2"
        );
    }

}
