// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {PeerRating} from "../../src/PeerRating.sol";
import {DeploymentConfig} from "../config/DeploymentConfig.sol";

contract UpgradePeerRating is Script, DeploymentConfig {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        console.log("\n=== Upgrading PeerRating ===");
        console.log("Network:", getNetworkName());

        if (!isDeployed("PeerRating")) revert("PeerRating proxy not found");
        address proxy = getContractAddress("PeerRating");
        console.log("Proxy address:", proxy);

        vm.startBroadcast(deployerPrivateKey);
        PeerRating newImplementation = new PeerRating();
        console.log("New implementation:", address(newImplementation));
        PeerRating(proxy).upgradeToAndCall(address(newImplementation), "");
        console.log("Upgrade complete");
        vm.stopBroadcast();
    }
}
