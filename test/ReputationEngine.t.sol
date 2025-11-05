// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/TopicRegistry.sol";
import "../src/User.sol";
import "../src/Challenge.sol";
import "../src/ReputationEngine.sol";

contract ReputationEngineTest is Test {
    TopicRegistry public topicRegistry;
    User public userContract;
    Challenge public challengeContract;
    ReputationEngine public reputationEngine;

    address public admin = address(1);
    address public alice = address(2);

    // Topic IDs
    uint32 public mathTopicId;

    function setUp() public {
        vm.startPrank(admin);

        topicRegistry = new TopicRegistry();
        userContract = new User(address(topicRegistry));
        challengeContract = new Challenge(address(topicRegistry), address(userContract));
        reputationEngine = new ReputationEngine(
            address(userContract),
            address(challengeContract),
            address(topicRegistry)
        );

        // Set reputation engine in User and Challenge contracts
        userContract.setReputationEngine(address(reputationEngine));
        challengeContract.setReputationEngine(address(reputationEngine));

        // Create initial topic
        mathTopicId = topicRegistry.createTopic("Mathematics", 0);

        vm.stopPrank();
    }

    function testReputationScoreCalculation() public {
        vm.prank(alice);
        userContract.registerUser();

        // Simulate expertise data
        uint16 score = reputationEngine.calculateExpertiseScore(alice, mathTopicId);
        assertEq(score, User(userContract).INITIAL_SCORE()); // No challenges yet

        // Test preview functionality
        uint16 projectedScore = reputationEngine.previewScoreChange(alice, mathTopicId, true);
        assertTrue(projectedScore > User(userContract).INITIAL_SCORE());
    }

    function testTimeDecay() public {
        vm.prank(alice);
        userContract.registerUser();

        // Create and answer a challenge
        bytes32 answerHash = keccak256(abi.encodePacked("answer"));
        vm.prank(admin);
        userContract.registerUser();
        vm.prank(admin);
        uint64 challengeId = challengeContract.createChallenge(
            mathTopicId,
            Challenge.DifficultyLevel.Easy,
            keccak256("Question"),
            answerHash
        );

        vm.prank(alice);
        challengeContract.attemptChallenge(challengeId, answerHash);
        reputationEngine.processChallengeAttempt(alice, challengeId);

        uint16 initialScore = userContract.getUserScore(alice, mathTopicId);

        // Simulate 31 days passing
        vm.warp(block.timestamp + 31 days);

        // Recalculate score - should have time decay applied
        reputationEngine.recalculateScore(alice, mathTopicId);
        uint16 decayedScore = userContract.getUserScore(alice, mathTopicId);

        // Score should decrease due to time decay
        assertTrue(decayedScore < initialScore);
        console.log("Initial score:", initialScore);
        console.log("Score after 31 days:", decayedScore);
    }
}
