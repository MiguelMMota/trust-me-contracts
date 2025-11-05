// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/TopicRegistry.sol";
import "../src/User.sol";

contract UserTest is Test {
    TopicRegistry public topicRegistry;
    User public userContract;

    address public admin = address(1);
    address public alice = address(2);
    address public bob = address(3);

    // Topic IDs
    uint32 public mathTopicId;

    function setUp() public {
        vm.startPrank(admin);

        // Deploy TopicRegistry with proxy
        TopicRegistry topicImpl = new TopicRegistry();
        bytes memory topicInitData = abi.encodeWithSelector(TopicRegistry.initialize.selector, admin);
        ERC1967Proxy topicProxy = new ERC1967Proxy(address(topicImpl), topicInitData);
        topicRegistry = TopicRegistry(address(topicProxy));

        // Deploy User with proxy
        User userImpl = new User();
        bytes memory userInitData = abi.encodeWithSelector(User.initialize.selector, admin, address(topicRegistry));
        ERC1967Proxy userProxy = new ERC1967Proxy(address(userImpl), userInitData);
        userContract = User(address(userProxy));

        // Create initial topic
        mathTopicId = topicRegistry.createTopic("Mathematics", 0);

        vm.stopPrank();
    }

    function testUserRegistration() public {
        vm.prank(alice);
        userContract.registerUser();

        assertTrue(userContract.isRegistered(alice));
        User.UserProfile memory profile = userContract.getUserProfile(alice);
        assertEq(profile.userAddress, alice);
        assertEq(profile.totalTopicsEngaged, 0);
    }

    function testAccuracyWithNoChallenges() public {
        vm.prank(alice);
        userContract.registerUser();

        // With no challenges, accuracy should be 0
        uint16 accuracy = userContract.getAccuracy(alice, mathTopicId);
        assertEq(accuracy, 0); // No challenges attempted yet
    }
}
