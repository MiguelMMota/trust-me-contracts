// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Challenge} from "../../src/Challenge.sol";
import {DeploymentConfig} from "../config/DeploymentConfig.sol";

/**
 * @title DeployChallenge
 * @notice Deploys Challenge with UUPS proxy pattern
 * @dev Requires TopicRegistry and User to be deployed first
 */
contract DeployChallenge is Script, DeploymentConfig {
    function run() external returns (address proxy) {
        address deployer = getDeployer();

        console.log("\n=== Deploying Challenge ===");
        console.log("Deployer:", deployer);
        console.log("Network:", getNetworkName());

        // Check dependencies
        if (!isDeployed("TopicRegistry")) {
            revert("TopicRegistry must be deployed first");
        }
        if (!isDeployed("User")) {
            revert("User must be deployed first");
        }

        address topicRegistry = getContractAddress("TopicRegistry");
        address user = getContractAddress("User");
        console.log("Using TopicRegistry at:", topicRegistry);
        console.log("Using User at:", user);

        startBroadcast();

        // 1. Deploy implementation
        Challenge implementation = new Challenge();
        console.log("Implementation deployed at:", address(implementation));

        // 2. Encode initialize function call
        bytes memory initData = abi.encodeWithSelector(
            Challenge.initialize.selector,
            deployer, // initialOwner
            topicRegistry, // _topicRegistry
            user // _userContract
        );

        // 3. Deploy proxy
        ERC1967Proxy proxyContract = new ERC1967Proxy(address(implementation), initData);
        proxy = address(proxyContract);
        console.log("Proxy deployed at:", proxy);

        vm.stopBroadcast();

        // 4. Save deployment
        updateContractAddress("Challenge", proxy);

        console.log("=== Challenge Deployment Complete ===\n");

        return proxy;
    }
}
