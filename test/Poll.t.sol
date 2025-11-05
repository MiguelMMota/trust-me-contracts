// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/TopicRegistry.sol";
import "../src/User.sol";
import "../src/ReputationEngine.sol";
import "../src/Poll.sol";

contract PollTest is Test {
    TopicRegistry public topicRegistry;
    User public userContract;
    ReputationEngine public reputationEngine;
    Poll public pollContract;

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

        // Deploy ReputationEngine with proxy (Challenge not needed for basic poll tests)
        ReputationEngine repImpl = new ReputationEngine();
        bytes memory repInitData = abi.encodeWithSelector(
            ReputationEngine.initialize.selector, admin, address(userContract), address(0), address(topicRegistry)
        );
        ERC1967Proxy repProxy = new ERC1967Proxy(address(repImpl), repInitData);
        reputationEngine = ReputationEngine(address(repProxy));

        // Deploy Poll with proxy
        Poll pollImpl = new Poll();
        bytes memory pollInitData = abi.encodeWithSelector(
            Poll.initialize.selector, admin, address(userContract), address(reputationEngine), address(topicRegistry)
        );
        ERC1967Proxy pollProxy = new ERC1967Proxy(address(pollImpl), pollInitData);
        pollContract = Poll(address(pollProxy));

        userContract.setReputationEngine(address(reputationEngine));

        // Create initial topic
        mathTopicId = topicRegistry.createTopic("Mathematics", 0);

        vm.stopPrank();
    }

    function testPollCreation() public {
        // Setup
        vm.prank(alice);
        userContract.registerUser();

        // Create poll
        vm.prank(alice);
        string[] memory options = new string[](3);
        options[0] = "Option A";
        options[1] = "Option B";
        options[2] = "Option C";

        uint64 pollId = pollContract.createPoll(
            mathTopicId,
            "Which method is best?",
            options,
            7 // 7 days
        );

        assertEq(pollId, 1);

        Poll.PollData memory poll = pollContract.getPoll(pollId);
        assertEq(poll.creator, alice);
        assertEq(poll.topicId, mathTopicId);
        assertEq(poll.optionCount, 3);
        assertTrue(poll.status == Poll.PollStatus.Active);
    }

    function testCannotVoteTwice() public {
        vm.prank(alice);
        userContract.registerUser();

        vm.prank(alice);
        string[] memory options = new string[](2);
        options[0] = "A";
        options[1] = "B";
        uint64 pollId = pollContract.createPoll(mathTopicId, "Test", options, 1);

        vm.prank(alice);
        pollContract.vote(pollId, 0);

        // Try to vote again - should fail
        vm.prank(alice);
        vm.expectRevert(Poll.AlreadyVoted.selector);
        pollContract.vote(pollId, 1);
    }

    function testPollClosing() public {
        vm.prank(alice);
        userContract.registerUser();

        vm.prank(alice);
        string[] memory options = new string[](2);
        options[0] = "A";
        options[1] = "B";
        uint64 pollId = pollContract.createPoll(mathTopicId, "Test", options, 1);

        // Warp to after end time
        vm.warp(block.timestamp + 2 days);

        // Anyone can close after end time
        vm.prank(bob);
        pollContract.closePoll(pollId);

        Poll.PollData memory poll = pollContract.getPoll(pollId);
        assertTrue(poll.status == Poll.PollStatus.Closed);
    }
}
