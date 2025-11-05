// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ReputationEngine} from "../../src/ReputationEngine.sol";
import {DeploymentConfig} from "../config/DeploymentConfig.sol";

contract UpgradeReputationEngine is Script, DeploymentConfig {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        console.log("\n=== Upgrading ReputationEngine ===");
        console.log("Network:", getNetworkName());

        if (!isDeployed("ReputationEngine")) revert("ReputationEngine proxy not found");
        address proxy = getContractAddress("ReputationEngine");
        console.log("Proxy address:", proxy);

        vm.startBroadcast(deployerPrivateKey);
        ReputationEngine newImplementation = new ReputationEngine();
        console.log("New implementation:", address(newImplementation));
        ReputationEngine(proxy).upgradeToAndCall(address(newImplementation), "");
        console.log("Upgrade complete");
        vm.stopBroadcast();
    }
}
