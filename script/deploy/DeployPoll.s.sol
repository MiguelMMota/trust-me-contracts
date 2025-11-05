// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Poll} from "../../src/Poll.sol";
import {DeploymentConfig} from "../config/DeploymentConfig.sol";

/**
 * @title DeployPoll
 * @notice Deploys Poll with UUPS proxy pattern
 * @dev Requires User, ReputationEngine, and TopicRegistry to be deployed first
 */
contract DeployPoll is Script, DeploymentConfig {
    function run() external returns (address proxy) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = getDeployer();

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

        startBroadcast();

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
}
