// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TopicRegistry} from "../src/TopicRegistry.sol";
import {User} from "../src/User.sol";
import {Challenge} from "../src/Challenge.sol";
import {ReputationEngine} from "../src/ReputationEngine.sol";

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

        // Set reputation engine in User and Challenge contracts
        userContract.setReputationEngine(address(reputationEngine));
        challengeContract.setReputationEngine(address(reputationEngine));

        // Create initial topic
        mathTopicId = topicRegistry.createTopic("Mathematics", 0);

        vm.stopPrank();
    }

    function testReputationScoreCalculation() public {
        vm.prank(alice);
        userContract.registerUser("Alice");

        // Simulate expertise data
        uint16 score = reputationEngine.calculateExpertiseScore(alice, mathTopicId);
        assertEq(score, User(userContract).INITIAL_SCORE()); // No challenges yet

        // Test preview functionality
        uint16 projectedScore = reputationEngine.previewScoreChange(alice, mathTopicId, true);
        assertTrue(projectedScore > User(userContract).INITIAL_SCORE());
    }

    function testTimeDecay() public {
        vm.prank(alice);
        userContract.registerUser("Alice");

        // Create and answer a challenge
        bytes32 answerHash = keccak256(abi.encodePacked("answer"));
        vm.prank(admin);
        userContract.registerUser("Admin");
        vm.prank(admin);
        uint64 challengeId = challengeContract.createChallenge(
            mathTopicId, Challenge.DifficultyLevel.Easy, keccak256("Question"), answerHash
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
