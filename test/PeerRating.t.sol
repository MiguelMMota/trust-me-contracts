// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TopicRegistry} from "../src/TopicRegistry.sol";
import {User} from "../src/User.sol";
import {PeerRating} from "../src/PeerRating.sol";

contract PeerRatingTest is Test {
    TopicRegistry public topicRegistry;
    User public userContract;
    PeerRating public peerRating;

    address public admin = address(1);
    address public alice = address(2);
    address public bob = address(3);
    address public charlie = address(4);
    address public dave = address(5);
    address public reputationEngine = address(6);
    address public unregisteredUser = address(7);

    // Topic IDs
    uint32 public mathTopicId;
    uint32 public scienceTopicId;
    uint32 public inactiveTopicId;

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

        // Deploy PeerRating with proxy
        PeerRating peerRatingImpl = new PeerRating();
        bytes memory peerRatingInitData =
            abi.encodeWithSelector(PeerRating.initialize.selector, admin, address(topicRegistry), address(userContract));
        ERC1967Proxy peerRatingProxy = new ERC1967Proxy(address(peerRatingImpl), peerRatingInitData);
        peerRating = PeerRating(address(peerRatingProxy));

        // Create topics
        mathTopicId = topicRegistry.createTopic("Mathematics", 0);
        scienceTopicId = topicRegistry.createTopic("Science", 0);
        inactiveTopicId = topicRegistry.createTopic("Inactive Topic", 0);
        topicRegistry.setTopicActive(inactiveTopicId, false);

        vm.stopPrank();

        // Register users
        vm.prank(alice);
        userContract.registerUser();

        vm.prank(bob);
        userContract.registerUser();

        vm.prank(charlie);
        userContract.registerUser();

        vm.prank(dave);
        userContract.registerUser();
    }

    /*///////////////////////////
      INITIALIZATION TESTS
    ///////////////////////////*/

    function testInitialization() public view {
        assertEq(address(peerRating.topicRegistry()), address(topicRegistry));
        assertEq(address(peerRating.userContract()), address(userContract));
        assertEq(peerRating.MIN_RATING(), 0);
        assertEq(peerRating.MAX_RATING(), 1000);
        assertEq(peerRating.RATING_COOLDOWN_PERIOD(), 182 days);
    }

    function testSetReputationEngine() public {
        vm.prank(admin);
        peerRating.setReputationEngine(reputationEngine);
        assertEq(peerRating.reputationEngine(), reputationEngine);
    }

    function testSetReputationEngineOnlyOnce() public {
        vm.startPrank(admin);
        peerRating.setReputationEngine(reputationEngine);

        vm.expectRevert(PeerRating.Unauthorized.selector);
        peerRating.setReputationEngine(address(999));
        vm.stopPrank();
    }

    function testSetReputationEngineOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        peerRating.setReputationEngine(reputationEngine);
    }

    /*///////////////////////////
        RATING TESTS
    ///////////////////////////*/

    function testRateUser() public {
        vm.prank(alice);
        peerRating.rateUser(bob, mathTopicId, 750);

        PeerRating.Rating memory rating = peerRating.getRating(bob, mathTopicId, alice);
        assertEq(rating.rater, alice);
        assertEq(rating.ratee, bob);
        assertEq(rating.topicId, mathTopicId);
        assertEq(rating.score, 750);
        assertTrue(rating.exists);
    }

    function testRateUserEmitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit PeerRating.RatingSubmitted(alice, bob, mathTopicId, 750, uint64(block.timestamp));
        peerRating.rateUser(bob, mathTopicId, 750);
    }

    function testRateUserUpdatesAggregateRating() public {
        vm.prank(alice);
        peerRating.rateUser(bob, mathTopicId, 800);

        PeerRating.UserTopicRatings memory ratings = peerRating.getUserTopicRating(bob, mathTopicId);
        assertEq(ratings.averageScore, 800);
        assertEq(ratings.totalRatings, 1);
    }

    function testMultipleRatersUpdateAverage() public {
        vm.prank(alice);
        peerRating.rateUser(bob, mathTopicId, 800);

        vm.prank(charlie);
        peerRating.rateUser(bob, mathTopicId, 600);

        PeerRating.UserTopicRatings memory ratings = peerRating.getUserTopicRating(bob, mathTopicId);
        assertEq(ratings.averageScore, 700); // (800 + 600) / 2
        assertEq(ratings.totalRatings, 2);
    }

    function testRateUserSelfRatingNotAllowed() public {
        vm.prank(alice);
        vm.expectRevert(PeerRating.SelfRatingNotAllowed.selector);
        peerRating.rateUser(alice, mathTopicId, 800);
    }

    function testRateUserUnregisteredRater() public {
        vm.prank(unregisteredUser);
        vm.expectRevert(PeerRating.UserNotRegistered.selector);
        peerRating.rateUser(bob, mathTopicId, 800);
    }

    function testRateUserUnregisteredRatee() public {
        vm.prank(alice);
        vm.expectRevert(PeerRating.UserNotRegistered.selector);
        peerRating.rateUser(unregisteredUser, mathTopicId, 800);
    }

    function testRateUserInvalidScore() public {
        vm.prank(alice);
        vm.expectRevert(PeerRating.InvalidRatingValue.selector);
        peerRating.rateUser(bob, mathTopicId, 1001);
    }

    function testRateUserInactiveTopic() public {
        vm.prank(alice);
        vm.expectRevert(PeerRating.InvalidTopicId.selector);
        peerRating.rateUser(bob, inactiveTopicId, 800);
    }

    function testRateUserMinScore() public {
        vm.prank(alice);
        peerRating.rateUser(bob, mathTopicId, 0);

        PeerRating.Rating memory rating = peerRating.getRating(bob, mathTopicId, alice);
        assertEq(rating.score, 0);
    }

    function testRateUserMaxScore() public {
        vm.prank(alice);
        peerRating.rateUser(bob, mathTopicId, 1000);

        PeerRating.Rating memory rating = peerRating.getRating(bob, mathTopicId, alice);
        assertEq(rating.score, 1000);
    }

    /*///////////////////////////
     RATING UPDATE TESTS
    ///////////////////////////*/

    function testUpdateRatingAfterCooldown() public {
        // First rating
        vm.prank(alice);
        peerRating.rateUser(bob, mathTopicId, 750);

        // Fast forward past cooldown period
        vm.warp(block.timestamp + 183 days);

        // Update rating
        vm.prank(alice);
        peerRating.rateUser(bob, mathTopicId, 900);

        PeerRating.Rating memory rating = peerRating.getRating(bob, mathTopicId, alice);
        assertEq(rating.score, 900);
    }

    function testUpdateRatingEmitsUpdateEvent() public {
        // First rating
        vm.prank(alice);
        peerRating.rateUser(bob, mathTopicId, 750);

        // Fast forward past cooldown period
        vm.warp(block.timestamp + 183 days);

        // Update rating - should emit RatingUpdated event
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit PeerRating.RatingUpdated(alice, bob, mathTopicId, 750, 900, uint64(block.timestamp));
        peerRating.rateUser(bob, mathTopicId, 900);
    }

    function testUpdateRatingBeforeCooldown() public {
        // First rating
        uint64 firstTimestamp = uint64(block.timestamp);
        vm.prank(alice);
        peerRating.rateUser(bob, mathTopicId, 750);

        // Try to update before cooldown (only 100 days, need 182)
        vm.warp(firstTimestamp + 100 days);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(PeerRating.RatedTooRecently.selector, alice, bob, mathTopicId, firstTimestamp)
        );
        peerRating.rateUser(bob, mathTopicId, 900);
    }

    function testMultipleRatingUpdates() public {
        uint64 t0 = uint64(block.timestamp);

        // First rating
        vm.prank(alice);
        peerRating.rateUser(bob, mathTopicId, 500);

        // Second rating after cooldown
        uint64 t1 = t0 + 183 days;
        vm.warp(t1);
        vm.prank(alice);
        peerRating.rateUser(bob, mathTopicId, 700);

        // Third rating after another cooldown
        uint64 t2 = t1 + 183 days;
        vm.warp(t2);
        vm.prank(alice);
        peerRating.rateUser(bob, mathTopicId, 900);

        PeerRating.Rating memory rating = peerRating.getRating(bob, mathTopicId, alice);
        assertEq(rating.score, 900);

        // Check we have 3 timestamps
        uint64[] memory timestamps = peerRating.getRatingTimestamps(bob, mathTopicId, alice);
        assertEq(timestamps.length, 3);
    }

    /*///////////////////////////
     AGGREGATE RATING TESTS
    ///////////////////////////*/

    function testAggregateRatingWithMultipleRaters() public {
        vm.prank(alice);
        peerRating.rateUser(bob, mathTopicId, 800);

        vm.prank(charlie);
        peerRating.rateUser(bob, mathTopicId, 600);

        vm.prank(dave);
        peerRating.rateUser(bob, mathTopicId, 1000);

        PeerRating.UserTopicRatings memory ratings = peerRating.getUserTopicRating(bob, mathTopicId);
        assertEq(ratings.averageScore, 800); // (800 + 600 + 1000) / 3
        assertEq(ratings.totalRatings, 3);
    }

    function testAggregateRatingAfterUpdate() public {
        // Alice rates Bob 500
        vm.prank(alice);
        peerRating.rateUser(bob, mathTopicId, 500);

        // Charlie rates Bob 600
        vm.prank(charlie);
        peerRating.rateUser(bob, mathTopicId, 600);

        // Average should be 550
        PeerRating.UserTopicRatings memory ratings1 = peerRating.getUserTopicRating(bob, mathTopicId);
        assertEq(ratings1.averageScore, 550);

        // Alice updates rating to 900 after cooldown
        vm.warp(block.timestamp + 183 days);
        vm.prank(alice);
        peerRating.rateUser(bob, mathTopicId, 900);

        // Average should now be 750 (900 + 600) / 2
        PeerRating.UserTopicRatings memory ratings2 = peerRating.getUserTopicRating(bob, mathTopicId);
        assertEq(ratings2.averageScore, 750);
        assertEq(ratings2.totalRatings, 2); // Still 2 raters
    }

    function testAggregateRatingEmitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit PeerRating.AggregateRatingUpdated(bob, mathTopicId, 750, 1);
        peerRating.rateUser(bob, mathTopicId, 750);
    }

    /*///////////////////////////
       VIEW FUNCTION TESTS
    ///////////////////////////*/

    function testGetRating() public {
        vm.prank(alice);
        peerRating.rateUser(bob, mathTopicId, 750);

        PeerRating.Rating memory rating = peerRating.getRating(bob, mathTopicId, alice);
        assertEq(rating.score, 750);
        assertTrue(rating.exists);
    }

    function testGetRatingNonExistent() public view {
        PeerRating.Rating memory rating = peerRating.getRating(bob, mathTopicId, alice);
        assertFalse(rating.exists);
        assertEq(rating.score, 0);
    }

    function testGetRatingAtTimestamp() public {
        uint64 firstTimestamp = uint64(block.timestamp);
        vm.prank(alice);
        peerRating.rateUser(bob, mathTopicId, 750);

        PeerRating.Rating memory rating = peerRating.getRatingAtTimestamp(bob, mathTopicId, alice, firstTimestamp);
        assertEq(rating.score, 750);
        assertTrue(rating.exists);
    }

    function testGetRatingAtTime() public {
        // First rating at time T
        vm.prank(alice);
        peerRating.rateUser(bob, mathTopicId, 500);

        uint64 timeAfterFirst = uint64(block.timestamp + 100 days);

        // Second rating at time T + 183 days
        vm.warp(block.timestamp + 183 days);
        vm.prank(alice);
        peerRating.rateUser(bob, mathTopicId, 900);

        // Query rating at time T + 100 days should return first rating
        PeerRating.Rating memory rating = peerRating.getRatingAtTime(bob, mathTopicId, alice, timeAfterFirst);
        assertEq(rating.score, 500);

        // Query rating at current time should return second rating
        PeerRating.Rating memory latestRating =
            peerRating.getRatingAtTime(bob, mathTopicId, alice, uint64(block.timestamp));
        assertEq(latestRating.score, 900);
    }

    function testGetRatingTimestamps() public {
        uint64 startTime = uint64(block.timestamp);
        vm.prank(alice);
        peerRating.rateUser(bob, mathTopicId, 500);

        uint64 secondTime = startTime + 183 days;
        vm.warp(secondTime);
        vm.prank(alice);
        peerRating.rateUser(bob, mathTopicId, 700);

        uint64[] memory timestamps = peerRating.getRatingTimestamps(bob, mathTopicId, alice);
        assertEq(timestamps.length, 2);
        assertEq(timestamps[0], startTime);
        assertEq(timestamps[1], secondTime);
    }

    function testGetUserTopicRating() public {
        vm.prank(alice);
        peerRating.rateUser(bob, mathTopicId, 800);

        PeerRating.UserTopicRatings memory ratings = peerRating.getUserTopicRating(bob, mathTopicId);
        assertEq(ratings.averageScore, 800);
        assertEq(ratings.totalRatings, 1);
        assertEq(ratings.lastRatingTime, uint64(block.timestamp));
    }

    function testGetUserTopicRatingAtTime() public {
        // Alice rates Bob 500 at timestamp 1
        vm.prank(alice);
        peerRating.rateUser(bob, mathTopicId, 500);

        // Set query time to be 50 days after first rating
        uint64 queryTime = uint64(block.timestamp + 50 days);

        // Warp forward 100 days (to timestamp 1 + 100 days = 8640001)
        vm.warp(block.timestamp + 100 days);

        // Charlie rates Bob 700 at timestamp (1 + 100 days = 8640001)
        vm.prank(charlie);
        peerRating.rateUser(bob, mathTopicId, 700);

        // Query at time after first rating but before second (at 1 + 50 days = 4320001)
        PeerRating.UserTopicRatings memory ratings = peerRating.getUserTopicRatingAtTime(bob, mathTopicId, queryTime);
        assertEq(ratings.averageScore, 500);
        assertEq(ratings.totalRatings, 1);
    }

    function testGetTopicRaters() public {
        vm.prank(alice);
        peerRating.rateUser(bob, mathTopicId, 800);

        vm.prank(charlie);
        peerRating.rateUser(bob, mathTopicId, 600);

        address[] memory raters = peerRating.getTopicRaters(bob, mathTopicId);
        assertEq(raters.length, 2);
        assertEq(raters[0], alice);
        assertEq(raters[1], charlie);
    }

    function testGetUserRatedTopics() public {
        vm.prank(alice);
        peerRating.rateUser(bob, mathTopicId, 800);

        vm.prank(alice);
        peerRating.rateUser(bob, scienceTopicId, 700);

        uint32[] memory topics = peerRating.getUserRatedTopics(bob);
        assertEq(topics.length, 2);
        assertEq(topics[0], mathTopicId);
        assertEq(topics[1], scienceTopicId);
    }

    function testGetAverageScore() public {
        vm.prank(alice);
        peerRating.rateUser(bob, mathTopicId, 800);

        vm.prank(charlie);
        peerRating.rateUser(bob, mathTopicId, 600);

        uint16 avgScore = peerRating.getAverageScore(bob, mathTopicId);
        assertEq(avgScore, 700);
    }

    function testGetRatingCount() public {
        vm.prank(alice);
        peerRating.rateUser(bob, mathTopicId, 800);

        vm.prank(charlie);
        peerRating.rateUser(bob, mathTopicId, 600);

        uint32 count = peerRating.getRatingCount(bob, mathTopicId);
        assertEq(count, 2);
    }

    function testRatingExists() public {
        assertFalse(peerRating.ratingExists(bob, mathTopicId, alice));

        vm.prank(alice);
        peerRating.rateUser(bob, mathTopicId, 800);

        assertTrue(peerRating.ratingExists(bob, mathTopicId, alice));
    }

    function testRatingExistsAtTimestamp() public {
        uint64 timestamp = uint64(block.timestamp);
        vm.prank(alice);
        peerRating.rateUser(bob, mathTopicId, 800);

        assertTrue(peerRating.ratingExistsAtTimestamp(bob, mathTopicId, alice, timestamp));
        assertFalse(peerRating.ratingExistsAtTimestamp(bob, mathTopicId, alice, timestamp + 1));
    }

    /*///////////////////////////
     COMPLEX SCENARIO TESTS
    ///////////////////////////*/

    function testMultipleUsersMultipleTopics() public {
        // Alice rates Bob on Math
        vm.prank(alice);
        peerRating.rateUser(bob, mathTopicId, 800);

        // Alice rates Bob on Science
        vm.prank(alice);
        peerRating.rateUser(bob, scienceTopicId, 700);

        // Charlie rates Bob on Math
        vm.prank(charlie);
        peerRating.rateUser(bob, mathTopicId, 600);

        // Check Math ratings
        PeerRating.UserTopicRatings memory mathRatings = peerRating.getUserTopicRating(bob, mathTopicId);
        assertEq(mathRatings.averageScore, 700); // (800 + 600) / 2
        assertEq(mathRatings.totalRatings, 2);

        // Check Science ratings
        PeerRating.UserTopicRatings memory scienceRatings = peerRating.getUserTopicRating(bob, scienceTopicId);
        assertEq(scienceRatings.averageScore, 700);
        assertEq(scienceRatings.totalRatings, 1);

        // Check topics Bob has been rated on
        uint32[] memory topics = peerRating.getUserRatedTopics(bob);
        assertEq(topics.length, 2);
    }

    function testRatingWithZeroScore() public {
        vm.prank(alice);
        peerRating.rateUser(bob, mathTopicId, 0);

        vm.prank(charlie);
        peerRating.rateUser(bob, mathTopicId, 800);

        PeerRating.UserTopicRatings memory ratings = peerRating.getUserTopicRating(bob, mathTopicId);
        assertEq(ratings.averageScore, 400); // (0 + 800) / 2
    }

    function testHistoricalRatingQuery() public {
        // Time T0: Alice rates Bob 300
        uint64 t0 = uint64(block.timestamp);
        vm.prank(alice);
        peerRating.rateUser(bob, mathTopicId, 300);

        // Time T1: Charlie rates Bob 500
        uint64 t1 = t0 + 30 days;
        vm.warp(t1);
        vm.prank(charlie);
        peerRating.rateUser(bob, mathTopicId, 500);

        // Time T2: Alice updates to 900
        uint64 t2 = t1 + 183 days;
        vm.warp(t2);
        vm.prank(alice);
        peerRating.rateUser(bob, mathTopicId, 900);

        // Query at T1: should show average of 400 (300 + 500) / 2
        PeerRating.UserTopicRatings memory ratingsAtT1 = peerRating.getUserTopicRatingAtTime(bob, mathTopicId, t1);
        assertEq(ratingsAtT1.averageScore, 400);
        assertEq(ratingsAtT1.totalRatings, 2);

        // Query at T2: should show average of 700 (900 + 500) / 2
        PeerRating.UserTopicRatings memory ratingsAtT2 = peerRating.getUserTopicRatingAtTime(bob, mathTopicId, t2);
        assertEq(ratingsAtT2.averageScore, 700);
        assertEq(ratingsAtT2.totalRatings, 2);
    }

    function testRatersArrayDoesNotGrowOnUpdate() public {
        // First rating
        vm.prank(alice);
        peerRating.rateUser(bob, mathTopicId, 500);

        address[] memory raters1 = peerRating.getTopicRaters(bob, mathTopicId);
        assertEq(raters1.length, 1);

        // Update rating after cooldown
        vm.warp(block.timestamp + 183 days);
        vm.prank(alice);
        peerRating.rateUser(bob, mathTopicId, 900);

        // Raters array should still have length 1
        address[] memory raters2 = peerRating.getTopicRaters(bob, mathTopicId);
        assertEq(raters2.length, 1);
        assertEq(raters2[0], alice);
    }

    function testLastRatingTimeTracking() public {
        uint64 firstTime = uint64(block.timestamp);
        vm.prank(alice);
        peerRating.rateUser(bob, mathTopicId, 500);

        PeerRating.UserTopicRatings memory ratings1 = peerRating.getUserTopicRating(bob, mathTopicId);
        assertEq(ratings1.lastRatingTime, firstTime);

        vm.warp(block.timestamp + 10 days);
        uint64 secondTime = uint64(block.timestamp);
        vm.prank(charlie);
        peerRating.rateUser(bob, mathTopicId, 700);

        PeerRating.UserTopicRatings memory ratings2 = peerRating.getUserTopicRating(bob, mathTopicId);
        assertEq(ratings2.lastRatingTime, secondTime);
    }

    /*///////////////////////////
          EDGE CASES
    ///////////////////////////*/

    function testGetRatingBeforeAnyRating() public view {
        PeerRating.Rating memory rating = peerRating.getRating(bob, mathTopicId, alice);
        assertFalse(rating.exists);
        assertEq(rating.rater, address(0));
        assertEq(rating.score, 0);
    }

    function testGetUserTopicRatingWithNoRatings() public view {
        PeerRating.UserTopicRatings memory ratings = peerRating.getUserTopicRating(bob, mathTopicId);
        assertEq(ratings.averageScore, 0);
        assertEq(ratings.totalRatings, 0);
        assertEq(ratings.lastRatingTime, 0);
    }

    function testGetRatingAtTimeBeforeAnyRating() public {
        uint64 queryTime = uint64(block.timestamp);

        vm.warp(queryTime + 100 days);
        vm.prank(alice);
        peerRating.rateUser(bob, mathTopicId, 800);

        PeerRating.Rating memory rating = peerRating.getRatingAtTime(bob, mathTopicId, alice, queryTime);
        assertFalse(rating.exists);
    }

    function testEmptyRatersArray() public view {
        address[] memory raters = peerRating.getTopicRaters(bob, mathTopicId);
        assertEq(raters.length, 0);
    }

    function testEmptyRatedTopicsArray() public view {
        uint32[] memory topics = peerRating.getUserRatedTopics(bob);
        assertEq(topics.length, 0);
    }

    function testEmptyTimestampsArray() public view {
        uint64[] memory timestamps = peerRating.getRatingTimestamps(bob, mathTopicId, alice);
        assertEq(timestamps.length, 0);
    }
}
