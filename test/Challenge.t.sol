// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/TopicRegistry.sol";
import "../src/User.sol";
import "../src/Challenge.sol";

contract ChallengeTest is Test {
    TopicRegistry public topicRegistry;
    User public userContract;
    Challenge public challengeContract;

    address public admin = address(1);
    address public alice = address(2);
    address public bob = address(3);

    // Topic IDs
    uint32 public mathTopicId;

    function setUp() public {
        vm.startPrank(admin);

        topicRegistry = new TopicRegistry();
        userContract = new User(address(topicRegistry));
        challengeContract = new Challenge(address(topicRegistry), address(userContract));

        // Create initial topic
        mathTopicId = topicRegistry.createTopic("Mathematics", 0);

        vm.stopPrank();
    }

    function testChallengeCreation() public {
        // Register users
        vm.prank(alice);
        userContract.registerUser();

        // Create challenge
        vm.prank(alice);
        bytes32 questionHash = keccak256("What is 2+2?");
        bytes32 answerHash = keccak256(abi.encodePacked("4"));

        uint64 challengeId = challengeContract.createChallenge(
            mathTopicId,
            Challenge.DifficultyLevel.Easy,
            questionHash,
            answerHash
        );

        assertEq(challengeId, 1);

        Challenge.ChallengeData memory challenge = challengeContract.getChallenge(challengeId);
        assertEq(challenge.creator, alice);
        assertEq(challenge.topicId, mathTopicId);
        assertTrue(challenge.status == Challenge.ChallengeStatus.Active);
    }

    function testChallengeAttemptCorrect() public {
        // Setup: Register users and create challenge
        vm.prank(alice);
        userContract.registerUser();

        vm.prank(bob);
        userContract.registerUser();

        vm.prank(alice);
        bytes32 answerHash = keccak256(abi.encodePacked("4"));
        uint64 challengeId = challengeContract.createChallenge(
            mathTopicId,
            Challenge.DifficultyLevel.Easy,
            keccak256("What is 2+2?"),
            answerHash
        );

        // Bob attempts challenge with correct answer
        vm.prank(bob);
        challengeContract.attemptChallenge(challengeId, answerHash);

        // Verify attempt was recorded
        Challenge.ChallengeAttempt memory attempt = challengeContract.getUserAttempt(bob, challengeId);
        assertTrue(attempt.isCorrect);
        assertEq(attempt.user, bob);
    }

    function testChallengeAttemptIncorrect() public {
        // Setup
        vm.prank(alice);
        userContract.registerUser();

        vm.prank(bob);
        userContract.registerUser();

        vm.prank(alice);
        bytes32 correctAnswerHash = keccak256(abi.encodePacked("4"));
        uint64 challengeId = challengeContract.createChallenge(
            mathTopicId,
            Challenge.DifficultyLevel.Easy,
            keccak256("What is 2+2?"),
            correctAnswerHash
        );

        // Bob attempts with wrong answer
        vm.prank(bob);
        bytes32 wrongAnswerHash = keccak256(abi.encodePacked("5"));
        challengeContract.attemptChallenge(challengeId, wrongAnswerHash);

        Challenge.ChallengeAttempt memory attempt = challengeContract.getUserAttempt(bob, challengeId);
        assertFalse(attempt.isCorrect);
    }
}
