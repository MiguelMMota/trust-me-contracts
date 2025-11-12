// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReputationEngine} from "./ReputationEngine.sol";
import {TopicRegistry} from "./TopicRegistry.sol";
import {User} from "./User.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title PeerRating
 * @notice Manages peer-to-peer reputation ratings across topics
 * @dev Allows users to rate each other's expertise, complementing challenge-based scoring
 */
contract PeerRating is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    /*///////////////////////////
           ERRORS
    ///////////////////////////*/

    error UserNotRegistered();
    error InvalidTopicId();
    error SelfRatingNotAllowed();
    error InvalidRatingValue();
    error RatingNotFound();
    error RatedTooRecently(address, address, uint32, uint64); // rater, ratee, topic, late rating timestamp
    error Unauthorized();

    /*///////////////////////////
      TYPE DECLARATIONS
    ///////////////////////////*/

    struct Rating {
        address rater; // Who gave the rating
        address ratee; // Who received the rating
        uint32 topicId; // Topic the rating is for
        uint16 score; // Rating score (0-1000)
        uint64 timestamp; // When the rating was given
        bool exists; // Whether this rating exists
    }

    struct UserTopicRatings {
        uint16 averageScore; // Average rating received (0-1000)
        uint32 totalRatings; // Number of ratings received
        uint64 lastRatingTime; // Last time user was rated (for time decay)
    }

    /*///////////////////////////
       STATE VARIABLES
    ///////////////////////////*/

    // Constants
    uint16 public constant MIN_RATING = 0;
    uint16 public constant MAX_RATING = 1000;
    uint64 public constant RATING_COOLDOWN_PERIOD = 182 days; // 6 months

    // user => topicId => rater => timestamp => Rating
    mapping(address => mapping(uint32 => mapping(address => mapping(uint64 => Rating)))) public ratings;

    // user => topicId => rater => array of timestamps when they were rated
    mapping(address => mapping(uint32 => mapping(address => uint64[]))) public ratingTimestamps;

    // user => topicId => aggregated ratings data (at current time)
    mapping(address => mapping(uint32 => UserTopicRatings)) public userTopicRatings;

    // user => topicId => array of raters who rated them
    mapping(address => mapping(uint32 => address[])) public topicRaters;

    // user => topics they've been rated on
    mapping(address => uint32[]) public userRatedTopics;

    // rater => array of all ratings they've made
    mapping(address => Rating[]) public ratingsMadeByUser;

    TopicRegistry public topicRegistry;
    User public userContract;
    address public reputationEngine; // Will be set after ReputationEngine deployment

    /*///////////////////////////
           EVENTS
    ///////////////////////////*/

    event RatingSubmitted(
        address indexed rater, address indexed ratee, uint32 indexed topicId, uint16 score, uint64 timestamp
    );

    event RatingUpdated(
        address indexed rater,
        address indexed ratee,
        uint32 indexed topicId,
        uint16 oldScore,
        uint16 newScore,
        uint64 timestamp
    );

    event AggregateRatingUpdated(
        address indexed user, uint32 indexed topicId, uint16 newAverageScore, uint32 totalRatings
    );

    /*///////////////////////////
         MODIFIERS
    ///////////////////////////*/

    modifier onlyReputationEngine() {
        if (msg.sender != reputationEngine) revert Unauthorized();
        _;
    }

    modifier onlyRegistered(address user) {
        if (!userContract.isRegistered(user)) revert UserNotRegistered();
        _;
    }

    /*///////////////////////////
         CONSTRUCTOR
    ///////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract
     * @param initialOwner The address that will own this contract
     * @param _topicRegistry Address of the TopicRegistry contract
     * @param _userContract Address of the User contract
     */
    function initialize(address initialOwner, address _topicRegistry, address _userContract) external initializer {
        __Ownable_init(initialOwner);
        topicRegistry = TopicRegistry(_topicRegistry);
        userContract = User(_userContract);
    }

    /*///////////////////////////
      EXTERNAL FUNCTIONS
    ///////////////////////////*/

    /**
     * @notice Set the reputation engine address (can only be done once)
     * @param _reputationEngine Address of the ReputationEngine contract
     */
    function setReputationEngine(address _reputationEngine) external onlyOwner {
        if (reputationEngine != address(0)) revert Unauthorized();
        reputationEngine = _reputationEngine;
    }

    /**
     * @notice Submit a new rating for another user on a specific topic
     * @notice Raters can submit multiple ratings over time to reflect changes in expertise,
     *   but only after a cooldown period
     * @param ratee Address of user being rated
     * @param topicId Topic ID
     * @param score Rating score (0-1000)
     */
    function rateUser(address ratee, uint32 topicId, uint16 score)
        external
        onlyRegistered(msg.sender)
        onlyRegistered(ratee)
    {
        address rater = msg.sender;
        _validateRateUserInputs(ratee, rater, topicId, score);

        // Check if rater has rated before and enforce cooldown period
        uint64 timestamp = uint64(block.timestamp);
        uint64[] storage timestamps = ratingTimestamps[ratee][topicId][rater];

        bool isFirstRatingFromRater = timestamps.length == 0;
        if (!isFirstRatingFromRater) {
            // Get the most recent rating timestamp
            uint64 lastRatingTimestamp = timestamps[timestamps.length - 1];

            // Check if cooldown period has passed
            if (timestamp < lastRatingTimestamp + RATING_COOLDOWN_PERIOD) {
                revert RatedTooRecently(rater, ratee, topicId, lastRatingTimestamp);
            }
        }

        _rateUser(rater, ratee, topicId, score);
    }

    /**
     * @notice Admin function to create test ratings on behalf of users (bypasses cooldown)
     * @dev Only callable by owner, intended for initial data population during deployment
     * @param rater Address of the user giving the rating
     * @param ratee Address of user being rated
     * @param topicId Topic ID
     * @param score Rating score (0-1000)
     */
    function adminRateUser(address rater, address ratee, uint32 topicId, uint16 score)
        external
        onlyOwner
        onlyRegistered(rater)
        onlyRegistered(ratee)
    {
        _validateRateUserInputs(ratee, rater, topicId, score);
        _rateUser(rater, ratee, topicId, score);
    }

    /**
     * @notice Internal function to recalculate aggregate rating for a user on a topic at a specific time
     * @param user User address
     * @param topicId Topic ID
     * @param scoreTime Calculate ratings as of this timestamp
     */
    function _updateAggregateRating(address user, uint32 topicId, uint256 scoreTime) internal {
        address[] memory raters = topicRaters[user][topicId];
        uint256 totalScore = 0;
        uint256 validRatings = 0;
        uint64 mostRecentTime = 0;

        for (uint256 i = 0; i < raters.length; i++) {
            address rater = raters[i];

            // Get the most recent rating from this rater before scoreTime
            Rating memory rating = _getMostRecentRatingBefore(user, topicId, rater, scoreTime);

            if (rating.exists) {
                totalScore += rating.score;
                validRatings++;
                if (rating.timestamp > mostRecentTime) {
                    mostRecentTime = rating.timestamp;
                }
            }
        }

        uint16 averageScore = validRatings > 0 ? uint16(totalScore / validRatings) : 0;

        userTopicRatings[user][topicId] = UserTopicRatings({
            averageScore: averageScore,
            totalRatings: uint32(validRatings),
            lastRatingTime: mostRecentTime
        });

        emit AggregateRatingUpdated(user, topicId, averageScore, uint32(validRatings));
    }

    /**
     * @notice Get the most recent rating from a rater before a specific time
     * @param ratee User who received the rating
     * @param topicId Topic ID
     * @param rater User who gave the rating
     * @param beforeTime Only consider ratings before this timestamp
     * @return rating The most recent Rating before the specified time
     */
    function _getMostRecentRatingBefore(address ratee, uint32 topicId, address rater, uint256 beforeTime)
        internal
        view
        returns (Rating memory)
    {
        uint64[] memory timestamps = ratingTimestamps[ratee][topicId][rater];

        // Return empty rating if no timestamps
        if (timestamps.length == 0) {
            return Rating({rater: address(0), ratee: address(0), topicId: 0, score: 0, timestamp: 0, exists: false});
        }

        // Find the most recent timestamp before scoreTime
        uint64 mostRecentTimestamp = 0;
        bool found = false;

        for (uint256 i = 0; i < timestamps.length; i++) {
            if (timestamps[i] <= beforeTime && timestamps[i] > mostRecentTimestamp) {
                mostRecentTimestamp = timestamps[i];
                found = true;
            }
        }

        if (!found) {
            return Rating({rater: address(0), ratee: address(0), topicId: 0, score: 0, timestamp: 0, exists: false});
        }

        return ratings[ratee][topicId][rater][mostRecentTimestamp];
    }

    /*///////////////////////////
        VIEW FUNCTIONS
    ///////////////////////////*/

    /**
     * @notice Get the most recent rating from one user to another on a topic (at current time)
     * @param ratee User who received the rating
     * @param topicId Topic ID
     * @param rater User who gave the rating
     * @return Rating struct (most recent)
     */
    function getRating(address ratee, uint32 topicId, address rater) external view returns (Rating memory) {
        return _getMostRecentRatingBefore(ratee, topicId, rater, block.timestamp);
    }

    /**
     * @notice Get a rating from one user to another on a topic at a specific timestamp
     * @param ratee User who received the rating
     * @param topicId Topic ID
     * @param rater User who gave the rating
     * @param timestamp Specific timestamp of the rating
     * @return Rating struct at that exact timestamp
     */
    function getRatingAtTimestamp(address ratee, uint32 topicId, address rater, uint64 timestamp)
        external
        view
        returns (Rating memory)
    {
        return ratings[ratee][topicId][rater][timestamp];
    }

    /**
     * @notice Get the most recent rating from a rater before a specific time
     * @param ratee User who received the rating
     * @param topicId Topic ID
     * @param rater User who gave the rating
     * @param scoreTime Get rating as of this timestamp
     * @return Rating struct (most recent before scoreTime)
     */
    function getRatingAtTime(address ratee, uint32 topicId, address rater, uint64 scoreTime)
        external
        view
        returns (Rating memory)
    {
        return _getMostRecentRatingBefore(ratee, topicId, rater, scoreTime);
    }

    /**
     * @notice Get all timestamps when a rater rated a user on a topic
     * @param ratee User who received the rating
     * @param topicId Topic ID
     * @param rater User who gave the rating
     * @return Array of timestamps
     */
    function getRatingTimestamps(address ratee, uint32 topicId, address rater)
        external
        view
        returns (uint64[] memory)
    {
        return ratingTimestamps[ratee][topicId][rater];
    }

    /**
     * @notice Get aggregate ratings for a user on a topic (at current time)
     * @param user User address
     * @param topicId Topic ID
     * @return UserTopicRatings struct
     */
    function getUserTopicRating(address user, uint32 topicId) external view returns (UserTopicRatings memory) {
        return userTopicRatings[user][topicId];
    }

    /**
     * @notice Get all ratings made by a user (where they are the rater)
     * @param user User address (rater)
     * @return Array of Rating structs representing all ratings this user has given
     */
    function getRatingsByUser(address user) external view returns (Rating[] memory) {
        return ratingsMadeByUser[user];
    }

    /**
     * @notice Get aggregate ratings for a user on a topic at a specific time
     * @param user User address
     * @param topicId Topic ID
     * @param scoreTime Calculate ratings as of this timestamp
     * @return UserTopicRatings struct calculated at scoreTime
     */
    function getUserTopicRatingAtTime(address user, uint32 topicId, uint64 scoreTime)
        external
        view
        returns (UserTopicRatings memory)
    {
        address[] memory raters = topicRaters[user][topicId];
        uint256 totalScore = 0;
        uint256 validRatings = 0;
        uint64 mostRecentTime = 0;

        for (uint256 i = 0; i < raters.length; i++) {
            address rater = raters[i];

            // Get the most recent rating from this rater before scoreTime
            Rating memory rating = _getMostRecentRatingBefore(user, topicId, rater, scoreTime);

            if (rating.exists) {
                totalScore += rating.score;
                validRatings++;
                if (rating.timestamp > mostRecentTime) {
                    mostRecentTime = rating.timestamp;
                }
            }
        }

        uint16 averageScore = validRatings > 0 ? uint16(totalScore / validRatings) : 0;

        return UserTopicRatings({
            averageScore: averageScore,
            totalRatings: uint32(validRatings),
            lastRatingTime: mostRecentTime
        });
    }

    /**
     * @notice Get all raters who have rated a user on a topic
     * @param user User address
     * @param topicId Topic ID
     * @return Array of rater addresses
     */
    function getTopicRaters(address user, uint32 topicId) external view returns (address[] memory) {
        return topicRaters[user][topicId];
    }

    /**
     * @notice Get all topics a user has been rated on
     * @param user User address
     * @return Array of topic IDs
     */
    function getUserRatedTopics(address user) external view returns (uint32[] memory) {
        return userRatedTopics[user];
    }

    /**
     * @notice Get the average peer rating score for a user on a topic
     * @param user User address
     * @param topicId Topic ID
     * @return Average score (0-1000), or 0 if no ratings
     */
    function getAverageScore(address user, uint32 topicId) external view returns (uint16) {
        return userTopicRatings[user][topicId].averageScore;
    }

    /**
     * @notice Get the number of ratings a user has received on a topic
     * @param user User address
     * @param topicId Topic ID
     * @return Number of ratings received
     */
    function getRatingCount(address user, uint32 topicId) external view returns (uint32) {
        return userTopicRatings[user][topicId].totalRatings;
    }

    /**
     * @notice Check if a rating exists from rater to ratee on a topic (at current time)
     * @param ratee User who received the rating
     * @param topicId Topic ID
     * @param rater User who gave the rating
     * @return true if any rating exists from this rater
     */
    function ratingExists(address ratee, uint32 topicId, address rater) external view returns (bool) {
        return ratingTimestamps[ratee][topicId][rater].length > 0;
    }

    /**
     * @notice Check if a rating exists at a specific timestamp
     * @param ratee User who received the rating
     * @param topicId Topic ID
     * @param rater User who gave the rating
     * @param timestamp Specific timestamp to check
     * @return true if rating exists at that timestamp
     */
    function ratingExistsAtTimestamp(address ratee, uint32 topicId, address rater, uint64 timestamp)
        external
        view
        returns (bool)
    {
        return ratings[ratee][topicId][rater][timestamp].exists;
    }

    /*///////////////////////////
      INTERNAL FUNCTIONS
    ///////////////////////////*/

    /**
     * @notice Authorize contract upgrade
     * @dev Only owner can upgrade the contract
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice inner function to validate inputs to rate a user on a topic
     * @param rater Address of the user giving the rating
     * @param ratee Address of user being rated
     * @param topicId Topic ID
     * @param score Rating score (0-1000)
     */
    function _validateRateUserInputs(address ratee, address rater, uint32 topicId, uint16 score)
        internal
        view
        onlyRegistered(rater)
        onlyRegistered(ratee)
    {
        // Validate inputs
        if (rater == ratee) revert SelfRatingNotAllowed();
        if (score > MAX_RATING) revert InvalidRatingValue();

        // Verify topic exists
        TopicRegistry.Topic memory topic = topicRegistry.getTopic(topicId);
        if (!topic.isActive) revert InvalidTopicId();
    }

    /**
     * @notice inner function to record a user rating and recalculate user score for the respective topic
     * @param rater Address of the user giving the rating
     * @param ratee Address of user being rated
     * @param topicId Topic ID
     * @param score Rating score (0-1000)
     */
    function _rateUser(address rater, address ratee, uint32 topicId, uint16 score)
        internal
        onlyRegistered(rater)
        onlyRegistered(ratee)
    {
        uint64 timestamp = uint64(block.timestamp);

        // Check if rater has rated before and enforce cooldown period
        uint64[] storage timestamps = ratingTimestamps[ratee][topicId][rater];

        // Create new rating entry at this timestamp
        Rating storage rating = ratings[ratee][topicId][rater][timestamp];
        rating.rater = rater;
        rating.ratee = ratee;
        rating.topicId = topicId;
        rating.score = score;
        rating.timestamp = timestamp;
        rating.exists = true;

        // Track this rating in the rater's list of ratings made
        ratingsMadeByUser[rater].push(
            Rating({rater: rater, ratee: ratee, topicId: topicId, score: score, timestamp: timestamp, exists: true})
        );

        // Track this timestamp
        timestamps.push(timestamp);

        // Track this rater if first time rating this user on this topic
        bool isFirstRatingFromRater = timestamps.length == 0;
        if (isFirstRatingFromRater) {
            topicRaters[ratee][topicId].push(rater);

            // Track this topic if first rating ever received
            if (userTopicRatings[ratee][topicId].totalRatings == 0) {
                userRatedTopics[ratee].push(topicId);
            }
        }

        // Update user's expertise score on this topic
        ReputationEngine(reputationEngine).calculateExpertiseScore(ratee, topicId);

        // Emit appropriate event
        if (isFirstRatingFromRater) {
            emit RatingSubmitted(rater, ratee, topicId, score, timestamp);
        } else {
            // This is an amendment - get the previous rating
            uint64 previousTimestamp = timestamps[timestamps.length - 2];
            uint16 oldScore = ratings[ratee][topicId][rater][previousTimestamp].score;
            emit RatingUpdated(rater, ratee, topicId, oldScore, score, timestamp);
        }

        // Update aggregate ratings (at current time)
        _updateAggregateRating(ratee, topicId, block.timestamp);
    }
}
