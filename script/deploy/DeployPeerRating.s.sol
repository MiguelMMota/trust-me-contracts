// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PeerRating} from "../../src/PeerRating.sol";
import {DeploymentConfig} from "../config/DeploymentConfig.sol";

/**
 * @title DeployPeerRating
 * @notice Deploys PeerRating with UUPS proxy pattern
 * @dev Requires TopicRegistry and User to be deployed first
 */
contract DeployPeerRating is Script, DeploymentConfig {
    function run() external returns (address proxy) {
        address deployer = getDeployer();

        console.log("\n=== Deploying PeerRating ===");
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
        PeerRating implementation = new PeerRating();
        console.log("Implementation deployed at:", address(implementation));

        // 2. Encode initialize function call
        bytes memory initData = abi.encodeWithSelector(
            PeerRating.initialize.selector,
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
        updateContractAddress("PeerRating", proxy);

        console.log("=== PeerRating Deployment Complete ===\n");

        return proxy;
    }

    function fillData(address proxy) public {
        console.log("\n=== Creating Peer Ratings ===");

        startBroadcast();

        PeerRating peerRatingContract = PeerRating(proxy);

        // Define the 4 test users
        address[4] memory testUsers = [
            0xCDc986e956f889b6046F500657625E523f06D5F0,
            0x13dbAD22Ae32aaa90F7E9173C1fA519c064E4d65,
            0x28C02652dFc64202360E1A0B4f88FcedECB538a6,
            0xCACCbe50c1D788031d774dd886DA8F5Dc225ee06
        ];

        // Topic IDs from TopicRegistry (based on DeployTopicRegistry.fillData)
        // We have 13 topics total. 90% coverage = 12 topics
        // We'll select 12 topics (excluding one for variety)
        uint32[12] memory topicIds = [
            uint32(1), // Mathematics
            uint32(2), // Algebra
            uint32(3), // Calculus
            uint32(4), // History
            uint32(5), // World History
            uint32(6), // Languages
            uint32(7), // English
            uint32(8), // Spanish
            uint32(9), // Software Engineering
            uint32(10), // Frontend Development
            uint32(11), // Backend Development
            uint32(13) // Blockchain Development (skipping Python #12 for 90% coverage)
        ];

        vm.stopBroadcast();

        // Each user rates the other 3 users on 90% of topics (12 topics)
        uint256 totalRatings = 0;
        for (uint256 raterIdx = 0; raterIdx < testUsers.length; raterIdx++) {
            address rater = testUsers[raterIdx];

            for (uint256 rateeIdx = 0; rateeIdx < testUsers.length; rateeIdx++) {
                // Skip self-rating
                if (raterIdx == rateeIdx) continue;

                address ratee = testUsers[rateeIdx];

                // Rate on 12 topics (90% of 13)
                for (uint256 topicIdx = 0; topicIdx < topicIds.length; topicIdx++) {
                    uint32 topicId = topicIds[topicIdx];

                    // Generate pseudo-random scores between 300-900 for variety
                    // Using a deterministic approach based on indices
                    uint16 score = uint16(300 + ((raterIdx * 100 + rateeIdx * 50 + topicIdx * 30) % 600));

                    vm.startPrank(rater);
                    peerRatingContract.rateUser(ratee, topicId, score);
                    vm.stopPrank();

                    totalRatings++;
                }
            }

            console.log("User", raterIdx + 1, "completed ratings");
        }

        console.log("=== Peer Ratings Complete ===");
        console.log("Total ratings created:", totalRatings);
        console.log("Each user rated 3 other users on 12 topics");
        console.log("Coverage: 12/13 topics = 92.3%");
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
