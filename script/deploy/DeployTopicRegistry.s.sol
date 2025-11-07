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
    function run() public returns (address proxy) {
        address deployer = getDeployer();

        console.log("\n=== Deploying TopicRegistry ===");
        console.log("Deployer:", deployer);
        console.log("Network:", getNetworkName());

        vm.startBroadcast();

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

    function fillData(address proxy) public {
        console.log("\n=== Creating Initial Topic Hierarchy ===");

        vm.startBroadcast();

        TopicRegistry topicRegistry = TopicRegistry(proxy);

        // Create initial topic hierarchy
        uint32 mathId = topicRegistry.createTopic("Mathematics", 0);
        uint32 algebraId = topicRegistry.createTopic("Algebra", mathId);
        uint32 calculusId = topicRegistry.createTopic("Calculus", mathId);

        uint32 historyId = topicRegistry.createTopic("History", 0);
        uint32 worldHistoryId = topicRegistry.createTopic("World History", historyId);

        uint32 languagesId = topicRegistry.createTopic("Languages", 0);
        uint32 englishId = topicRegistry.createTopic("English", languagesId);
        uint32 spanishId = topicRegistry.createTopic("Spanish", languagesId);

        uint32 softwareId = topicRegistry.createTopic("Software Engineering", 0);
        uint32 frontendId = topicRegistry.createTopic("Frontend Development", softwareId);
        uint32 backendId = topicRegistry.createTopic("Backend Development", softwareId);
        uint32 pythonId = topicRegistry.createTopic("Python", backendId);
        uint32 blockchainId = topicRegistry.createTopic("Blockchain Development", softwareId);

        console.log("Created 13 topics across 4 root categories");

        vm.stopBroadcast();

        console.log("=== Topic Hierarchy Complete ===");
        console.log("Topics Created:");
        console.log("  - Mathematics (", mathId, ")");
        console.log("    - Algebra (", algebraId, ")");
        console.log("    - Calculus (", calculusId, ")");
        console.log("  - History (", historyId, ")");
        console.log("    - World History (", worldHistoryId, ")");
        console.log("  - Languages (", languagesId, ")");
        console.log("    - English (", englishId, ")");
        console.log("    - Spanish (", spanishId, ")");
        console.log("  - Software Engineering (", softwareId, ")");
        console.log("    - Frontend Development (", frontendId, ")");
        console.log("    - Backend Development (", backendId, ")");
        console.log("      - Python (", pythonId, ")");
        console.log("    - Blockchain Development (", blockchainId, ")");
        console.log("===============================================\n");
    }

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
