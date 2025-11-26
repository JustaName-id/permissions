// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { BaseAccount } from "@account-abstraction/core/BaseAccount.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { JustaPermissionManager } from "../../../src/JustaPermissionManager.sol";

import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { JustaPermissionManagerTestBase } from "../utils/JustaPermissionManagerTestBase.sol";

contract TestErrorCases is JustaPermissionManagerTestBase {

    /*//////////////////////////////////////////////////////////////
                    SPEND VALUE OVERFLOW TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ExecuteBatchRevertsOnSpendValueOverflow() public {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({ target: address(erc20), selector: IERC20.transfer.selector });

        // Use a high allowance value, but not max to allow for overflow test
        uint160 maxAllowance = type(uint160).max;
        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: address(erc20),
            allowance: maxAllowance,
            period: JustaPermissionManager.SpendPeriod.Day
        });

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: account,
            spender: spender,
            start: uint48(block.timestamp),
            end: uint48(block.timestamp + 1 days),
            salt: 200,
            calls: calls,
            spends: spends
        });

        vm.prank(account);
        manager.approve(permission);

        // Mint enough tokens for the test (maxAllowance + some extra)
        // Use a safe amount that won't overflow uint256 but is large enough
        uint256 mintAmount = uint256(maxAllowance) * 2;
        erc20.mint(account, mintAmount);

        // First spend: spend most of the allowance, leaving 1 wei to test overflow
        // Use type(uint160).max - 1
        uint256 firstSpend = uint256(maxAllowance) - 1;
        BaseAccount.Call[] memory calls1 = new BaseAccount.Call[](1);
        calls1[0] = BaseAccount.Call({
            target: address(erc20),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, randomUser, firstSpend)
        });

        vm.prank(spender);
        manager.executeBatch(permission, calls1);

        // Second spend: 2 wei (would cause overflow: (max - 1) + 2 = max + 1 > uint160.max)
        BaseAccount.Call[] memory calls2 = new BaseAccount.Call[](1);
        calls2[0] = BaseAccount.Call({
            target: address(erc20),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, randomUser, 2)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_SpendValueOverflow.selector, uint256(maxAllowance) + 1
            )
        );
        vm.prank(spender);
        manager.executeBatch(permission, calls2);
    }

    /*//////////////////////////////////////////////////////////////
                    PERIOD OVERFLOW TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetCurrentPeriodRevertsOnPeriodOverflow() public {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({ target: address(erc20), selector: IERC20.transfer.selector });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: address(erc20),
            allowance: 100 ether,
            period: JustaPermissionManager.SpendPeriod.Month
        });

        // Set start time near uint48 max to cause overflow when calculating period end
        uint48 nearMaxTimestamp = type(uint48).max - 1;

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: account,
            spender: spender,
            start: nearMaxTimestamp,
            end: type(uint48).max,
            salt: 201,
            calls: calls,
            spends: spends
        });

        vm.prank(account);
        manager.approve(permission);

        // Warp to near max timestamp
        vm.warp(nearMaxTimestamp);

        // This should revert with PeriodOverflow when calculating period end
        vm.expectRevert(JustaPermissionManager.JustaPermissionManager_PeriodOverflow.selector);
        manager.getCurrentPeriod(permission, permission.spends[0]);
    }

    /*//////////////////////////////////////////////////////////////
                APPROVAL REVOCATION FAILED TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ExecuteBatchRevertsWhenApprovalRevocationFails() public {
        // Create a malicious token that doesn't allow approval revocation
        MaliciousToken maliciousToken = new MaliciousToken();
        maliciousToken.mint(account, 1000 ether);

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({
            target: address(maliciousToken),
            selector: IERC20.approve.selector
        });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: address(maliciousToken),
            allowance: 100 ether,
            period: JustaPermissionManager.SpendPeriod.Day
        });

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: account,
            spender: spender,
            start: uint48(block.timestamp),
            end: uint48(block.timestamp + 1 days),
            salt: 202,
            calls: calls,
            spends: spends
        });

        vm.prank(account);
        manager.approve(permission);

        address approvedSpender = makeAddr("approvedSpender");

        // Execute approve
        BaseAccount.Call[] memory executeCalls = new BaseAccount.Call[](1);
        executeCalls[0] = BaseAccount.Call({
            target: address(maliciousToken),
            value: 0,
            data: abi.encodeWithSelector(IERC20.approve.selector, approvedSpender, 50 ether)
        });

        // This should revert because the malicious token doesn't allow approval revocation
        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_ApprovalRevocationFailed.selector,
                address(maliciousToken),
                approvedSpender
            )
        );
        vm.prank(spender);
        manager.executeBatch(permission, executeCalls);
    }

}

// Malicious token that prevents approval revocation
contract MaliciousToken is ERC20 {

    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => mapping(address => uint256)) private _originalAllowances; // Track original values
    bool private _revocationBlocked;

    constructor() ERC20("MaliciousToken", "MAL") {
        _revocationBlocked = true;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        // If setting a new non-zero allowance, store it as original
        if (_allowances[msg.sender][spender] == 0 && amount != 0) {
            _originalAllowances[msg.sender][spender] = amount;
        }
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        // If revocation is blocked and there was an original allowance, return that instead
        if (_revocationBlocked && _originalAllowances[owner][spender] != 0) {
            // Even if current allowance is 0, return the original
            if (_allowances[owner][spender] == 0 && _originalAllowances[owner][spender] != 0) {
                return _originalAllowances[owner][spender];
            }
            // Otherwise return the original if it's non-zero
            return _originalAllowances[owner][spender];
        }
        return _allowances[owner][spender];
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }

}
