// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BaseAccount } from "@account-abstraction/core/BaseAccount.sol";

import { JustaPermissionManager } from "../../../src/JustaPermissionManager.sol";
import { JustaPermissionManagerTestBase } from "../utils/JustaPermissionManagerTestBase.sol";

contract TestPeriodCalculation is JustaPermissionManagerTestBase {

    /*//////////////////////////////////////////////////////////////
                    PERIOD CALCULATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_StartOfSpendPeriodMinute() public view {
        uint256 timestamp = 1700000000; // Some arbitrary timestamp
        uint256 expectedStart = (timestamp / 60) * 60;
        assertEq(manager.startOfSpendPeriod(timestamp, JustaPermissionManager.SpendPeriod.Minute), expectedStart);
    }

    function test_StartOfSpendPeriodHour() public view {
        uint256 timestamp = 1700000000;
        uint256 expectedStart = (timestamp / 3600) * 3600;
        assertEq(manager.startOfSpendPeriod(timestamp, JustaPermissionManager.SpendPeriod.Hour), expectedStart);
    }

    function test_StartOfSpendPeriodDay() public view {
        uint256 timestamp = 1700000000;
        uint256 expectedStart = (timestamp / 86400) * 86400;
        assertEq(manager.startOfSpendPeriod(timestamp, JustaPermissionManager.SpendPeriod.Day), expectedStart);
    }

    function test_StartOfSpendPeriodForever() public view {
        uint256 timestamp = 1700000000;
        assertEq(manager.startOfSpendPeriod(timestamp, JustaPermissionManager.SpendPeriod.Forever), 1);
    }

    function test_SpendLimitResetsOnNewPeriod() public {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({
            target: address(erc20),
            selector: IERC20.transfer.selector
        });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: address(erc20),
            allowance: 100 ether,
            period: JustaPermissionManager.SpendPeriod.Hour
        });

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: account,
            spender: spender,
            start: uint48(block.timestamp),
            end: uint48(block.timestamp + 30 days),
            salt: 60,
            calls: calls,
            spends: spends
        });

        vm.prank(account);
        manager.approve(permission);

        // Spend 30 ether (within 100 ether limit)
        BaseAccount.Call[] memory calls1 = new BaseAccount.Call[](1);
        calls1[0] = BaseAccount.Call({
            target: address(erc20),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, randomUser, 30 ether)
        });

        vm.prank(spender);
        manager.executeBatch(permission, calls1);

        uint256 balanceAfterFirst = erc20.balanceOf(randomUser);

        // Warp past the hour boundary - period should reset
        // The period ends at 3601, so we need to go past that
        vm.warp(block.timestamp + 1 hours + 1);

        // Should be able to spend again in new period
        BaseAccount.Call[] memory calls2 = new BaseAccount.Call[](1);
        calls2[0] = BaseAccount.Call({
            target: address(erc20),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, randomUser, 30 ether)
        });

        vm.prank(spender);
        manager.executeBatch(permission, calls2);

        // Verify more tokens were transferred (period reset allowed more spending)
        assertEq(erc20.balanceOf(randomUser), balanceAfterFirst + 30 ether);
    }
}


