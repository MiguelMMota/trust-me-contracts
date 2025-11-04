// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./TopicRegistry.sol";
import "./User.sol";

/**
 * @title PeerRating
 * @notice Manages peer-to-peer reputation ratings across topics
 * @dev Allows users to rate each other's expertise, complementing challenge-based scoring
 */
contract PeerRating {
    /*///////////////////////////
           ERRORS
    ///////////////////////////*/

    error UserNotRegistered();
    error InvalidTopicId();
    error SelfRatingNotAllowed();
    error InvalidRatingValue();
    error RatingAlreadyExists();
    error RatingNotFound();
    error Unauthorized();

    /*///////////////////////////
      TYPE DECLARATIONS
    ///////////////////////////*/

    struct Rating {
        address rater;         // Who gave the rating
        address ratee;         // Who received the rating
        uint32 topicId;        // Topic the rating is for
        uint16 score;          // Rating score (0-1000)
        uint64 timestamp;      // When the rating was given
        bool exists;           // Whether this rating exists
    }

    struct UserTopicRatings {
        uint16 averageScore;      // Average rating received (0-1000)
        uint32 totalRatings;      // Number of ratings received
        uint64 lastRatingTime;    // Last time user was rated (for time decay)
    }

    /*///////////////////////////
       STATE VARIABLES
    ///////////////////////////*/

    // Constants
    uint16 public constant MIN_RATING = 0;
    uint16 public constant MAX_RATING = 1000;

    // user => topicId => rater => Rating
    mapping(address => mapping(uint32 => mapping(address => Rating))) public ratings;

    // user => topicId => aggregated ratings data
    mapping(address => mapping(uint32 => UserTopicRatings)) public userTopicRatings;

    // user => topicId => array of raters who rated them
    mapping(address => mapping(uint32 => address[])) public topicRaters;

    // user => topics they've been rated on
    mapping(address => uint32[]) public userRatedTopics;

    TopicRegistry public immutable topicRegistry;
    User public immutable userContract;
    address public reputationEngine; // Will be set after ReputationEngine deployment

    /*///////////////////////////
           EVENTS
    ///////////////////////////*/

    event RatingSubmitted(
        address indexed rater,
        address indexed ratee,
        uint32 indexed topicId,
        uint16 score,
        uint64 timestamp
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
        address indexed user,
        uint32 indexed topicId,
        uint16 newAverageScore,
        uint32 totalRatings
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

    constructor(address _topicRegistry, address _userContract) {
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
    function setReputationEngine(address _reputationEngine) external {
        if (reputationEngine != address(0)) revert Unauthorized();
        reputationEngine = _reputationEngine;
    }

    /**
     * @notice Submit or update a rating for another user on a specific topic
     * @param ratee Address of user being rated
     * @param topicId Topic ID
     * @param score Rating score (0-1000)
     */
    function rateUser(
        address ratee,
        uint32 topicId,
        uint16 score
    ) external onlyRegistered(msg.sender) onlyRegistered(ratee) {
        // Validate inputs
        if (msg.sender == ratee) revert SelfRatingNotAllowed();
        if (score > MAX_RATING) revert InvalidRatingValue();

        // Verify topic exists
        TopicRegistry.Topic memory topic = topicRegistry.getTopic(topicId);
        if (!topic.isActive) revert InvalidTopicId();

        Rating storage rating = ratings[ratee][topicId][msg.sender];
        bool isUpdate = rating.exists;
        uint16 oldScore = rating.score;

        if (isUpdate) {
            // Update existing rating
            rating.score = score;
            rating.timestamp = uint64(block.timestamp);

            emit RatingUpdated(msg.sender, ratee, topicId, oldScore, score, uint64(block.timestamp));
        } else {
            // Create new rating
            rating.rater = msg.sender;
            rating.ratee = ratee;
            rating.topicId = topicId;
            rating.score = score;
            rating.timestamp = uint64(block.timestamp);
            rating.exists = true;

            // Track this rater
            topicRaters[ratee][topicId].push(msg.sender);

            // Track this topic if first rating
            if (userTopicRatings[ratee][topicId].totalRatings == 0) {
                userRatedTopics[ratee].push(topicId);
            }

            emit RatingSubmitted(msg.sender, ratee, topicId, score, uint64(block.timestamp));
        }

        // Update aggregate ratings
        _updateAggregateRating(ratee, topicId);
    }

    /**
     * @notice Internal function to recalculate aggregate rating for a user on a topic
     * @param user User address
     * @param topicId Topic ID
     */
    function _updateAggregateRating(address user, uint32 topicId) internal {
        address[] memory raters = topicRaters[user][topicId];
        uint256 totalScore = 0;
        uint256 validRatings = 0;
        uint64 mostRecentTime = 0;

        for (uint256 i = 0; i < raters.length; i++) {
            Rating memory rating = ratings[user][topicId][raters[i]];
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

    /*///////////////////////////
        VIEW FUNCTIONS
    ///////////////////////////*/

    /**
     * @notice Get a specific rating from one user to another on a topic
     * @param ratee User who received the rating
     * @param topicId Topic ID
     * @param rater User who gave the rating
     * @return Rating struct
     */
    function getRating(
        address ratee,
        uint32 topicId,
        address rater
    ) external view returns (Rating memory) {
        return ratings[ratee][topicId][rater];
    }

    /**
     * @notice Get aggregate ratings for a user on a topic
     * @param user User address
     * @param topicId Topic ID
     * @return UserTopicRatings struct
     */
    function getUserTopicRating(
        address user,
        uint32 topicId
    ) external view returns (UserTopicRatings memory) {
        return userTopicRatings[user][topicId];
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
     * @notice Check if a rating exists from rater to ratee on a topic
     * @param ratee User who received the rating
     * @param topicId Topic ID
     * @param rater User who gave the rating
     * @return true if rating exists
     */
    function ratingExists(
        address ratee,
        uint32 topicId,
        address rater
    ) external view returns (bool) {
        return ratings[ratee][topicId][rater].exists;
    }
}
