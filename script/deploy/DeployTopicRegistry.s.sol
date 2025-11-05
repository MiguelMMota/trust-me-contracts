// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TopicRegistry} from "../../src/TopicRegistry.sol";
import {DeploymentConfig} from "../config/DeploymentConfig.sol";

/**
 * @title DeployTopicRegistry
 * @notice Deploys TopicRegistry with UUPS proxy pattern
 */
contract DeployTopicRegistry is Script, DeploymentConfig {
    function run() external returns (address proxy) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = getDeployer();

        console.log("\n=== Deploying TopicRegistry ===");
        console.log("Deployer:", deployer);
        console.log("Network:", getNetworkName());

        startBroadcast();

        // 1. Deploy implementation
        TopicRegistry implementation = new TopicRegistry();
        console.log("Implementation deployed at:", address(implementation));

        // 2. Encode initialize function call
        bytes memory initData = abi.encodeWithSelector(
            TopicRegistry.initialize.selector,
            deployer // initialOwner
        );

        // 3. Deploy proxy
        ERC1967Proxy proxyContract = new ERC1967Proxy(address(implementation), initData);
        proxy = address(proxyContract);
        console.log("Proxy deployed at:", proxy);

        vm.stopBroadcast();

        // 4. Save deployment
        updateContractAddress("TopicRegistry", proxy);

        console.log("=== TopicRegistry Deployment Complete ===\n");

        return proxy;
    }
}
