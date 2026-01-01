// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @notice Simplified Permit2 mock for testing
 * @dev Implements approve and lockdown functions that the permission manager calls
 */
contract Permit2Mock {

    mapping(address => mapping(address => uint160)) public allowance;

    struct TokenSpenderPair {
        address token;
        address spender;
    }

    event Approval(
        address indexed owner, address indexed token, address indexed spender, uint160 amount, uint48 expiration
    );

    /**
     * @notice Approve function signature: approve(address,address,uint160,uint48)
     * @dev Selector: 0x87517c45
     */
    function approve(address token, address spender, uint160 amount, uint48 expiration) external {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, token, spender, amount, expiration);
    }

    /**
     * @notice Lockdown function to revoke approvals
     * @dev Called by permission manager to revoke Permit2 approvals after execution
     */
    function lockdown(TokenSpenderPair[] calldata approvals) external {
        for (uint256 i = 0; i < approvals.length; i++) {
            allowance[msg.sender][approvals[i].spender] = 0;
        }
    }

    /**
     * @notice Get allowance for testing
     */
    function getAllowance(address owner, address token, address spender) external view returns (uint160) {
        return allowance[owner][spender];
    }

}