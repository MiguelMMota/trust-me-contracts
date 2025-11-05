// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Challenge} from "../../src/Challenge.sol";
import {DeploymentConfig} from "../config/DeploymentConfig.sol";

contract UpgradeChallenge is Script, DeploymentConfig {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        console.log("\n=== Upgrading Challenge ===");
        console.log("Network:", getNetworkName());

        if (!isDeployed("Challenge")) revert("Challenge proxy not found");
        address proxy = getContractAddress("Challenge");
        console.log("Proxy address:", proxy);

        startBroadcast();
        Challenge newImplementation = new Challenge();
        console.log("New implementation:", address(newImplementation));
        Challenge(proxy).upgradeToAndCall(address(newImplementation), "");
        console.log("Upgrade complete");
        vm.stopBroadcast();
    }
}
