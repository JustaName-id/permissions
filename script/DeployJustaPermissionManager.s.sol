// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { Script, console2 } from "forge-std/Script.sol";
import { SafeSingletonDeployer } from "safe-singleton-deployer-sol/src/SafeSingletonDeployer.sol";

import { JustaPermissionManager } from "../src/JustaPermissionManager.sol";

/**
 * @notice Deploy the JustaPermissionManager contract.
 */
contract DeployJustaPermissionManager is Script {

    address constant EXPECTED_MANAGER = address(0);

    bytes32 constant MANAGER_SALT = 0x0000000000000000000000000000000000000000000000000000000000000000;

    function run() public {
        console2.log("Deploying on chain ID", block.chainid);

        if (block.chainid == 31_337) {
            vm.startBroadcast();
            deploy();
            vm.stopBroadcast();
        } else {
            deployWithSafeSingleton();
        }
    }

    function deploy() internal {
        JustaPermissionManager manager = new JustaPermissionManager{ salt: 0 }();

        logAddress("JustaPermissionManager", address(manager));
    }

    function deployWithSafeSingleton() internal {
        // Deploy manager
        address manager = SafeSingletonDeployer.broadcastDeploy({
            creationCode: type(JustaPermissionManager).creationCode, args: "", salt: MANAGER_SALT
        });

        console2.log("Deployed JustaPermissionManager:", manager);
        if (EXPECTED_MANAGER != address(0)) {
            assert(manager == EXPECTED_MANAGER); // Safety check
        }

        logAddress("JustaPermissionManager", manager);
    }

    function logAddress(string memory name, address addr) internal pure {
        console2.logString(string.concat(name, ": ", Strings.toHexString(addr)));
    }

}
