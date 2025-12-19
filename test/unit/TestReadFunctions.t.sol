// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";

import { CodeConstants } from "../../script/HelperConfig.s.sol";
import { JustaPermissionManager } from "../../src/JustaPermissionManager.sol";

contract TestReadFunctions is Test, CodeConstants {

    JustaPermissionManager public manager;

    function setUp() public {
        manager = new JustaPermissionManager();
    }

    /*//////////////////////////////////////////////////////////////
                        CONSTANT VALUE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ShouldReturnCorrectNativeToken() public view {
        assertEq(manager.NATIVE_TOKEN(), NATIVE_TOKEN);
    }

    function test_ShouldReturnCorrectPermit2Address() public view {
        assertEq(manager.PERMIT2(), PERMIT2);
    }

    function test_ShouldReturnCorrectAnyTarget() public view {
        assertEq(manager.ANY_TARGET(), ANY_TARGET);
    }

    function test_ShouldReturnCorrectAnyFnSel() public view {
        assertEq(manager.ANY_FN_SEL(), ANY_FN_SEL);
    }

    function test_ShouldReturnCorrectEmptyCalldataFnSel() public view {
        assertEq(manager.EMPTY_CALLDATA_FN_SEL(), EMPTY_CALLDATA_FN_SEL);
    }

    /*//////////////////////////////////////////////////////////////
                        TYPEHASH TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ShouldReturnCorrectCallPermissionTypehash() public view {
        assertEq(manager.CALL_PERMISSION_TYPEHASH(), CALL_PERMISSION_TYPEHASH);
    }

    function test_ShouldReturnCorrectSpendLimitTypehash() public view {
        assertEq(manager.SPEND_LIMIT_TYPEHASH(), SPEND_LIMIT_TYPEHASH);
    }

    function test_ShouldReturnCorrectPermissionTypehash() public view {
        assertEq(manager.PERMISSION_TYPEHASH(), PERMISSION_TYPEHASH);
    }
}
