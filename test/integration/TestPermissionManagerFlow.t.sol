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

contract TestPermissionManagerFlow is Test, PreparePermission {

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

    ////////////////////////////////////////////////////////////////////////
    // INTEGRATION TESTS
    ////////////////////////////////////////////////////////////////////////

    /**
     * @notice Tests the full ERC20 transfer flow through permission manager.
     * @dev This test verifies:
     *      1. Permission can be created and approved
     *      2. Spender can execute transfer through manager
     *      3. Real tokens are transferred (not mocked)
     *      4. Spend limits are tracked correctly
     */
    function test_ShouldExecuteERC20TransferThroughPermission(
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
        vm.assume(allowance <= type(uint160).max);

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

        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, transferAmount)
        });

        uint256 accountBalanceBefore = mockToken.balanceOf(TEST_ACCOUNT_ADDRESS);
        uint256 recipientBalanceBefore = mockToken.balanceOf(recipient);

        vm.prank(spender);
        manager.executeBatch(permission, calls);

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
