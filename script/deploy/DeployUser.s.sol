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

    function fillData(address proxy) public {
        console.log("\n=== Creating Test Users ===");

        startBroadcast();

        User userContract = User(proxy);

        // Register 4 test users
        address[4] memory testUsers = [
            0xCDc986e956f889b6046F500657625E523f06D5F0,
            0x13dbAD22Ae32aaa90F7E9173C1fA519c064E4d65,
            0x28C02652dFc64202360E1A0B4f88FcedECB538a6,
            0xCACCbe50c1D788031d774dd886DA8F5Dc225ee06
        ];

        for (uint256 i = 0; i < testUsers.length; i++) {
            // Use vm.prank to register each user from their own address
            vm.stopBroadcast();
            vm.startPrank(testUsers[i]);
            userContract.registerUser();
            vm.stopPrank();
            console.log("User", i + 1, "registered:", testUsers[i]);
            startBroadcast();
        }

        vm.stopBroadcast();

        console.log("=== User Registration Complete ===");
        console.log("4 users have been registered");
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
