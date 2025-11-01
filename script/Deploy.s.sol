// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/TopicRegistry.sol";
import "../src/User.sol";
import "../src/Challenge.sol";
import "../src/ReputationEngine.sol";
import "../src/Poll.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying contracts with address:", deployer);
        console.log("Account balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy contracts in correct order
        TopicRegistry topicRegistry = new TopicRegistry();
        console.log("TopicRegistry deployed at:", address(topicRegistry));

        User userContract = new User(address(topicRegistry));
        console.log("User deployed at:", address(userContract));

        Challenge challengeContract = new Challenge(address(topicRegistry), address(userContract));
        console.log("Challenge deployed at:", address(challengeContract));

        ReputationEngine reputationEngine = new ReputationEngine(
            address(userContract),
            address(challengeContract),
            address(topicRegistry)
        );
        console.log("ReputationEngine deployed at:", address(reputationEngine));

        Poll pollContract = new Poll(
            address(userContract),
            address(reputationEngine),
            address(topicRegistry)
        );
        console.log("Poll deployed at:", address(pollContract));

        // Set reputation engine references
        userContract.setReputationEngine(address(reputationEngine));
        challengeContract.setReputationEngine(address(reputationEngine));
        console.log("ReputationEngine references set");

        // Create initial topics
        uint32 mathId = topicRegistry.createTopic("Mathematics", 0);
        console.log("Created topic: Mathematics (ID:", mathId, ")");

        uint32 algebraId = topicRegistry.createTopic("Algebra", mathId);
        console.log("Created topic: Algebra (ID:", algebraId, ")");

        uint32 calculusId = topicRegistry.createTopic("Calculus", mathId);
        console.log("Created topic: Calculus (ID:", calculusId, ")");

        uint32 historyId = topicRegistry.createTopic("History", 0);
        console.log("Created topic: History (ID:", historyId, ")");

        uint32 worldHistoryId = topicRegistry.createTopic("World History", historyId);
        console.log("Created topic: World History (ID:", worldHistoryId, ")");

        uint32 languagesId = topicRegistry.createTopic("Languages", 0);
        console.log("Created topic: Languages (ID:", languagesId, ")");

        uint32 englishId = topicRegistry.createTopic("English", languagesId);
        console.log("Created topic: English (ID:", englishId, ")");

        uint32 spanishId = topicRegistry.createTopic("Spanish", languagesId);
        console.log("Created topic: Spanish (ID:", spanishId, ")");

        uint32 softwareId = topicRegistry.createTopic("Software Engineering", 0);
        console.log("Created topic: Software Engineering (ID:", softwareId, ")");

        uint32 frontendId = topicRegistry.createTopic("Frontend Development", softwareId);
        console.log("Created topic: Frontend Development (ID:", frontendId, ")");

        uint32 backendId = topicRegistry.createTopic("Backend Development", softwareId);
        console.log("Created topic: Backend Development (ID:", backendId, ")");

        uint32 pythonId = topicRegistry.createTopic("Python", backendId);
        console.log("Created topic: Python (ID:", pythonId, ")");

        uint32 blockchainId = topicRegistry.createTopic("Blockchain Development", softwareId);
        console.log("Created topic: Blockchain Development (ID:", blockchainId, ")");

        vm.stopBroadcast();

        // Save deployment addresses to a file
        string memory deploymentInfo = string.concat(
            "# TrustMe Contract Deployments\n\n",
            "## Network: ", vm.toString(block.chainid), "\n\n",
            "- **TopicRegistry**: ", vm.toString(address(topicRegistry)), "\n",
            "- **User**: ", vm.toString(address(userContract)), "\n",
            "- **Challenge**: ", vm.toString(address(challengeContract)), "\n",
            "- **ReputationEngine**: ", vm.toString(address(reputationEngine)), "\n",
            "- **Poll**: ", vm.toString(address(pollContract)), "\n\n",
            "## Topics Created:\n",
            "- Mathematics (", vm.toString(mathId), ")\n",
            "  - Algebra (", vm.toString(algebraId), ")\n",
            "  - Calculus (", vm.toString(calculusId), ")\n",
            "- History (", vm.toString(historyId), ")\n",
            "  - World History (", vm.toString(worldHistoryId), ")\n",
            "- Languages (", vm.toString(languagesId), ")\n",
            "  - English (", vm.toString(englishId), ")\n",
            "  - Spanish (", vm.toString(spanishId), ")\n",
            "- Software Engineering (", vm.toString(softwareId), ")\n",
            "  - Frontend Development (", vm.toString(frontendId), ")\n",
            "  - Backend Development (", vm.toString(backendId), ")\n",
            "    - Python (", vm.toString(pythonId), ")\n",
            "  - Blockchain Development (", vm.toString(blockchainId), ")\n"
        );

        vm.writeFile("deployments.md", deploymentInfo);
        console.log("\nDeployment info saved to deployments.md");
    }
}
