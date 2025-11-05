// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {User} from "../../src/User.sol";
import {DeploymentConfig} from "../config/DeploymentConfig.sol";

/**
 * @title DeployUser
 * @notice Deploys User with UUPS proxy pattern
 * @dev Requires TopicRegistry to be deployed first
 */
contract DeployUser is Script, DeploymentConfig {
    function run() external returns (address proxy) {
        address deployer = getDeployer();

        console.log("\n=== Deploying User ===");
        console.log("Deployer:", deployer);
        console.log("Network:", getNetworkName());

        // Check if TopicRegistry is deployed
        if (!isDeployed("TopicRegistry")) {
            revert("TopicRegistry must be deployed first");
        }
        address topicRegistry = getContractAddress("TopicRegistry");
        console.log("Using TopicRegistry at:", topicRegistry);

        startBroadcast();

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

        return proxy;
    }
}
