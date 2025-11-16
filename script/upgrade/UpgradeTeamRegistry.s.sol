// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TeamRegistry} from "../../src/TeamRegistry.sol";
import {DeploymentConfig} from "../config/DeploymentConfig.sol";

/**
 * @title UpgradeTeamRegistry
 * @notice Upgrades TeamRegistry implementation
 */
contract UpgradeTeamRegistry is Script, DeploymentConfig {
    function run() external {
        address deployer = getDeployer();

        console.log("\n=== Upgrading TeamRegistry ===");
        console.log("Upgrader:", deployer);
        console.log("Network:", getNetworkName());

        // Load existing proxy address
        if (!isDeployed("TeamRegistry")) {
            revert("TeamRegistry proxy not found. Deploy it first.");
        }
        address proxy = getContractAddress("TeamRegistry");
        console.log("Proxy address:", proxy);

        vm.startBroadcast();

        // 1. Deploy new implementation
        TeamRegistry newImplementation = new TeamRegistry();
        console.log("New implementation deployed at:", address(newImplementation));

        // 2. Upgrade proxy to new implementation
        TeamRegistry proxyAsContract = TeamRegistry(proxy);
        proxyAsContract.upgradeToAndCall(address(newImplementation), "");

        console.log("Proxy upgraded successfully");

        vm.stopBroadcast();

        console.log("=== TeamRegistry Upgrade Complete ===\n");
    }
}
