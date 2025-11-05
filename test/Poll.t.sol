// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
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

        topicRegistry = new TopicRegistry();
        userContract = new User(address(topicRegistry));

        // Note: ReputationEngine needs Challenge contract, but for Poll unit tests
        // we can use a minimal setup or mock if needed
        // For now, we'll create a minimal setup
        reputationEngine = new ReputationEngine(
            address(userContract),
            address(0), // Challenge not needed for basic poll tests
            address(topicRegistry)
        );

        pollContract = new Poll(
            address(userContract),
            address(reputationEngine),
            address(topicRegistry)
        );

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
