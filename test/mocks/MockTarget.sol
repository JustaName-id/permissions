// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @dev Simple target contract for testing call permissions
 */
contract MockTarget {
    uint256 public counter;
    address public lastCaller;
    bytes public lastData;

    event FunctionCalled(address caller, bytes data);

    function increment() external {
        counter++;
        lastCaller = msg.sender;
        emit FunctionCalled(msg.sender, msg.data);
    }

    function setCounter(uint256 value) external {
        counter = value;
        lastCaller = msg.sender;
        emit FunctionCalled(msg.sender, msg.data);
    }

    function getValue() external view returns (uint256) {
        return counter;
    }

    function restricted() external pure {
        revert("MockTarget: restricted function");
    }

    receive() external payable {}
}
