// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TeamRegistry} from "../src/TeamRegistry.sol";
import {TopicRegistry} from "../src/TopicRegistry.sol";
import {User} from "../src/User.sol";
import {Challenge} from "../src/Challenge.sol";
import {ReputationEngine} from "../src/ReputationEngine.sol";

contract TeamIntegrationTest is Test {
    TeamRegistry public teamRegistry;
    TopicRegistry public topicRegistry;
    User public userContract;
    Challenge public challengeContract;
    ReputationEngine public reputationEngine;

    address public admin = address(1);
    address public alice = address(2);
    address public bob = address(3);
    address public charlie = address(4);

    uint64 public teamId;
    uint32 public globalTopicId;
    uint32 public teamTopicId;

    function setUp() public {
        vm.startPrank(admin);

        // Deploy TeamRegistry
        TeamRegistry teamImpl = new TeamRegistry();
        bytes memory teamInitData = abi.encodeWithSelector(TeamRegistry.initialize.selector);
        ERC1967Proxy teamProxy = new ERC1967Proxy(address(teamImpl), teamInitData);
        teamRegistry = TeamRegistry(address(teamProxy));

        // Deploy TopicRegistry
        TopicRegistry topicImpl = new TopicRegistry();
        bytes memory topicInitData = abi.encodeWithSelector(TopicRegistry.initialize.selector, admin);
        ERC1967Proxy topicProxy = new ERC1967Proxy(address(topicImpl), topicInitData);
        topicRegistry = TopicRegistry(address(topicProxy));

        // Set TeamRegistry in TopicRegistry
        topicRegistry.setTeamRegistry(address(teamRegistry));

        // Deploy User
        User userImpl = new User();
        bytes memory userInitData = abi.encodeWithSelector(User.initialize.selector, admin, address(topicRegistry));
        ERC1967Proxy userProxy = new ERC1967Proxy(address(userImpl), userInitData);
        userContract = User(address(userProxy));

        // Set TeamRegistry in User
        userContract.setTeamRegistry(address(teamRegistry));

        // Deploy Challenge
        Challenge challengeImpl = new Challenge();
        bytes memory challengeInitData = abi.encodeWithSelector(
            Challenge.initialize.selector, admin, address(topicRegistry), address(teamRegistry), address(userContract)
        );
        ERC1967Proxy challengeProxy = new ERC1967Proxy(address(challengeImpl), challengeInitData);
        challengeContract = Challenge(address(challengeProxy));

        // Deploy ReputationEngine
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

        // Wire up contracts
        userContract.setReputationEngine(address(reputationEngine));
        userContract.setChallengeContract(address(challengeContract));
        challengeContract.setReputationEngine(address(reputationEngine));

        // Create global topic
        globalTopicId = topicRegistry.createTopic("Software Engineering", 0);

        vm.stopPrank();

        // Create a team
        vm.prank(alice);
        teamId = teamRegistry.createTeam("Engineering Team");

        // Add Bob as admin and Charlie as member
        vm.prank(alice);
        teamRegistry.addMember(teamId, bob, TeamRegistry.TeamRole.Admin);

        vm.prank(alice);
        teamRegistry.addMember(teamId, charlie, TeamRegistry.TeamRole.Member);
    }

    /*///////////////////////////
      TOPIC REGISTRY TESTS
    ///////////////////////////*/

    function testCreateTeamTopic() public {
        vm.prank(alice);
        teamTopicId = topicRegistry.createTeamTopic(teamId, "Foundry", globalTopicId);

        TopicRegistry.Topic memory topic = topicRegistry.getTeamTopic(teamId, teamTopicId);
        assertEq(topic.name, "Foundry");
        assertEq(topic.parentId, globalTopicId);
        assertTrue(topic.isActive);
    }

    function testAdminCanCreateTeamTopic() public {
        vm.prank(bob); // Bob is admin
        teamTopicId = topicRegistry.createTeamTopic(teamId, "Solidity", globalTopicId);

        TopicRegistry.Topic memory topic = topicRegistry.getTeamTopic(teamId, teamTopicId);
        assertEq(topic.name, "Solidity");
    }

    function testMemberCannotCreateTeamTopic() public {
        vm.prank(charlie); // Charlie is just a member
        vm.expectRevert(TopicRegistry.NotTeamAdmin.selector);
        topicRegistry.createTeamTopic(teamId, "Rust", globalTopicId);
    }

    function testDisableGlobalTopicForTeam() public {
        vm.prank(alice);
        topicRegistry.setTopicEnabledInTeam(teamId, globalTopicId, false);

        assertFalse(topicRegistry.isTopicEnabledInTeam(teamId, globalTopicId));
    }

    function testEnableGlobalTopicForTeam() public {
        vm.prank(alice);
        topicRegistry.setTopicEnabledInTeam(teamId, globalTopicId, false);

        vm.prank(alice);
        topicRegistry.setTopicEnabledInTeam(teamId, globalTopicId, true);

        assertTrue(topicRegistry.isTopicEnabledInTeam(teamId, globalTopicId));
    }

    function testDisableTopicCascadesToChildren() public {
        // Create parent topic
        vm.prank(admin);
        uint32 parentTopic = topicRegistry.createTopic("Backend", 0);

        // Create child topic
        vm.prank(admin);
        uint32 childTopic = topicRegistry.createTopic("Python", parentTopic);

        // Disable parent for team
        vm.prank(alice);
        topicRegistry.setTopicEnabledInTeam(teamId, parentTopic, false);

        // Child should also be disabled
        assertFalse(topicRegistry.isTopicEnabledInTeam(teamId, parentTopic));
        assertFalse(topicRegistry.isTopicEnabledInTeam(teamId, childTopic));
    }

    function testGetTeamChildTopics() public {
        vm.prank(alice);
        uint32 teamTopic1 = topicRegistry.createTeamTopic(teamId, "Topic 1", globalTopicId);

        vm.prank(alice);
        uint32 teamTopic2 = topicRegistry.createTeamTopic(teamId, "Topic 2", globalTopicId);

        uint32[] memory children = topicRegistry.getTeamChildTopics(teamId, globalTopicId);
        assertEq(children.length, 2);
    }

    /*///////////////////////////
      USER CONTRACT TESTS
    ///////////////////////////*/

    function testRegisterUserInTeam() public {
        vm.prank(alice);
        userContract.registerUserInTeam(teamId, "Alice in Team");

        assertTrue(userContract.isRegisteredInTeam(teamId, alice));

        User.UserProfile memory profile = userContract.getTeamUserProfile(teamId, alice);
        assertEq(profile.name, "Alice in Team");
        assertEq(profile.userAddress, alice);
    }

    function testOnlyTeamMembersCanRegister() public {
        address outsider = address(99);

        vm.prank(outsider);
        vm.expectRevert(User.NotTeamMember.selector);
        userContract.registerUserInTeam(teamId, "Outsider");
    }

    function testTeamReputationIsolatedFromGlobal() public {
        // Register Alice globally
        vm.prank(alice);
        userContract.registerUser("Alice Global");

        // Register Alice in team
        vm.prank(alice);
        userContract.registerUserInTeam(teamId, "Alice Team");

        // Verify separate profiles
        User.UserProfile memory globalProfile = userContract.getUserProfile(alice);
        User.UserProfile memory teamProfile = userContract.getTeamUserProfile(teamId, alice);

        assertEq(globalProfile.name, "Alice Global");
        assertEq(teamProfile.name, "Alice Team");
    }

    function testTeamUserScoresIsolated() public {
        // Register users
        vm.prank(alice);
        userContract.registerUser("Alice");

        vm.prank(alice);
        userContract.registerUserInTeam(teamId, "Alice Team");

        // Simulate expertise in team context using reputation engine
        vm.prank(address(reputationEngine));
        userContract.recordTeamChallengeAttempt(teamId, alice, globalTopicId, true);

        // Team expertise should be recorded
        User.UserTopicExpertise memory teamExpertise = userContract.getTeamUserExpertise(teamId, alice, globalTopicId);
        assertEq(teamExpertise.totalChallenges, 1);
        assertEq(teamExpertise.correctChallenges, 1);

        // Global expertise should be zero
        User.UserTopicExpertise memory globalExpertise = userContract.getUserExpertise(alice, globalTopicId);
        assertEq(globalExpertise.totalChallenges, 0);
    }

    function testGetTeamUserTopics() public {
        vm.prank(alice);
        userContract.registerUserInTeam(teamId, "Alice");

        vm.prank(admin);
        uint32 topic1 = topicRegistry.createTopic("Topic 1", 0);

        vm.prank(admin);
        uint32 topic2 = topicRegistry.createTopic("Topic 2", 0);

        // Record attempts in multiple topics
        vm.prank(address(reputationEngine));
        userContract.recordTeamChallengeAttempt(teamId, alice, topic1, true);

        vm.prank(address(reputationEngine));
        userContract.recordTeamChallengeAttempt(teamId, alice, topic2, false);

        uint32[] memory topics = userContract.getTeamUserTopics(teamId, alice);
        assertEq(topics.length, 2);
    }

    function testUpdateTeamExpertiseScore() public {
        vm.prank(alice);
        userContract.registerUserInTeam(teamId, "Alice");

        vm.prank(address(reputationEngine));
        userContract.updateTeamExpertiseScore(teamId, alice, globalTopicId, 750);

        uint16 score = userContract.getTeamUserScore(teamId, alice, globalTopicId);
        assertEq(score, 750);
    }

    function testTeamAccuracyCalculation() public {
        vm.prank(alice);
        userContract.registerUserInTeam(teamId, "Alice");

        // Record 7 correct out of 10
        for (uint256 i = 0; i < 10; i++) {
            bool correct = i < 7;
            vm.prank(address(reputationEngine));
            userContract.recordTeamChallengeAttempt(teamId, alice, globalTopicId, correct);
        }

        uint16 accuracy = userContract.getTeamAccuracy(teamId, alice, globalTopicId);
        assertEq(accuracy, 7000); // 70% in basis points
    }

    /*///////////////////////////
      REPUTATION ENGINE TESTS
    ///////////////////////////*/

    function testCalculateTeamExpertiseScore() public {
        vm.prank(alice);
        userContract.registerUserInTeam(teamId, "Alice");

        // Record some challenges
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(address(reputationEngine));
            userContract.recordTeamChallengeAttempt(teamId, alice, globalTopicId, true);
        }

        uint16 score = reputationEngine.calculateTeamExpertiseScore(teamId, alice, globalTopicId);
        assertTrue(score > 50); // Should be higher than MIN_SCORE
    }

    function testTeamScoreCalculationIsolated() public {
        vm.prank(alice);
        userContract.registerUser("Alice");

        vm.prank(alice);
        userContract.registerUserInTeam(teamId, "Alice Team");

        // Record global challenges
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(address(challengeContract));
            userContract.recordChallengeAttempt(alice, globalTopicId, true);
        }

        // Record team challenges
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(address(reputationEngine));
            userContract.recordTeamChallengeAttempt(teamId, alice, globalTopicId, true);
        }

        uint16 globalScore = reputationEngine.calculateExpertiseScore(alice, globalTopicId);
        uint16 teamScore = reputationEngine.calculateTeamExpertiseScore(teamId, alice, globalTopicId);

        // Scores should be different since they have different numbers of challenges
        assertTrue(globalScore != teamScore);
    }

    function testCalculateTeamChallengeScore() public {
        vm.prank(alice);
        userContract.registerUserInTeam(teamId, "Alice");

        // Record 8 correct out of 10
        for (uint256 i = 0; i < 10; i++) {
            bool correct = i < 8;
            vm.prank(address(reputationEngine));
            userContract.recordTeamChallengeAttempt(teamId, alice, globalTopicId, correct);
        }

        uint16 challengeScore = reputationEngine.calculateTeamChallengeScore(teamId, alice, globalTopicId);
        assertTrue(challengeScore > 50);
        assertTrue(challengeScore <= 1000);
    }

    function testRecalculateTeamScore() public {
        vm.prank(alice);
        userContract.registerUserInTeam(teamId, "Alice");

        vm.prank(address(reputationEngine));
        userContract.recordTeamChallengeAttempt(teamId, alice, globalTopicId, true);

        uint16 initialScore = userContract.getTeamUserScore(teamId, alice, globalTopicId);

        vm.prank(address(reputationEngine));
        userContract.recordTeamChallengeAttempt(teamId, alice, globalTopicId, true);

        reputationEngine.recalculateTeamScore(teamId, alice, globalTopicId);

        uint16 newScore = userContract.getTeamUserScore(teamId, alice, globalTopicId);
        assertTrue(newScore >= initialScore); // Score should increase or stay same with correct answers
    }

    function testBatchRecalculateTeamScores() public {
        vm.prank(alice);
        userContract.registerUserInTeam(teamId, "Alice");

        vm.prank(admin);
        uint32 topic2 = topicRegistry.createTopic("Topic 2", 0);

        vm.prank(admin);
        uint32 topic3 = topicRegistry.createTopic("Topic 3", 0);

        // Record challenges in multiple topics
        vm.prank(address(reputationEngine));
        userContract.recordTeamChallengeAttempt(teamId, alice, globalTopicId, true);

        vm.prank(address(reputationEngine));
        userContract.recordTeamChallengeAttempt(teamId, alice, topic2, true);

        vm.prank(address(reputationEngine));
        userContract.recordTeamChallengeAttempt(teamId, alice, topic3, false);

        uint32[] memory topics = new uint32[](3);
        topics[0] = globalTopicId;
        topics[1] = topic2;
        topics[2] = topic3;

        reputationEngine.batchRecalculateTeamScores(teamId, alice, topics);

        // Verify scores were calculated
        assertTrue(userContract.getTeamUserScore(teamId, alice, globalTopicId) > 0);
        assertTrue(userContract.getTeamUserScore(teamId, alice, topic2) > 0);
        assertTrue(userContract.getTeamUserScore(teamId, alice, topic3) > 0);
    }

    function testGetTeamVotingWeight() public {
        vm.prank(alice);
        userContract.registerUserInTeam(teamId, "Alice");

        vm.prank(address(reputationEngine));
        userContract.updateTeamExpertiseScore(teamId, alice, globalTopicId, 750);

        uint256 weight = reputationEngine.getTeamVotingWeight(teamId, alice, globalTopicId);
        assertEq(weight, 750);
    }

    function testTeamScoreWithTimeDecay() public {
        vm.prank(alice);
        userContract.registerUserInTeam(teamId, "Alice");

        vm.prank(address(reputationEngine));
        userContract.recordTeamChallengeAttempt(teamId, alice, globalTopicId, true);

        uint16 initialScore = reputationEngine.calculateTeamExpertiseScore(teamId, alice, globalTopicId);

        // Simulate 35 days passing (mid-term decay)
        vm.warp(block.timestamp + 35 days);

        uint16 decayedScore = reputationEngine.calculateTeamExpertiseScore(teamId, alice, globalTopicId);

        // Score should be lower due to time decay
        assertTrue(decayedScore < initialScore);
    }

    /*///////////////////////////
      INTEGRATION TESTS
    ///////////////////////////*/

    function testCompleteTeamWorkflow() public {
        // 1. Register team members
        vm.prank(alice);
        userContract.registerUserInTeam(teamId, "Alice");

        vm.prank(bob);
        userContract.registerUserInTeam(teamId, "Bob");

        // 2. Create team-specific topic
        vm.prank(alice);
        teamTopicId = topicRegistry.createTeamTopic(teamId, "Smart Contracts", globalTopicId);

        // 3. Disable a global topic for the team
        vm.prank(admin);
        uint32 irrelevantTopic = topicRegistry.createTopic("Irrelevant Topic", 0);

        vm.prank(alice);
        topicRegistry.setTopicEnabledInTeam(teamId, irrelevantTopic, false);

        // 4. Record team activities
        vm.prank(address(reputationEngine));
        userContract.recordTeamChallengeAttempt(teamId, alice, teamTopicId, true);

        vm.prank(address(reputationEngine));
        userContract.recordTeamChallengeAttempt(teamId, bob, teamTopicId, true);

        // 5. Calculate team scores
        uint16 aliceScore = reputationEngine.calculateTeamExpertiseScore(teamId, alice, teamTopicId);
        uint16 bobScore = reputationEngine.calculateTeamExpertiseScore(teamId, bob, teamTopicId);

        // 6. Verify isolation - global reputation should be unaffected
        assertFalse(userContract.isRegistered(alice)); // Not registered globally
        assertFalse(userContract.isRegistered(bob));

        // 7. Verify team reputation
        assertTrue(aliceScore > 50);
        assertTrue(bobScore > 50);

        // 8. Verify topic access
        assertTrue(topicRegistry.isTopicEnabledInTeam(teamId, teamTopicId));
        assertFalse(topicRegistry.isTopicEnabledInTeam(teamId, irrelevantTopic));
    }

    function testCannotUseTeamId0() public {
        vm.prank(alice);
        vm.expectRevert(User.InvalidTeamId.selector);
        userContract.registerUserInTeam(0, "Alice");

        vm.prank(address(reputationEngine));
        vm.expectRevert(User.InvalidTeamId.selector);
        userContract.updateTeamExpertiseScore(0, alice, globalTopicId, 500);

        vm.expectRevert(ReputationEngine.InvalidTeamId.selector);
        reputationEngine.calculateTeamExpertiseScore(0, alice, globalTopicId);
    }
}
