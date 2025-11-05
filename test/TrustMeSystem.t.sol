// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
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

        // Deploy Challenge with proxy
        Challenge challengeImpl = new Challenge();
        bytes memory challengeInitData =
            abi.encodeWithSelector(Challenge.initialize.selector, admin, address(topicRegistry), address(userContract));
        ERC1967Proxy challengeProxy = new ERC1967Proxy(address(challengeImpl), challengeInitData);
        challengeContract = Challenge(address(challengeProxy));

        // Deploy ReputationEngine with proxy
        ReputationEngine repImpl = new ReputationEngine();
        bytes memory repInitData = abi.encodeWithSelector(
            ReputationEngine.initialize.selector,
            admin,
            address(userContract),
            address(challengeContract),
            address(topicRegistry)
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

        // Set reputation engine in User and Challenge contracts
        userContract.setReputationEngine(address(reputationEngine));
        challengeContract.setReputationEngine(address(reputationEngine));

        // Create initial topics
        mathTopicId = topicRegistry.createTopic("Mathematics", 0);
        softwareTopicId = topicRegistry.createTopic("Software Engineering", 0);
        pythonTopicId = topicRegistry.createTopic("Python", softwareTopicId);

        vm.stopPrank();
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

        for (uint256 i = 0; i < 5; i++) {
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
        for (uint256 i = 0; i < 5; i++) {
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

    function testWeightedVoting() public {
        // Setup: Register users
        vm.prank(alice);
        userContract.registerUser();

        vm.prank(bob);
        userContract.registerUser();

        vm.prank(admin);
        userContract.registerUser();

        // Give Alice high expertise in math (answer 10 challenges correctly)
        for (uint256 i = 0; i < 10; i++) {
            bytes32 answerHash = keccak256(abi.encodePacked(i));
            vm.prank(admin);
            uint64 challengeId = challengeContract.createChallenge(
                mathTopicId, Challenge.DifficultyLevel.Medium, keccak256(abi.encodePacked("Q", i)), answerHash
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

    function testAccuracyCalculation() public {
        vm.prank(alice);
        userContract.registerUser();

        vm.prank(admin);
        userContract.registerUser();

        // Answer 7 out of 10 correctly
        for (uint256 i = 0; i < 10; i++) {
            bytes32 answerHash = keccak256(abi.encodePacked(i));
            vm.prank(admin);
            uint64 challengeId = challengeContract.createChallenge(
                mathTopicId, Challenge.DifficultyLevel.Easy, keccak256(abi.encodePacked("Q", i)), answerHash
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
