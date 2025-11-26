// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { JustaPermissionManager } from "../../../src/JustaPermissionManager.sol";
import { JustanAccount } from "justanaccount/JustanAccount.sol";
import { JustanAccountFactory } from "justanaccount/JustanAccountFactory.sol";
import { EntryPoint } from "@account-abstraction/core/EntryPoint.sol";

import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { ERC721Mock } from "../mocks/ERC721Mock.sol";
import { ERC1155Mock } from "../mocks/ERC1155Mock.sol";

abstract contract JustaPermissionManagerTestBase is Test {
    JustaPermissionManager public manager;
    JustanAccount public justanAccount;
    JustanAccountFactory public factory;
    EntryPoint public entryPoint;

    ERC20Mock public erc20;
    ERC721Mock public erc721;
    ERC1155Mock public erc1155;

    address public accountOwner;
    uint256 public accountOwnerPk;
    address payable public account;

    address public spender;
    uint256 public spenderPk;

    address public randomUser;

    // Constants from the contract
    address constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address constant ANY_TARGET = 0x3232323232323232323232323232323232323232;
    bytes4 constant ANY_FN_SEL = 0x32323232;
    bytes4 constant EMPTY_CALLDATA_FN_SEL = 0xe0e0e0e0;

    function setUp() public virtual {
        // Deploy EntryPoint
        entryPoint = new EntryPoint();

        // Deploy JustanAccount factory first (needed for implementation constructor)
        // We use a temporary address, then redeploy properly
        factory = new JustanAccountFactory(address(0));

        // Deploy JustanAccount implementation with factory address
        justanAccount = new JustanAccount(address(entryPoint), address(factory));

        // Redeploy factory with correct implementation
        factory = new JustanAccountFactory(address(justanAccount));

        // Create account owner
        (accountOwner, accountOwnerPk) = makeAddrAndKey("accountOwner");

        // Create the account
        bytes[] memory owners = new bytes[](1);
        owners[0] = abi.encode(accountOwner);
        JustanAccount newAccount = factory.createAccount(owners, 1);
        account = payable(address(newAccount));

        // Attach delegation for EIP-7702
        vm.signAndAttachDelegation(address(justanAccount), accountOwnerPk);

        // Create spender
        (spender, spenderPk) = makeAddrAndKey("spender");

        // Create random user
        randomUser = makeAddr("randomUser");

        // Deploy permission manager
        manager = new JustaPermissionManager();

        // Add permission manager as an owner of the account so it can call executeBatch
        vm.prank(account);
        JustanAccount(account).addOwnerAddress(address(manager));

        // Deploy mock tokens
        erc20 = new ERC20Mock();
        erc721 = new ERC721Mock();
        erc1155 = new ERC1155Mock();

        // Fund the account with ETH
        vm.deal(account, 100 ether);

        // Mint some ERC20 tokens to the account
        erc20.mint(account, 1000 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _createBasicPermission() internal view returns (JustaPermissionManager.Permission memory) {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({
            target: address(erc20),
            selector: IERC20.transfer.selector
        });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: address(erc20),
            allowance: 100 ether,
            period: JustaPermissionManager.SpendPeriod.Day
        });

        return JustaPermissionManager.Permission({
            account: account,
            spender: spender,
            start: uint48(block.timestamp),
            end: uint48(block.timestamp + 1 days),
            salt: 1,
            calls: calls,
            spends: spends
        });
    }

    function _createPermissionWithNativeToken() internal view returns (JustaPermissionManager.Permission memory) {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({
            target: randomUser,
            selector: EMPTY_CALLDATA_FN_SEL
        });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: NATIVE_TOKEN,
            allowance: 1 ether,
            period: JustaPermissionManager.SpendPeriod.Day
        });

        return JustaPermissionManager.Permission({
            account: account,
            spender: spender,
            start: uint48(block.timestamp),
            end: uint48(block.timestamp + 1 days),
            salt: 2,
            calls: calls,
            spends: spends
        });
    }

    function _createPermissionNoSpendLimits() internal view returns (JustaPermissionManager.Permission memory) {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({
            target: address(erc20),
            selector: IERC20.transfer.selector
        });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](0);

        return JustaPermissionManager.Permission({
            account: account,
            spender: spender,
            start: uint48(block.timestamp),
            end: uint48(block.timestamp + 1 days),
            salt: 3,
            calls: calls,
            spends: spends
        });
    }

    function _createWildcardPermission() internal view returns (JustaPermissionManager.Permission memory) {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = JustaPermissionManager.CallPermission({
            target: ANY_TARGET,
            selector: ANY_FN_SEL
        });

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = JustaPermissionManager.SpendLimit({
            token: address(erc20),
            allowance: 100 ether,
            period: JustaPermissionManager.SpendPeriod.Day
        });

        return JustaPermissionManager.Permission({
            account: account,
            spender: spender,
            start: uint48(block.timestamp),
            end: uint48(block.timestamp + 1 days),
            salt: 4,
            calls: calls,
            spends: spends
        });
    }
}


