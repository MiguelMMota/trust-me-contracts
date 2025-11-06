// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ReputationEngine} from "../../src/ReputationEngine.sol";
import {DeploymentConfig} from "../config/DeploymentConfig.sol";

/**
 * @title DeployReputationEngine
 * @notice Deploys ReputationEngine with UUPS proxy pattern
 * @dev Requires User, Challenge, and TopicRegistry to be deployed first
 */
contract DeployReputationEngine is Script, DeploymentConfig {
    function run() external returns (address proxy) {
        address deployer = getDeployer();

        console.log("\n=== Deploying ReputationEngine ===");
        console.log("Deployer:", deployer);
        console.log("Network:", getNetworkName());

        // Check dependencies
        if (!isDeployed("User")) {
            revert("User must be deployed first");
        }
        if (!isDeployed("Challenge")) {
            revert("Challenge must be deployed first");
        }
        if (!isDeployed("TopicRegistry")) {
            revert("TopicRegistry must be deployed first");
        }

        address user = getContractAddress("User");
        address challenge = getContractAddress("Challenge");
        address topicRegistry = getContractAddress("TopicRegistry");
        console.log("Using User at:", user);
        console.log("Using Challenge at:", challenge);
        console.log("Using TopicRegistry at:", topicRegistry);

        startBroadcast();

        // 1. Deploy implementation
        ReputationEngine implementation = new ReputationEngine();
        console.log("Implementation deployed at:", address(implementation));

        // 2. Encode initialize function call
        bytes memory initData = abi.encodeWithSelector(
            ReputationEngine.initialize.selector,
            deployer, // initialOwner
            user, // _userContract
            challenge, // _challengeContract
            topicRegistry // _topicRegistry
        );

        // 3. Deploy proxy
        ERC1967Proxy proxyContract = new ERC1967Proxy(address(implementation), initData);
        proxy = address(proxyContract);
        console.log("Proxy deployed at:", proxy);

        vm.stopBroadcast();

        // 4. Save deployment
        updateContractAddress("ReputationEngine", proxy);

        console.log("=== ReputationEngine Deployment Complete ===\n");

        return proxy;
    }

    function fillData(address proxy) public {}

    /**
     * @notice Deploys TopicRegistry with initial test data
     * @dev Creates a predefined topic hierarchy for testing/development
     * @return proxy The address of the deployed proxy contract
     */
    function runWithData() external returns (address proxy) {
        // First deploy the contract
        proxy = this.run();
        this.fillData(proxy);

        return proxy;
    }
}
