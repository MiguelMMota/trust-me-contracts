// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/TopicRegistry.sol";
import "../src/User.sol";
import "../src/Challenge.sol";
import "../src/ReputationEngine.sol";
import "../src/Poll.sol";

contract TrustMeSystemTest is Test {
    TopicRegistry public topicRegistry;
    User public userContract;
    Challenge public challengeContract;
    ReputationEngine public reputationEngine;
    Poll public pollContract;

    address public admin = address(1);
    address public alice = address(2);
    address public bob = address(3);
    address public charlie = address(4);

    // Topic IDs
    uint32 public mathTopicId;
    uint32 public softwareTopicId;
    uint32 public pythonTopicId;

    function setUp() public {
        vm.startPrank(admin);

        // Deploy contracts in correct order
        topicRegistry = new TopicRegistry();
        userContract = new User(address(topicRegistry));
        challengeContract = new Challenge(address(topicRegistry), address(userContract));
        reputationEngine = new ReputationEngine(
            address(userContract),
            address(challengeContract),
            address(topicRegistry)
        );
        pollContract = new Poll(
            address(userContract),
            address(reputationEngine),
            address(topicRegistry)
        );

        // Set reputation engine in User and Challenge contracts
        userContract.setReputationEngine(address(reputationEngine));
        challengeContract.setReputationEngine(address(reputationEngine));

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

    function testUserRegistration() public {
        vm.prank(alice);
        userContract.registerUser();

        assertTrue(userContract.isRegistered(alice));
        User.UserProfile memory profile = userContract.getUserProfile(alice);
        assertEq(profile.userAddress, alice);
        assertEq(profile.totalTopicsEngaged, 0);
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

        // Process the attempt through reputation engine
        reputationEngine.processChallengeAttempt(bob, challengeId);

        // Check expertise was updated
        User.UserTopicExpertise memory expertise = userContract.getUserExpertise(bob, mathTopicId);
        assertEq(expertise.totalChallenges, 1);
        assertEq(expertise.correctChallenges, 1);
        assertTrue(expertise.score > User(userContract).INITIAL_SCORE());
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

        // Process attempt
        reputationEngine.processChallengeAttempt(bob, challengeId);

        // Check expertise
        User.UserTopicExpertise memory expertise = userContract.getUserExpertise(bob, mathTopicId);
        assertEq(expertise.totalChallenges, 1);
        assertEq(expertise.correctChallenges, 0);
    }

    function testMultipleChallengesScoring() public {
        // Setup
        vm.prank(alice);
        userContract.registerUser();

        // Register admin once before loop
        vm.prank(admin);
        userContract.registerUser();

        // Create 5 challenges
        uint64[] memory challengeIds = new uint64[](5);
        bytes32[] memory answerHashes = new bytes32[](5);

        for (uint i = 0; i < 5; i++) {
            answerHashes[i] = keccak256(abi.encodePacked(i));

            vm.prank(admin);
            challengeIds[i] = challengeContract.createChallenge(
                mathTopicId,
                Challenge.DifficultyLevel.Medium,
                keccak256(abi.encodePacked("Question", i)),
                answerHashes[i]
            );
        }

        // Alice answers 4 correctly, 1 incorrectly
        for (uint i = 0; i < 5; i++) {
            vm.prank(alice);
            if (i == 2) {
                // Wrong answer for 3rd challenge
                challengeContract.attemptChallenge(challengeIds[i], keccak256(abi.encodePacked("wrong")));
            } else {
                challengeContract.attemptChallenge(challengeIds[i], answerHashes[i]);
            }
            reputationEngine.processChallengeAttempt(alice, challengeIds[i]);
        }

        // Check final stats
        User.UserTopicExpertise memory expertise = userContract.getUserExpertise(alice, mathTopicId);
        assertEq(expertise.totalChallenges, 5);
        assertEq(expertise.correctChallenges, 4);

        // 80% accuracy should give decent score
        uint16 score = userContract.getUserScore(alice, mathTopicId);
        assertTrue(score > 500); // Should be well above minimum
        console.log("Score with 80% accuracy (4/5 correct):", score);
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

    function testWeightedVoting() public {
        // Setup: Register users
        vm.prank(alice);
        userContract.registerUser();

        vm.prank(bob);
        userContract.registerUser();

        vm.prank(admin);
        userContract.registerUser();

        // Give Alice high expertise in math (answer 10 challenges correctly)
        for (uint i = 0; i < 10; i++) {
            bytes32 answerHash = keccak256(abi.encodePacked(i));
            vm.prank(admin);
            uint64 challengeId = challengeContract.createChallenge(
                mathTopicId,
                Challenge.DifficultyLevel.Medium,
                keccak256(abi.encodePacked("Q", i)),
                answerHash
            );

            vm.prank(alice);
            challengeContract.attemptChallenge(challengeId, answerHash);
            reputationEngine.processChallengeAttempt(alice, challengeId);
        }

        // Bob has minimal expertise (just registered)
        uint16 aliceScore = userContract.getUserScore(alice, mathTopicId);
        uint16 bobScore = userContract.getUserScore(bob, mathTopicId);

        console.log("Alice's expertise score:", aliceScore);
        console.log("Bob's expertise score:", bobScore);

        assertTrue(aliceScore > bobScore);

        // Create poll
        vm.prank(alice);
        string[] memory options = new string[](2);
        options[0] = "Option A";
        options[1] = "Option B";

        uint64 pollId = pollContract.createPoll(mathTopicId, "Test poll", options, 1);

        // Both vote for different options
        vm.prank(alice);
        pollContract.vote(pollId, 0); // Alice votes for Option A

        vm.prank(bob);
        pollContract.vote(pollId, 1); // Bob votes for Option B

        // Check results - Alice's vote should have more weight
        Poll.PollResults memory results = pollContract.getPollResults(pollId);
        assertTrue(results.optionWeights[0] > results.optionWeights[1]);
        assertEq(results.winningOption, 0); // Alice's choice wins due to higher expertise
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

    function testAccuracyCalculation() public {
        vm.prank(alice);
        userContract.registerUser();

        vm.prank(admin);
        userContract.registerUser();

        // Answer 7 out of 10 correctly
        for (uint i = 0; i < 10; i++) {
            bytes32 answerHash = keccak256(abi.encodePacked(i));
            vm.prank(admin);
            uint64 challengeId = challengeContract.createChallenge(
                mathTopicId,
                Challenge.DifficultyLevel.Easy,
                keccak256(abi.encodePacked("Q", i)),
                answerHash
            );

            vm.prank(alice);
            if (i < 7) {
                challengeContract.attemptChallenge(challengeId, answerHash); // Correct
            } else {
                challengeContract.attemptChallenge(challengeId, keccak256(abi.encodePacked("wrong"))); // Wrong
            }
            reputationEngine.processChallengeAttempt(alice, challengeId);
        }

        uint16 accuracy = userContract.getAccuracy(alice, mathTopicId);
        assertEq(accuracy, 7000); // 70% in basis points
    }
}
