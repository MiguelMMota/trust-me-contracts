// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {User} from "../../src/User.sol";
import {DeploymentConfig} from "../config/DeploymentConfig.sol";

/**
 * @title UpgradeUser
 * @notice Upgrades User implementation
 */
contract UpgradeUser is Script, DeploymentConfig {
    function run() external {
        address deployer = getDeployer();

        console.log("\n=== Upgrading User ===");
        console.log("Upgrader:", deployer);
        console.log("Network:", getNetworkName());

        if (!isDeployed("User")) {
            revert("User proxy not found. Deploy it first.");
        }
        address proxy = getContractAddress("User");
        console.log("Proxy address:", proxy);

        vm.startBroadcast();

        User newImplementation = new User();
        console.log("New implementation deployed at:", address(newImplementation));

        User proxyAsContract = User(proxy);
        proxyAsContract.upgradeToAndCall(address(newImplementation), "");

        console.log("Proxy upgraded successfully");
        vm.stopBroadcast();

        console.log("=== User Upgrade Complete ===\n");
    }
}
