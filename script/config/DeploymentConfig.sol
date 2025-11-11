// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

contract ServerConstants {
    // Anvil's first default account (corresponding to private key used in justfile)
    address public constant ANVIL_DEFAULT_ACCOUNT = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    uint256 public constant LOCAL_CHAIN_ID = 31337;
    uint256 public constant SEPOLIA_ETH_CHAIN_ID = 11_155_111;
}

/**
 * @title DeploymentConfig
 * @notice Manages deployed contract addresses across different networks
 * @dev Provides helpers to read/write deployment addresses from JSON files
 */
abstract contract DeploymentConfig is Script, ServerConstants {
    /*//////////////////////////
          STRUCTS
    //////////////////////////*/

    struct Deployment {
        address topicRegistry;
        address user;
        address challenge;
        address peerRating;
        address reputationEngine;
        address poll;
    }

    /*//////////////////////////
       STATE VARIABLES
    //////////////////////////*/

    string constant DEPLOYMENTS_DIR = "deployments/";

    /*//////////////////////////
      INTERNAL FUNCTIONS
    //////////////////////////*/

    /**
     * @notice Get deployer address - works with both cast wallet and env var
     * @dev When using --account flag, msg.sender is the account
     *      When on Sepolia, reads from SEPOLIA_TEST_ACCOUNT env var
     *      For local/Anvil, uses Anvil's first default account
     */
    function getDeployer() internal view returns (address) {
        if (block.chainid == SEPOLIA_ETH_CHAIN_ID) {
            return vm.envAddress("SEPOLIA_TEST_ACCOUNT");
        } else {
            return ANVIL_DEFAULT_ACCOUNT;
        }
    }

    /**
     * @notice Get network name from chain ID
     */
    function getNetworkName() internal view returns (string memory) {
        uint256 chainId = block.chainid;

        if (chainId == 1) return "mainnet";
        if (chainId == 11155111) return "sepolia";
        if (chainId == 31337) return "anvil";

        return string(abi.encodePacked("unknown-", vm.toString(chainId)));
    }

    /**
     * @notice Get deployment file path for current network
     */
    function getDeploymentPath() internal view returns (string memory) {
        return string(abi.encodePacked(DEPLOYMENTS_DIR, getNetworkName(), ".json"));
    }

    /**
     * @notice Load deployed addresses from JSON file
     */
    function loadDeployment() internal view returns (Deployment memory deployment) {
        string memory path = getDeploymentPath();

        // Check if file exists
        try vm.readFile(path) returns (string memory json) {
            deployment.topicRegistry = vm.parseJsonAddress(json, ".topicRegistry");
            deployment.user = vm.parseJsonAddress(json, ".user");
            deployment.challenge = vm.parseJsonAddress(json, ".challenge");
            deployment.peerRating = vm.parseJsonAddress(json, ".peerRating");
            deployment.reputationEngine = vm.parseJsonAddress(json, ".reputationEngine");
            deployment.poll = vm.parseJsonAddress(json, ".poll");

            console.log("Loaded deployment config from:", path);
        } catch {
            console.log("No existing deployment found at:", path);
            // Return empty deployment
        }

        return deployment;
    }

    /**
     * @notice Save deployed addresses to JSON file
     */
    function saveDeployment(Deployment memory deployment) internal {
        string memory path = getDeploymentPath();

        // Build JSON manually
        string memory json = string(
            abi.encodePacked(
                "{\n",
                '  "network": "',
                getNetworkName(),
                '",\n',
                '  "chainId": ',
                vm.toString(block.chainid),
                ",\n",
                '  "timestamp": ',
                vm.toString(block.timestamp),
                ",\n",
                '  "topicRegistry": "',
                vm.toString(deployment.topicRegistry),
                '",\n',
                '  "user": "',
                vm.toString(deployment.user),
                '",\n',
                '  "challenge": "',
                vm.toString(deployment.challenge),
                '",\n',
                '  "peerRating": "',
                vm.toString(deployment.peerRating),
                '",\n',
                '  "reputationEngine": "',
                vm.toString(deployment.reputationEngine),
                '",\n',
                '  "poll": "',
                vm.toString(deployment.poll),
                '"\n',
                "}"
            )
        );

        vm.writeFile(path, json);
        console.log("Saved deployment config to:", path);
    }

    /**
     * @notice Update a single contract address in deployment
     */
    function updateContractAddress(string memory contractName, address newAddress) internal {
        Deployment memory deployment = loadDeployment();

        if (keccak256(bytes(contractName)) == keccak256(bytes("TopicRegistry"))) {
            deployment.topicRegistry = newAddress;
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("User"))) {
            deployment.user = newAddress;
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("Challenge"))) {
            deployment.challenge = newAddress;
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("PeerRating"))) {
            deployment.peerRating = newAddress;
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("ReputationEngine"))) {
            deployment.reputationEngine = newAddress;
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("Poll"))) {
            deployment.poll = newAddress;
        } else {
            revert(string(abi.encodePacked("Unknown contract: ", contractName)));
        }

        saveDeployment(deployment);
        console.log("Updated", contractName, "address to:", newAddress);
    }

    /**
     * @notice Check if a contract has been deployed
     */
    function isDeployed(string memory contractName) internal view returns (bool) {
        Deployment memory deployment = loadDeployment();

        if (keccak256(bytes(contractName)) == keccak256(bytes("TopicRegistry"))) {
            return deployment.topicRegistry != address(0);
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("User"))) {
            return deployment.user != address(0);
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("Challenge"))) {
            return deployment.challenge != address(0);
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("PeerRating"))) {
            return deployment.peerRating != address(0);
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("ReputationEngine"))) {
            return deployment.reputationEngine != address(0);
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("Poll"))) {
            return deployment.poll != address(0);
        }

        return false;
    }

    /**
     * @notice Get deployed contract address
     */
    function getContractAddress(string memory contractName) internal view returns (address) {
        Deployment memory deployment = loadDeployment();

        if (keccak256(bytes(contractName)) == keccak256(bytes("TopicRegistry"))) {
            return deployment.topicRegistry;
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("User"))) {
            return deployment.user;
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("Challenge"))) {
            return deployment.challenge;
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("PeerRating"))) {
            return deployment.peerRating;
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("ReputationEngine"))) {
            return deployment.reputationEngine;
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("Poll"))) {
            return deployment.poll;
        }

        revert(string(abi.encodePacked("Unknown contract: ", contractName)));
    }

    /**
     * @notice Print current deployment status
     */
    function printDeploymentStatus() internal view {
        Deployment memory deployment = loadDeployment();

        console.log("\n=== Deployment Status for", getNetworkName(), "===");
        console.log("TopicRegistry:", deployment.topicRegistry);
        console.log("User:", deployment.user);
        console.log("Challenge:", deployment.challenge);
        console.log("PeerRating:", deployment.peerRating);
        console.log("ReputationEngine:", deployment.reputationEngine);
        console.log("Poll:", deployment.poll);
        console.log("=====================================\n");
    }
}
