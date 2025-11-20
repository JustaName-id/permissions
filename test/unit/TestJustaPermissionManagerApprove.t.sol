// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseTest} from "../utils/BaseTest.sol";
import {JustaPermissionManager} from "../../src/JustaPermissionManager.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockTarget} from "../mocks/MockTarget.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MockERC721 is ERC721 {
    constructor() ERC721("MockNFT", "MNFT") {}

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}

/**
 * @title TestJustaPermissionManagerApprove
 * @notice Comprehensive tests for the approve() function
 */
contract TestJustaPermissionManagerApprove is BaseTest {
    /*//////////////////////////////////////////////////////////////
                        SUCCESSFUL APPROVAL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Approve_BasicPermissionWithCalls() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();
        bytes32 hash = manager.getHash(permission);

        vm.prank(address(account));
        vm.expectEmit(true, false, false, true);
        emit PermissionApproved(hash, permission);
        bool result = manager.approve(permission);

        assertTrue(result);
        assertTrue(manager.isApproved(permission));
    }

    function test_Approve_PermissionWithSpendLimits() public {
        JustaPermissionManager.Permission memory permission = _createSpendPermission(uint160(100e18), PERIOD);
        bytes32 hash = manager.getHash(permission);

        vm.prank(address(account));
        vm.expectEmit(true, false, false, true);
        emit PermissionApproved(hash, permission);
        bool result = manager.approve(permission);

        assertTrue(result);
        assertTrue(manager.isApproved(permission));
    }

    function test_Approve_MultipleCallPermissions() public {
        JustaPermissionManager.Permission memory permission = _createMultiCallPermission();

        vm.prank(address(account));
        bool result = manager.approve(permission);

        assertTrue(result);
        assertTrue(manager.isApproved(permission));
    }

    function test_Approve_MultipleSpendLimits() public {
        MockERC20 token2 = new MockERC20("Token2", "TK2", 18);

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](0);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](2);
        spends[0] = JustaPermissionManager.SpendLimit({token: address(token), allowance: 100e18, period: PERIOD});
        spends[1] = JustaPermissionManager.SpendLimit({token: address(token2), allowance: 50e18, period: PERIOD});

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: address(account),
            spender: spender,
            start: START_TIME,
            end: END_TIME,
            salt: 0,
            calls: calls,
            spends: spends
        });

        vm.prank(address(account));
        bool result = manager.approve(permission);

        assertTrue(result);
        assertTrue(manager.isApproved(permission));
    }

    function test_Approve_PermissionWithBothCallsAndSpends() public {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({
            target: address(target),
            selector: MockTarget.increment.selector
        });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({token: address(token), allowance: 100e18, period: PERIOD});

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: address(account),
            spender: spender,
            start: START_TIME,
            end: END_TIME,
            salt: 0,
            calls: calls,
            spends: spends
        });

        vm.prank(address(account));
        bool result = manager.approve(permission);

        assertTrue(result);
        assertTrue(manager.isApproved(permission));
    }

    function test_Approve_AlreadyApprovedPermission() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        // First approval
        vm.prank(address(account));
        bool result1 = manager.approve(permission);

        // Second approval (idempotent)
        vm.prank(address(account));
        bool result2 = manager.approve(permission);

        assertTrue(result1);
        assertTrue(result2);
        assertTrue(manager.isApproved(permission));
    }

    function test_Approve_DifferentSaltCreatesDifferentHash() public {
        JustaPermissionManager.Permission memory permission1 = _createBasicPermission();
        permission1.salt = 0;

        JustaPermissionManager.Permission memory permission2 = _createBasicPermission();
        permission2.salt = 1;

        vm.startPrank(address(account));
        manager.approve(permission1);
        manager.approve(permission2);
        vm.stopPrank();

        bytes32 hash1 = manager.getHash(permission1);
        bytes32 hash2 = manager.getHash(permission2);

        assertTrue(hash1 != hash2);
        assertTrue(manager.isApproved(permission1));
        assertTrue(manager.isApproved(permission2));
    }

    /*//////////////////////////////////////////////////////////////
                    VALIDATION ERROR TESTS - SENDER
    //////////////////////////////////////////////////////////////*/

    function test_RevertWhen_Approve_CallerNotAccount() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_InvalidSender.selector, attacker, address(account)
            )
        );
        manager.approve(permission);
    }

    function test_RevertWhen_Approve_CallerIsSpender() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();

        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_InvalidSender.selector, spender, address(account)
            )
        );
        manager.approve(permission);
    }

    /*//////////////////////////////////////////////////////////////
                VALIDATION ERROR TESTS - PERMISSION FIELDS
    //////////////////////////////////////////////////////////////*/

    function test_RevertWhen_Approve_ZeroSpender() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();
        permission.spender = address(0);

        vm.prank(address(account));
        vm.expectRevert(abi.encodeWithSelector(JustaPermissionManager.JustaPermissionManager_ZeroSpender.selector));
        manager.approve(permission);
    }

    function test_RevertWhen_Approve_StartEqualsEnd() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();
        permission.start = END_TIME;
        permission.end = END_TIME;

        vm.prank(address(account));
        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_InvalidStartEnd.selector, END_TIME, END_TIME
            )
        );
        manager.approve(permission);
    }

    function test_RevertWhen_Approve_StartGreaterThanEnd() public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();
        permission.start = END_TIME;
        permission.end = START_TIME;

        vm.prank(address(account));
        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_InvalidStartEnd.selector, END_TIME, START_TIME
            )
        );
        manager.approve(permission);
    }

    function test_RevertWhen_Approve_EmptyPermission() public {
        JustaPermissionManager.Permission memory permission = _createEmptyPermission();

        vm.prank(address(account));
        vm.expectRevert(
            abi.encodeWithSelector(JustaPermissionManager.JustaPermissionManager_EmptyPermission.selector)
        );
        manager.approve(permission);
    }

    /*//////////////////////////////////////////////////////////////
            VALIDATION ERROR TESTS - CALL PERMISSIONS
    //////////////////////////////////////////////////////////////*/

    function test_RevertWhen_Approve_ZeroTargetInCallPermission() public {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({target: address(0), selector: bytes4(0x12345678)});

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](0);

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: address(account),
            spender: spender,
            start: START_TIME,
            end: END_TIME,
            salt: 0,
            calls: calls,
            spends: spends
        });

        vm.prank(address(account));
        vm.expectRevert(abi.encodeWithSelector(JustaPermissionManager.JustaPermissionManager_ZeroTarget.selector));
        manager.approve(permission);
    }

    function test_RevertWhen_Approve_ZeroSelectorInCallPermission() public {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({target: address(target), selector: bytes4(0)});

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](0);

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: address(account),
            spender: spender,
            start: START_TIME,
            end: END_TIME,
            salt: 0,
            calls: calls,
            spends: spends
        });

        vm.prank(address(account));
        vm.expectRevert(abi.encodeWithSelector(JustaPermissionManager.JustaPermissionManager_ZeroSelector.selector));
        manager.approve(permission);
    }

    /*//////////////////////////////////////////////////////////////
            VALIDATION ERROR TESTS - SPEND LIMITS
    //////////////////////////////////////////////////////////////*/

    function test_RevertWhen_Approve_ZeroTokenInSpendLimit() public {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](0);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({token: address(0), allowance: 100e18, period: PERIOD});

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: address(account),
            spender: spender,
            start: START_TIME,
            end: END_TIME,
            salt: 0,
            calls: calls,
            spends: spends
        });

        vm.prank(address(account));
        vm.expectRevert(abi.encodeWithSelector(JustaPermissionManager.JustaPermissionManager_ZeroToken.selector));
        manager.approve(permission);
    }

    function test_RevertWhen_Approve_ZeroAllowanceInSpendLimit() public {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](0);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({token: address(token), allowance: 0, period: PERIOD});

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: address(account),
            spender: spender,
            start: START_TIME,
            end: END_TIME,
            salt: 0,
            calls: calls,
            spends: spends
        });

        vm.prank(address(account));
        vm.expectRevert(abi.encodeWithSelector(JustaPermissionManager.JustaPermissionManager_ZeroAllowance.selector));
        manager.approve(permission);
    }

    function test_RevertWhen_Approve_ZeroPeriodInSpendLimit() public {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](0);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({token: address(token), allowance: 100e18, period: 0});

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: address(account),
            spender: spender,
            start: START_TIME,
            end: END_TIME,
            salt: 0,
            calls: calls,
            spends: spends
        });

        vm.prank(address(account));
        vm.expectRevert(abi.encodeWithSelector(JustaPermissionManager.JustaPermissionManager_ZeroPeriod.selector));
        manager.approve(permission);
    }

    function test_RevertWhen_Approve_ERC721TokenNotSupported() public {
        MockERC721 nft = new MockERC721();

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](0);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({token: address(nft), allowance: 1, period: PERIOD});

        JustaPermissionManager.Permission memory permission = JustaPermissionManager.Permission({
            account: address(account),
            spender: spender,
            start: START_TIME,
            end: END_TIME,
            salt: 0,
            calls: calls,
            spends: spends
        });

        vm.prank(address(account));
        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_ERC721TokenNotSupported.selector, address(nft)
            )
        );
        manager.approve(permission);
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Approve_DifferentTimeRanges(uint48 start, uint48 end) public {
        vm.assume(end > start);
        vm.assume(start >= START_TIME);
        vm.assume(end <= type(uint48).max);

        JustaPermissionManager.Permission memory permission = _createBasicPermission();
        permission.start = start;
        permission.end = end;

        vm.warp(start);

        vm.prank(address(account));
        bool result = manager.approve(permission);

        assertTrue(result);
        assertTrue(manager.isApproved(permission));
    }

    function testFuzz_Approve_DifferentAllowances(uint160 allowance) public {
        vm.assume(allowance > 0);
        vm.assume(allowance <= type(uint160).max);

        JustaPermissionManager.Permission memory permission = _createSpendPermission(allowance, PERIOD);

        vm.prank(address(account));
        bool result = manager.approve(permission);

        assertTrue(result);
        assertTrue(manager.isApproved(permission));
    }

    function testFuzz_Approve_DifferentSalts(uint256 salt) public {
        JustaPermissionManager.Permission memory permission = _createBasicPermission();
        permission.salt = salt;

        vm.prank(address(account));
        bool result = manager.approve(permission);

        assertTrue(result);
        assertTrue(manager.isApproved(permission));
    }
}
