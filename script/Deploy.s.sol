// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Challenge} from "../src/Challenge.sol";
import {PeerRating} from "../src/PeerRating.sol";
import {Poll} from "../src/Poll.sol";
import {ReputationEngine} from "../src/ReputationEngine.sol";
import {TopicRegistry} from "../src/TopicRegistry.sol";
import {User} from "../src/User.sol";
import {DeploymentConfig} from "./config/DeploymentConfig.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployScript
 * @notice Orchestrates full deployment of all contracts using modular scripts
 * @dev Uses UUPS proxy pattern for upgradeable contracts
 */
contract DeployScript is Script, DeploymentConfig {
    /*//////////////////////////
       STATE VARIABLES
    //////////////////////////*/

    // Sepolia testnet user addresses
    address[4] private SEPOLIA_TEST_USERS = [
        0xCDc986e956f889b6046F500657625E523f06D5F0,
        0x13dbAD22Ae32aaa90F7E9173C1fA519c064E4d65,
        0x28C02652dFc64202360E1A0B4f88FcedECB538a6,
        0xCACCbe50c1D788031d774dd886DA8F5Dc225ee06
    ];

    /*//////////////////////////
           FUNCTIONS
    //////////////////////////*/

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
        // Each deployer handles its own broadcasting
        deployTopicRegistry(deployer);
        address userContract = deployUser(deployer);
        address challengeContract = deployChallenge(deployer);
        address peerRatingContract = deployPeerRating(deployer);
        address reputationEngineContract = deployReputationEngine(deployer);
        deployPoll(deployer);

        // Set cross-contract references
        console.log("\n=== Setting Cross-Contract References ===");

        vm.startBroadcast(deployer);

        User(userContract).setReputationEngine(reputationEngineContract);
        console.log("User.setReputationEngine()");

        User(userContract).setPeerRatingContract(peerRatingContract);
        console.log("User.setPeerRatingContract()");

        Challenge(challengeContract).setReputationEngine(reputationEngineContract);
        console.log("Challenge.setReputationEngine()");

        PeerRating(peerRatingContract).setReputationEngine(reputationEngineContract);
        console.log("PeerRating.setReputationEngine()");

        ReputationEngine(reputationEngineContract).setPeerRatingContract(peerRatingContract);
        console.log("ReputationEngine.setPeerRatingContract()");

        vm.sleep(2000);

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

    /**
     * @notice Returns Anvil's default test account addresses
     * @dev These are the first 20 addresses generated from the mnemonic:
     *      "test test test test test test test test test test test junk"
     * @return addresses Array of 20 Anvil default addresses
     */
    function getAnvilAddresses() private pure returns (address[20] memory addresses) {
        addresses[0] = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        addresses[1] = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
        addresses[2] = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
        addresses[3] = 0x90F79bf6EB2c4f870365E785982E1f101E93b906;
        addresses[4] = 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65;
        addresses[5] = 0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc;
        addresses[6] = 0x976EA74026E726554dB657fA54763abd0C3a0aa9;
        addresses[7] = 0x14dC79964da2C08b23698B3D3cc7Ca32193d9955;
        addresses[8] = 0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f;
        addresses[9] = 0xa0Ee7A142d267C1f36714E4a8F75612F20a79720;
    }

    /**
     * @notice Returns test user addresses based on the deployment network
     * @dev Returns Anvil addresses for local network, Sepolia addresses for testnet
     * @param maxAddresses Maximum number of addresses to return
     * @return testUsers Dynamic array of test user addresses (up to maxAddresses)
     */
    function getTestUserAddresses(uint256 maxAddresses) private view returns (address[] memory testUsers) {
        string memory networkName = getNetworkName();

        if (keccak256(bytes(networkName)) == keccak256(bytes("anvil"))) {
            // Local network: use Anvil addresses
            address[20] memory anvilAddresses = getAnvilAddresses();
            uint256 count = maxAddresses > 20 ? 20 : maxAddresses;
            testUsers = new address[](count);

            for (uint256 i = 0; i < count; i++) {
                testUsers[i] = anvilAddresses[i];
            }
        } else {
            // Sepolia or other network: use configured addresses
            uint256 count = maxAddresses > SEPOLIA_TEST_USERS.length ? SEPOLIA_TEST_USERS.length : maxAddresses;
            testUsers = new address[](count);

            for (uint256 i = 0; i < count; i++) {
                testUsers[i] = SEPOLIA_TEST_USERS[i];
            }
        }
    }

    function deployChallenge(address deployer) private returns (address proxy) {
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

        vm.startBroadcast(deployer);

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

    function deployPeerRating(address deployer) private returns (address proxy) {
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

        vm.startBroadcast(deployer);

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

        fillPeerRatingData(proxy, deployer);

        return proxy;
    }

    function deployPoll(address deployer) private returns (address proxy) {
        console.log("\n=== Deploying Poll ===");
        console.log("Deployer:", deployer);
        console.log("Network:", getNetworkName());

        // Check dependencies
        if (!isDeployed("User")) {
            revert("User must be deployed first");
        }
        if (!isDeployed("ReputationEngine")) {
            revert("ReputationEngine must be deployed first");
        }
        if (!isDeployed("TopicRegistry")) {
            revert("TopicRegistry must be deployed first");
        }

        address user = getContractAddress("User");
        address reputationEngine = getContractAddress("ReputationEngine");
        address topicRegistry = getContractAddress("TopicRegistry");
        console.log("Using User at:", user);
        console.log("Using ReputationEngine at:", reputationEngine);
        console.log("Using TopicRegistry at:", topicRegistry);

        vm.startBroadcast(deployer);

        // 1. Deploy implementation
        Poll implementation = new Poll();
        console.log("Implementation deployed at:", address(implementation));

        // 2. Encode initialize function call
        bytes memory initData = abi.encodeWithSelector(
            Poll.initialize.selector,
            deployer, // initialOwner
            user, // _userContract
            reputationEngine, // _reputationEngine
            topicRegistry // _topicRegistry
        );

        // 3. Deploy proxy
        ERC1967Proxy proxyContract = new ERC1967Proxy(address(implementation), initData);
        proxy = address(proxyContract);
        console.log("Proxy deployed at:", proxy);

        vm.stopBroadcast();

        // 4. Save deployment
        updateContractAddress("Poll", proxy);

        console.log("=== Poll Deployment Complete ===\n");

        return proxy;
    }

    function deployReputationEngine(address deployer) private returns (address proxy) {
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

        vm.startBroadcast(deployer);

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

    function deployTopicRegistry(address deployer) private returns (address proxy) {
        console.log("\n=== Deploying TopicRegistry ===");
        console.log("Deployer:", deployer);
        console.log("Network:", getNetworkName());

        vm.startBroadcast(deployer);

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

        fillTopicRegistryData(proxy, deployer);

        return proxy;
    }

    function deployUser(address deployer) private returns (address proxy) {
        console.log("\n=== Deploying User ===");
        console.log("Deployer:", deployer);
        console.log("Network:", getNetworkName());

        // Check if TopicRegistry is deployed
        if (!isDeployed("TopicRegistry")) {
            revert("TopicRegistry must be deployed first");
        }
        address topicRegistry = getContractAddress("TopicRegistry");
        console.log("Using TopicRegistry at:", topicRegistry);

        vm.startBroadcast(deployer);

        // 1. Deploy implementation
        User implementation = new User();
        console.log("Implementation deployed at:", address(implementation));

        // 2. Encode initialize function call
        bytes memory initData = abi.encodeWithSelector(
            User.initialize.selector,
            deployer, // initialOwner
            topicRegistry // _topicRegistry
        );

        // 3. Deploy proxy
        ERC1967Proxy proxyContract = new ERC1967Proxy(address(implementation), initData);
        proxy = address(proxyContract);
        console.log("Proxy deployed at:", proxy);

        vm.stopBroadcast();

        // 4. Save deployment
        updateContractAddress("User", proxy);

        console.log("=== User Deployment Complete ===\n");

        fillUserData(proxy, deployer);

        return proxy;
    }

    function fillPeerRatingData(address proxy, address deployer) private {
        console.log("\n=== Creating Peer Ratings ===");

        PeerRating peerRatingContract = PeerRating(proxy);

        // Get test users based on network (Anvil or Sepolia)
        address[] memory testUsers = getTestUserAddresses(4);

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

        vm.startBroadcast(deployer);

        // Each user rates the other 3 users on 90% of topics (12 topics)
        uint256 totalRatings = 0;

        // this has to be done in a flat list to prevent "too deep in the stack" errors
        uint256 i = 0;
        totalRatings += _createRatingsForUser(peerRatingContract, testUsers, testUsers[i], i, topicIds);

        i++;
        totalRatings += _createRatingsForUser(peerRatingContract, testUsers, testUsers[i], i, topicIds);

        i++;
        totalRatings += _createRatingsForUser(peerRatingContract, testUsers, testUsers[i], i, topicIds);

        i++;
        totalRatings += _createRatingsForUser(peerRatingContract, testUsers, testUsers[i], i, topicIds);

        vm.stopBroadcast();

        console.log("=== Peer Ratings Complete ===");
        console.log("Total ratings created:", totalRatings);
        console.log("Each user rated 3 other users on 12 topics");
        console.log("Coverage: 12/13 topics = 92.3%");
        console.log("===============================================\n");
    }

    function _createRatingsForUser(
        PeerRating peerRatingContract,
        address[] memory testUsers,
        address rater,
        uint256 raterIdx,
        uint32[12] memory topicIds
    ) private returns (uint256 ratingsCreated) {
        ratingsCreated = 0;

        for (uint256 rateeIdx = 0; rateeIdx < testUsers.length; rateeIdx++) {
            // Skip self-rating
            if (raterIdx == rateeIdx) continue;

            address ratee = testUsers[rateeIdx];

            // Rate on all but the last topic
            for (uint256 topicIdx = 0; topicIdx < topicIds.length - 1; topicIdx++) {
                // Generate pseudo-random scores for variety
                uint16 score = uint16((raterIdx * 678 + rateeIdx * 901 + topicIdx * 234) % 1001); // TODO: Replace 1001 with PeerRating.MAX_RATING() + 1

                peerRatingContract.adminRateUser(rater, ratee, topicIds[topicIdx], score);

                ratingsCreated++;
            }

            vm.sleep(2000);
        }

        console.log("User", raterIdx + 1, "completed ratings");
    }

    function fillTopicRegistryData(address proxy, address deployer) private {
        console.log("\n=== Creating Initial Topic Hierarchy ===");

        vm.startBroadcast(deployer);

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

        vm.sleep(2000);

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

    function fillUserData(address proxy, address deployer) private {
        console.log("\n=== Creating Test Users ===");

        vm.startBroadcast(deployer);

        User userContract = User(proxy);

        // Get test users based on network (Anvil or Sepolia)
        address[] memory testUsers = getTestUserAddresses(4);
        string[4] memory testUserNames = ["Alice", "Bob", "Charlie", "David"];

        for (uint256 i = 0; i < testUsers.length; i++) {
            userContract.adminRegisterUser(testUsers[i], testUserNames[i]);
            console.log("User registered:", testUsers[i]);
            console.log("Name:", testUserNames[i]);
        }

        vm.stopBroadcast();

        vm.sleep(2000);

        console.log("=== User Registration Complete ===");
        console.log("4 users have been registered");
        console.log("===============================================\n");
    }
}
