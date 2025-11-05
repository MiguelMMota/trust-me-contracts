// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TopicRegistry} from "../src/TopicRegistry.sol";
import {User} from "../src/User.sol";
import {Challenge} from "../src/Challenge.sol";
import {PeerRating} from "../src/PeerRating.sol";
import {ReputationEngine} from "../src/ReputationEngine.sol";
import {Poll} from "../src/Poll.sol";
import {DeploymentConfig} from "./config/DeploymentConfig.sol";
import {DeployTopicRegistry} from "./deploy/DeployTopicRegistry.s.sol";
import {DeployUser} from "./deploy/DeployUser.s.sol";
import {DeployChallenge} from "./deploy/DeployChallenge.s.sol";
import {DeployPeerRating} from "./deploy/DeployPeerRating.s.sol";
import {DeployReputationEngine} from "./deploy/DeployReputationEngine.s.sol";
import {DeployPoll} from "./deploy/DeployPoll.s.sol";

/**
 * @title DeployScript
 * @notice Orchestrates full deployment of all contracts using modular scripts
 * @dev Uses UUPS proxy pattern for upgradeable contracts
 */
contract DeployScript is Script, DeploymentConfig {
    function run() external {
        address deployer = getDeployer();

        console.log("\n===============================================");
        console.log("   TrustMe Full Deployment with Proxies");
        console.log("===============================================");
        console.log("Deployer:", deployer);
        console.log("Network:", getNetworkName());
        console.log("Balance:", deployer.balance);
        console.log("===============================================\n");

        // Deploy all contracts using individual scripts
        DeployTopicRegistry topicRegistryDeployer = new DeployTopicRegistry();
        address topicRegistry = topicRegistryDeployer.run();

        DeployUser userDeployer = new DeployUser();
        address userContract = userDeployer.run();

        DeployChallenge challengeDeployer = new DeployChallenge();
        address challengeContract = challengeDeployer.run();

        DeployPeerRating peerRatingDeployer = new DeployPeerRating();
        address peerRatingContract = peerRatingDeployer.run();

        DeployReputationEngine reputationEngineDeployer = new DeployReputationEngine();
        address reputationEngine = reputationEngineDeployer.run();

        DeployPoll pollDeployer = new DeployPoll();
        address pollContract = pollDeployer.run();

        // Set cross-contract references
        console.log("\n=== Setting Cross-Contract References ===");
        startBroadcast();

        User(userContract).setReputationEngine(reputationEngine);
        console.log("User.setReputationEngine()");

        User(userContract).setPeerRatingContract(peerRatingContract);
        console.log("User.setPeerRatingContract()");

        Challenge(challengeContract).setReputationEngine(reputationEngine);
        console.log("Challenge.setReputationEngine()");

        PeerRating(peerRatingContract).setReputationEngine(reputationEngine);
        console.log("PeerRating.setReputationEngine()");

        ReputationEngine(reputationEngine).setPeerRatingContract(peerRatingContract);
        console.log("ReputationEngine.setPeerRatingContract()");

        console.log("=== Cross-Contract References Complete ===\n");

        // Create initial topic hierarchy
        console.log("=== Creating Initial Topic Hierarchy ===");

        uint32 mathId = TopicRegistry(topicRegistry).createTopic("Mathematics", 0);
        uint32 algebraId = TopicRegistry(topicRegistry).createTopic("Algebra", mathId);
        uint32 calculusId = TopicRegistry(topicRegistry).createTopic("Calculus", mathId);

        uint32 historyId = TopicRegistry(topicRegistry).createTopic("History", 0);
        uint32 worldHistoryId = TopicRegistry(topicRegistry).createTopic("World History", historyId);

        uint32 languagesId = TopicRegistry(topicRegistry).createTopic("Languages", 0);
        uint32 englishId = TopicRegistry(topicRegistry).createTopic("English", languagesId);
        uint32 spanishId = TopicRegistry(topicRegistry).createTopic("Spanish", languagesId);

        uint32 softwareId = TopicRegistry(topicRegistry).createTopic("Software Engineering", 0);
        uint32 frontendId = TopicRegistry(topicRegistry).createTopic("Frontend Development", softwareId);
        uint32 backendId = TopicRegistry(topicRegistry).createTopic("Backend Development", softwareId);
        uint32 pythonId = TopicRegistry(topicRegistry).createTopic("Python", backendId);
        uint32 blockchainId = TopicRegistry(topicRegistry).createTopic("Blockchain Development", softwareId);

        console.log("Created 13 topics across 4 root categories");

        vm.stopBroadcast();

        console.log("=== Topic Hierarchy Complete ===\n");

        // Print deployment summary
        console.log("\n===============================================");
        console.log("         Deployment Summary");
        console.log("===============================================");
        printDeploymentStatus();
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
        console.log("===============================================");
        console.log("\nDeployment complete! Config saved to:");
        console.log(getDeploymentPath());
        console.log("===============================================\n");
    }
}
