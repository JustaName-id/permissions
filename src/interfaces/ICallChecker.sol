// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ICallChecker
 * @notice Interface for call validation contracts.
 * @dev Checkers receive full context and can validate arguments, not just selectors.
 */
interface ICallChecker {

    /**
     * @notice Validates whether a call can be executed.
     * @param permissionHash The hash of the permission being used.
     * @param account The account executing the call.
     * @param spender The spender using the permission.
     * @param target The target contract address.
     * @param value The ETH value being sent.
     * @param data The full calldata including selector and arguments.
     * @return True if the call is allowed, false otherwise.
     */
    function canExecute(
        bytes32 permissionHash,
        address account,
        address spender,
        address target,
        uint256 value,
        bytes calldata data
    )
        external
        view
        returns (bool);

}
