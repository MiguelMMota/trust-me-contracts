// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {User} from "../src/User.sol";
import {Challenge} from "../src/Challenge.sol";
import {PeerRating} from "../src/PeerRating.sol";
import {ReputationEngine} from "../src/ReputationEngine.sol";
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
        topicRegistryDeployer.runWithData();

        DeployUser userDeployer = new DeployUser();
        address userContract = userDeployer.runWithData();

        DeployChallenge challengeDeployer = new DeployChallenge();
        address challengeContract = challengeDeployer.runWithData();

        DeployPeerRating peerRatingDeployer = new DeployPeerRating();
        address peerRatingContract = peerRatingDeployer.runWithData();

        DeployReputationEngine reputationEngineDeployer = new DeployReputationEngine();
        address reputationEngine = reputationEngineDeployer.runWithData();

        DeployPoll pollDeployer = new DeployPoll();
        pollDeployer.runWithData();

        // Set cross-contract references
        console.log("\n=== Setting Cross-Contract References ===");
        vm.startBroadcast();

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

        vm.stopBroadcast();

        // Print deployment summary
        console.log("\n===============================================");
        console.log("         Deployment Summary");
        console.log("===============================================");
        printDeploymentStatus();
        console.log("===============================================");
        console.log("\nDeployment complete! Config saved to:");
        console.log(getDeploymentPath());
        console.log("===============================================\n");
    }
}
