// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { BaseAccount } from "@account-abstraction/core/BaseAccount.sol";
import { EntryPoint } from "@account-abstraction/core/EntryPoint.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Test } from "forge-std/Test.sol";
import { JustanAccount } from "justanaccount/JustanAccount.sol";
import { MultiOwnable } from "justanaccount/MultiOwnable.sol";
import { PreparePermission } from "script/PreparePermission.s.sol";
import { JustaPermissionManager } from "src/JustaPermissionManager.sol";
import { ERC20Mock } from "test/mocks/ERC20Mock.sol";

/**
 * @title Test7702BatchSetupFlow
 * @notice Integration tests for ERC-7702 batch setup scenarios.
 * @dev Tests the ability to batch addOwnerAddress + approve in a single transaction,
 *      validating that the permission manager can be set up atomically with permissions.
 */
contract Test7702BatchSetupFlow is Test, PreparePermission {

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
    }

    ////////////////////////////////////////////////////////////////////////
    // BATCH SETUP TESTS - addOwnerAddress FIRST, then approve
    ////////////////////////////////////////////////////////////////////////

    function test_ShouldBatchAddOwnerThenApprove(address spender, address recipient, uint160 allowance) public {
        vm.assume(spender != address(0));
        vm.assume(spender != TEST_ACCOUNT_ADDRESS);
        vm.assume(spender != address(manager));
        vm.assume(recipient != address(0));
        vm.assume(recipient != TEST_ACCOUNT_ADDRESS);
        vm.assume(allowance > 0);

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

        // Prepare batch calls: addOwnerAddress + approve
        BaseAccount.Call[] memory setupCalls = new BaseAccount.Call[](2);

        // Call 1: Add manager as owner (self-call)
        setupCalls[0] = BaseAccount.Call({
            target: TEST_ACCOUNT_ADDRESS,
            value: 0,
            data: abi.encodeWithSelector(MultiOwnable.addOwnerAddress.selector, address(manager))
        });

        // Call 2: Approve permission on manager
        setupCalls[1] = BaseAccount.Call({
            target: address(manager),
            value: 0,
            data: abi.encodeWithSelector(JustaPermissionManager.approve.selector, permission)
        });

        vm.prank(TEST_ACCOUNT_ADDRESS);
        JustanAccount(TEST_ACCOUNT_ADDRESS).executeBatch(setupCalls);

        assertTrue(
            JustanAccount(TEST_ACCOUNT_ADDRESS).isOwnerAddress(address(manager)),
            "Manager should be an owner after batch"
        );

        assertTrue(manager.isApproved(permission), "Permission should be approved after batch");

        uint256 transferAmount = allowance / 2;
        vm.assume(transferAmount > 0);
        vm.assume(transferAmount <= INITIAL_BALANCE);

        BaseAccount.Call[] memory spenderCalls = new BaseAccount.Call[](1);
        spenderCalls[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount)
        });

        uint256 recipientBalanceBefore = mockToken.balanceOf(recipient);

        vm.prank(spender);
        manager.executeBatch(permission, spenderCalls);

        assertEq(
            mockToken.balanceOf(recipient),
            recipientBalanceBefore + transferAmount,
            "Recipient should receive tokens via permission"
        );
    }

    ////////////////////////////////////////////////////////////////////////
    // BATCH SETUP TESTS - approve FIRST, then addOwnerAddress
    ////////////////////////////////////////////////////////////////////////

    /**
     * @notice Tests batching approve + addOwnerAddress in reverse order.
     * @dev Order: approve(permission) -> addOwnerAddress(manager)
     *      This should also work because approve() doesn't require manager to be owner.
     */
    function test_ShouldBatchApproveThenAddOwner(address spender, address recipient, uint160 allowance) public {
        vm.assume(spender != address(0));
        vm.assume(spender != TEST_ACCOUNT_ADDRESS);
        vm.assume(spender != address(manager));
        vm.assume(recipient != address(0));
        vm.assume(recipient != TEST_ACCOUNT_ADDRESS);
        vm.assume(allowance > 0);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            1,
            address(mockToken),
            TRANSFER_SELECTOR,
            address(mockToken),
            allowance,
            6,
            1
        );

        // Prepare batch calls: approve FIRST, then addOwnerAddress
        BaseAccount.Call[] memory setupCalls = new BaseAccount.Call[](2);

        // Call 1: Approve permission on manager (manager is NOT yet an owner)
        setupCalls[0] = BaseAccount.Call({
            target: address(manager),
            value: 0,
            data: abi.encodeWithSelector(JustaPermissionManager.approve.selector, permission)
        });

        // Call 2: Add manager as owner (self-call)
        setupCalls[1] = BaseAccount.Call({
            target: TEST_ACCOUNT_ADDRESS,
            value: 0,
            data: abi.encodeWithSelector(MultiOwnable.addOwnerAddress.selector, address(manager))
        });

        vm.prank(TEST_ACCOUNT_ADDRESS);
        JustanAccount(TEST_ACCOUNT_ADDRESS).executeBatch(setupCalls);

        assertTrue(
            JustanAccount(TEST_ACCOUNT_ADDRESS).isOwnerAddress(address(manager)),
            "Manager should be an owner after batch"
        );

        assertTrue(manager.isApproved(permission), "Permission should be approved after batch");

        uint256 transferAmount = allowance / 2;
        vm.assume(transferAmount > 0);
        vm.assume(transferAmount <= INITIAL_BALANCE);

        BaseAccount.Call[] memory spenderCalls = new BaseAccount.Call[](1);
        spenderCalls[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount)
        });

        uint256 recipientBalanceBefore = mockToken.balanceOf(recipient);

        vm.prank(spender);
        manager.executeBatch(permission, spenderCalls);

        assertEq(
            mockToken.balanceOf(recipient),
            recipientBalanceBefore + transferAmount,
            "Recipient should receive tokens via permission"
        );
    }

    ////////////////////////////////////////////////////////////////////////
    // EDGE CASE: Approve WITHOUT adding owner (permission unusable)
    ////////////////////////////////////////////////////////////////////////

    /**
     * @notice Tests that approving a permission without adding manager as owner
     *         results in an unusable permission.
     * @dev The permission IS approved, but executeBatch fails because
     *      PermissionManager cannot call account.executeBatch().
     */
    function test_ShouldFailIfManagerNotAddedAsOwner(address spender, address recipient, uint160 allowance) public {
        vm.assume(spender != address(0));
        vm.assume(spender != TEST_ACCOUNT_ADDRESS);
        vm.assume(spender != address(manager));
        vm.assume(recipient != address(0));
        vm.assume(recipient != TEST_ACCOUNT_ADDRESS);
        vm.assume(allowance > 0);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            2,
            address(mockToken),
            TRANSFER_SELECTOR,
            address(mockToken),
            allowance,
            6,
            1
        );

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.approve(permission);

        assertTrue(manager.isApproved(permission), "Permission should be approved");

        assertFalse(
            JustanAccount(TEST_ACCOUNT_ADDRESS).isOwnerAddress(address(manager)),
            "Manager should NOT be an owner"
        );

        uint256 transferAmount = allowance / 2;
        vm.assume(transferAmount > 0);
        vm.assume(transferAmount <= INITIAL_BALANCE);

        BaseAccount.Call[] memory spenderCalls = new BaseAccount.Call[](1);
        spenderCalls[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount)
        });

        vm.prank(spender);
        vm.expectRevert(MultiOwnable.MultiOwnable_Unauthorized.selector);
        manager.executeBatch(permission, spenderCalls);
    }

    ////////////////////////////////////////////////////////////////////////
    // MULTIPLE OWNERS IN SINGLE BATCH
    ////////////////////////////////////////////////////////////////////////

    /**
     * @notice Tests adding multiple owners (manager + recovery) in a single batch.
     * @dev Simulates a full account setup with permission manager and recovery contract.
     */
    function test_ShouldBatchAddMultipleOwnersAndApprove(
        address spender,
        address recipient,
        address recoveryContract,
        uint160 allowance
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(spender != TEST_ACCOUNT_ADDRESS);
        vm.assume(spender != address(manager));
        vm.assume(recipient != address(0));
        vm.assume(recipient != TEST_ACCOUNT_ADDRESS);
        vm.assume(recoveryContract != address(0));
        vm.assume(recoveryContract != TEST_ACCOUNT_ADDRESS);
        vm.assume(recoveryContract != address(manager));
        vm.assume(allowance > 0);

        JustaPermissionManager.Permission memory permission = createBasicPermission(
            TEST_ACCOUNT_ADDRESS,
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            3,
            address(mockToken),
            TRANSFER_SELECTOR,
            address(mockToken),
            allowance,
            6,
            1
        );

        // Prepare batch calls: add manager, add recovery, approve permission
        BaseAccount.Call[] memory setupCalls = new BaseAccount.Call[](3);

        setupCalls[0] = BaseAccount.Call({
            target: TEST_ACCOUNT_ADDRESS,
            value: 0,
            data: abi.encodeWithSelector(MultiOwnable.addOwnerAddress.selector, address(manager))
        });

        setupCalls[1] = BaseAccount.Call({
            target: TEST_ACCOUNT_ADDRESS,
            value: 0,
            data: abi.encodeWithSelector(MultiOwnable.addOwnerAddress.selector, recoveryContract)
        });

        setupCalls[2] = BaseAccount.Call({
            target: address(manager),
            value: 0,
            data: abi.encodeWithSelector(JustaPermissionManager.approve.selector, permission)
        });

        vm.prank(TEST_ACCOUNT_ADDRESS);
        JustanAccount(TEST_ACCOUNT_ADDRESS).executeBatch(setupCalls);

        assertTrue(
            JustanAccount(TEST_ACCOUNT_ADDRESS).isOwnerAddress(address(manager)), "Manager should be an owner"
        );
        assertTrue(
            JustanAccount(TEST_ACCOUNT_ADDRESS).isOwnerAddress(recoveryContract), "Recovery should be an owner"
        );

        uint256 transferAmount = allowance / 2;
        vm.assume(transferAmount > 0);
        vm.assume(transferAmount <= INITIAL_BALANCE);

        BaseAccount.Call[] memory spenderCalls = new BaseAccount.Call[](1);
        spenderCalls[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount)
        });

        uint256 recipientBalanceBefore = mockToken.balanceOf(recipient);

        vm.prank(spender);
        manager.executeBatch(permission, spenderCalls);

        assertEq(
            mockToken.balanceOf(recipient),
            recipientBalanceBefore + transferAmount,
            "Recipient should receive tokens via permission"
        );
    }

}
