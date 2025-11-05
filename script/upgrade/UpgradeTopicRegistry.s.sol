// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {TopicRegistry} from "../../src/TopicRegistry.sol";
import {DeploymentConfig} from "../config/DeploymentConfig.sol";

/**
 * @title UpgradeTopicRegistry
 * @notice Upgrades TopicRegistry implementation
 */
contract UpgradeTopicRegistry is Script, DeploymentConfig {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = getDeployer();

        console.log("\n=== Upgrading TopicRegistry ===");
        console.log("Upgrader:", deployer);
        console.log("Network:", getNetworkName());

        // Load existing proxy address
        if (!isDeployed("TopicRegistry")) {
            revert("TopicRegistry proxy not found. Deploy it first.");
        }
        address proxy = getContractAddress("TopicRegistry");
        console.log("Proxy address:", proxy);

        startBroadcast();

        // 1. Deploy new implementation
        TopicRegistry newImplementation = new TopicRegistry();
        console.log("New implementation deployed at:", address(newImplementation));

        // 2. Upgrade proxy to new implementation
        TopicRegistry proxyAsContract = TopicRegistry(proxy);
        proxyAsContract.upgradeToAndCall(address(newImplementation), "");

        console.log("Proxy upgraded successfully");

        vm.stopBroadcast();

        console.log("=== TopicRegistry Upgrade Complete ===\n");
    }
}
