// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { JustaPermissionManager } from "../../../src/JustaPermissionManager.sol";
import { JustaPermissionManagerTestBase } from "../utils/JustaPermissionManagerTestBase.sol";

contract TestConstants is JustaPermissionManagerTestBase {

    /*//////////////////////////////////////////////////////////////
                        CONSTANTS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ConstantsAreCorrect() public view {
        assertEq(manager.NATIVE_TOKEN(), 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
        assertEq(manager.PERMIT2(), 0x000000000022D473030F116dDEE9F6B43aC78BA3);
        assertEq(manager.ANY_TARGET(), 0x3232323232323232323232323232323232323232);
        assertEq(manager.ANY_FN_SEL(), bytes4(0x32323232));
        assertEq(manager.EMPTY_CALLDATA_FN_SEL(), bytes4(0xe0e0e0e0));
    }

}
