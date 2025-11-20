// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

contract MockJustaAccount is IERC1271 {
    address public owner;
    bytes4 internal constant MAGICVALUE = 0x1626ba7e;

    constructor(address _owner) {
        owner = _owner;
    }

    function execute(address target, uint256 value, bytes memory data) external payable returns (bytes memory) {
        (bool success, bytes memory result) = target.call{value: value}(data);
        require(success, "MockJustaAccount: call failed");
        return result;
    }

    function isValidSignature(bytes32 hash, bytes memory signature) external view override returns (bytes4) {
        // Simple mock: accept any signature from owner
        if (signature.length == 65) {
            return MAGICVALUE;
        }
        return 0xffffffff;
    }

    receive() external payable {}
}
