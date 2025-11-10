// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TopicRegistry} from "./TopicRegistry.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title User
 * @notice Manages user profiles and expertise scores across topics
 * @dev Uses efficient storage packing with uint16 for scores (0-1000 range)
 */
contract User is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    /*///////////////////////////
           ERRORS
    ///////////////////////////*/

    error UserAlreadyRegistered();
    error UserNotRegistered();
    error Unauthorized();
    error InvalidTopicId();

    /*///////////////////////////
      TYPE DECLARATIONS
    ///////////////////////////*/

    // Packed struct: 2 per storage slot (128 bits each)
    struct UserTopicExpertise {
        uint16 score; // 0-1000 expertise score
        uint32 totalChallenges; // Total challenges attempted
        uint32 correctChallenges; // Correct challenges
        uint64 lastActivityTime; // Last activity timestamp for time decay
    }

    struct UserProfile {
        address userAddress;
        bool isRegistered;
        uint64 registrationTime;
        uint32 totalTopicsEngaged;
        string name;
    }

    /*///////////////////////////
       STATE VARIABLES
    ///////////////////////////*/

    // Constants
    uint16 public constant MIN_SCORE = 50;
    uint16 public constant MAX_SCORE = 1000;
    uint16 public constant INITIAL_SCORE = 50;

    mapping(address => UserProfile) public userProfiles;
    mapping(address => mapping(uint32 => UserTopicExpertise)) public userExpertise; // user => topicId => expertise
    mapping(address => uint32[]) public userTopics; // user => engaged topic IDs

    TopicRegistry public topicRegistry;
    address public reputationEngine; // Will be set after ReputationEngine deployment
    address public peerRatingContract; // Will be set after PeerRating deployment

    /*///////////////////////////
           EVENTS
    ///////////////////////////*/

    event UserRegistered(address indexed user, uint64 timestamp);
    event ExpertiseUpdated(address indexed user, uint32 indexed topicId, uint16 newScore);
    event ChallengeAttempted(address indexed user, uint32 indexed topicId, bool correct);

    /*///////////////////////////
         MODIFIERS
    ///////////////////////////*/

    modifier onlyReputationEngine() {
        if (msg.sender != reputationEngine) revert Unauthorized();
        _;
    }

    modifier onlyRegistered(address user) {
        if (!userProfiles[user].isRegistered) revert UserNotRegistered();
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
     */
    function initialize(address initialOwner, address _topicRegistry) external initializer {
        __Ownable_init(initialOwner);
        topicRegistry = TopicRegistry(_topicRegistry);
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
     * @notice Set the peer rating contract address (can only be done once)
     * @param _peerRatingContract Address of the PeerRating contract
     */
    function setPeerRatingContract(address _peerRatingContract) external onlyOwner {
        if (peerRatingContract != address(0)) revert Unauthorized();
        peerRatingContract = _peerRatingContract;
    }

    /**
     * @notice Register a new user
     * @param name The name of the user
     */
    function registerUser(string calldata name) external {
        if (userProfiles[msg.sender].isRegistered) revert UserAlreadyRegistered();

        userProfiles[msg.sender] = UserProfile({
            userAddress: msg.sender,
            isRegistered: true,
            registrationTime: uint64(block.timestamp),
            totalTopicsEngaged: 0,
            name: name
        });

        emit UserRegistered(msg.sender, uint64(block.timestamp));
    }

    /**
     * @notice Record a challenge attempt (called by Challenge contract via ReputationEngine)
     * @param user User address
     * @param topicId Topic ID
     * @param correct Whether the answer was correct
     */
    function recordChallengeAttempt(address user, uint32 topicId, bool correct) external onlyReputationEngine {
        if (!userProfiles[user].isRegistered) revert UserNotRegistered();

        // Verify topic exists
        TopicRegistry.Topic memory topic = topicRegistry.getTopic(topicId);
        if (!topic.isActive) revert InvalidTopicId();

        UserTopicExpertise storage expertise = userExpertise[user][topicId];

        // Initialize if first attempt in this topic
        if (expertise.totalChallenges == 0) {
            expertise.score = INITIAL_SCORE;
            userTopics[user].push(topicId);
            userProfiles[user].totalTopicsEngaged++;
        }

        expertise.totalChallenges++;
        if (correct) {
            expertise.correctChallenges++;
        }
        expertise.lastActivityTime = uint64(block.timestamp);

        emit ChallengeAttempted(user, topicId, correct);
    }

    /**
     * @notice Update user's expertise score (called by ReputationEngine)
     * @param user User address
     * @param topicId Topic ID
     * @param newScore New expertise score
     */
    function updateExpertiseScore(address user, uint32 topicId, uint16 newScore) external onlyReputationEngine {
        if (newScore > MAX_SCORE) newScore = MAX_SCORE;
        if (newScore < MIN_SCORE) newScore = MIN_SCORE;

        userExpertise[user][topicId].score = newScore;
        emit ExpertiseUpdated(user, topicId, newScore);
    }

    /*///////////////////////////
        VIEW FUNCTIONS
    ///////////////////////////*/

    /**
     * @notice Get user's expertise in a specific topic
     * @param user User address
     * @param topicId Topic ID
     * @return expertise UserTopicExpertise struct
     */
    function getUserExpertise(address user, uint32 topicId) external view returns (UserTopicExpertise memory) {
        return userExpertise[user][topicId];
    }

    /**
     * @notice Get user's expertise score (with initial score if never attempted)
     * @param user User address
     * @param topicId Topic ID
     * @return score Expertise score (0-1000)
     */
    function getUserScore(address user, uint32 topicId) external view returns (uint16) {
        UserTopicExpertise memory expertise = userExpertise[user][topicId];
        if (expertise.totalChallenges == 0) {
            return INITIAL_SCORE; // Default score for new topics
        }
        return expertise.score;
    }

    /**
     * @notice Get all topics a user has engaged with
     * @param user User address
     * @return Array of topic IDs
     */
    function getUserTopics(address user) external view returns (uint32[] memory) {
        return userTopics[user];
    }

    /**
     * @notice Get user profile
     * @param user User address
     * @return UserProfile struct
     */
    function getUserProfile(address user) external view returns (UserProfile memory) {
        return userProfiles[user];
    }

    /**
     * @notice Calculate accuracy percentage for a user in a topic
     * @param user User address
     * @param topicId Topic ID
     * @return accuracy Accuracy in basis points (0-10000, where 10000 = 100%)
     */
    function getAccuracy(address user, uint32 topicId) external view returns (uint16) {
        UserTopicExpertise memory expertise = userExpertise[user][topicId];
        if (expertise.totalChallenges == 0) return 0;
        return uint16((expertise.correctChallenges * 10000) / expertise.totalChallenges);
    }

    /**
     * @notice Check if user is registered
     * @param user User address
     * @return true if registered
     */
    function isRegistered(address user) external view returns (bool) {
        return userProfiles[user].isRegistered;
    }

    /*///////////////////////////
      INTERNAL FUNCTIONS
    ///////////////////////////*/

    /**
     * @notice Authorize contract upgrade
     * @dev Only owner can upgrade the contract
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
