// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Poll} from "../../src/Poll.sol";
import {DeploymentConfig} from "../config/DeploymentConfig.sol";

contract UpgradePoll is Script, DeploymentConfig {
    function run() external {
        console.log("\n=== Upgrading Poll ===");
        console.log("Network:", getNetworkName());

        if (!isDeployed("Poll")) revert("Poll proxy not found");
        address proxy = getContractAddress("Poll");
        console.log("Proxy address:", proxy);

        vm.startBroadcast();
        Poll newImplementation = new Poll();
        console.log("New implementation:", address(newImplementation));
        Poll(proxy).upgradeToAndCall(address(newImplementation), "");
        console.log("Upgrade complete");
        vm.stopBroadcast();
    }
}
