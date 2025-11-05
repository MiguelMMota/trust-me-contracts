// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/TopicRegistry.sol";

contract TopicRegistryTest is Test {
    TopicRegistry public topicRegistry;

    address public admin = address(1);

    // Topic IDs
    uint32 public mathTopicId;
    uint32 public softwareTopicId;
    uint32 public pythonTopicId;

    function setUp() public {
        vm.startPrank(admin);

        // Deploy implementation
        TopicRegistry implementation = new TopicRegistry();

        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(TopicRegistry.initialize.selector, admin);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        topicRegistry = TopicRegistry(address(proxy));

        // Create initial topics
        mathTopicId = topicRegistry.createTopic("Mathematics", 0);
        softwareTopicId = topicRegistry.createTopic("Software Engineering", 0);
        pythonTopicId = topicRegistry.createTopic("Python", softwareTopicId);

        vm.stopPrank();
    }

    function testTopicCreation() public {
        vm.startPrank(admin);

        uint32 historyId = topicRegistry.createTopic("History", 0);
        assertEq(historyId, 4);

        TopicRegistry.Topic memory topic = topicRegistry.getTopic(historyId);
        assertEq(topic.name, "History");
        assertEq(topic.parentId, 0);
        assertTrue(topic.isActive);

        vm.stopPrank();
    }

    function testTopicHierarchy() public view {
        assertTrue(topicRegistry.isDescendant(pythonTopicId, softwareTopicId));
        assertFalse(topicRegistry.isDescendant(mathTopicId, softwareTopicId));
    }
}
