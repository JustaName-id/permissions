// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { ICallChecker } from "../../src/interfaces/ICallChecker.sol";

contract CallCheckerMock is ICallChecker {

    bool public shouldApprove = true;

    function setShouldApprove(bool _shouldApprove) external {
        shouldApprove = _shouldApprove;
    }

    function canExecute(
        bytes32,
        address,
        address,
        address,
        uint256,
        bytes calldata
    ) external view override returns (bool) {
        return shouldApprove;
    }

}
