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
 * @title TestPermissionLifecycleFlow
 * @notice Integration test for the full permission lifecycle.
 * @dev Tests approve -> execute -> revoke -> fail flow.
 */
contract TestPermissionLifecycleFlow is Test, PreparePermission {

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
     * @notice Tests the full permission lifecycle: approve -> execute -> revoke -> fail.
     * @dev Verifies:
     *      1. Permission can be approved
     *      2. Execution succeeds with approved permission
     *      3. Permission can be revoked
     *      4. Subsequent executions fail after revocation
     */
    function test_ShouldFollowPermissionLifecycle(
        address spender,
        address recipient,
        uint128 transferAmount
    )
        public
    {
        vm.assume(spender != address(0));
        vm.assume(spender != TEST_ACCOUNT_ADDRESS);
        vm.assume(spender != address(manager));
        vm.assume(recipient != address(0));
        vm.assume(recipient != TEST_ACCOUNT_ADDRESS);
        vm.assume(transferAmount > 0);
        vm.assume(transferAmount <= INITIAL_BALANCE / 2);

        uint160 allowance = uint160(transferAmount) * 2;

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

        assertTrue(manager.isApproved(permission), "Permission should be approved");
        assertFalse(manager.isRevoked(permission), "Permission should not be revoked");

        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount)
        });

        vm.prank(spender);
        manager.executeBatch(permission, calls);

        assertEq(mockToken.balanceOf(recipient), transferAmount, "First transfer should succeed");

        vm.prank(TEST_ACCOUNT_ADDRESS);
        manager.revoke(permission);

        assertTrue(manager.isApproved(permission), "Permission should still show as approved");
        assertTrue(manager.isRevoked(permission), "Permission should now be revoked");

        BaseAccount.Call[] memory calls2 = new BaseAccount.Call[](1);
        calls2[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount)
        });

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_UnauthorizedPermission.selector);
        vm.prank(spender);
        manager.executeBatch(permission, calls2);

        assertEq(
            mockToken.balanceOf(recipient), transferAmount, "Balance should not change after revoked permission attempt"
        );
    }

    /**
     * @notice Tests that spender can also revoke their own permission.
     * @dev Verifies revokeAsSpender works correctly.
     */
    function test_ShouldAllowSpenderToRevokePermission(
        address spender,
        address recipient,
        uint128 transferAmount
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

        uint160 allowance = uint160(transferAmount);

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

        vm.prank(spender);
        manager.revokeAsSpender(permission);

        assertTrue(manager.isRevoked(permission), "Permission should be revoked by spender");

        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount)
        });

        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_UnauthorizedPermission.selector);
        vm.prank(spender);
        manager.executeBatch(permission, calls);
    }

}
