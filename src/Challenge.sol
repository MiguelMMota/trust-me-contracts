// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./TopicRegistry.sol";
import "./User.sol";

/**
 * @title Challenge
 * @notice Manages objective validation questions for expertise building
 * @dev Stores question hashes on-chain, full questions stored off-chain (IPFS/events)
 */
contract Challenge {
    /*///////////////////////////
           ERRORS
    ///////////////////////////*/

    error Unauthorized();
    error ChallengeNotFound();
    error ChallengeNotActive();
    error InvalidTopic();
    error AlreadyAttempted();
    error UserNotRegistered();
    error EmptyHash();

    /*///////////////////////////
      TYPE DECLARATIONS
    ///////////////////////////*/

    enum DifficultyLevel {
        Easy,      // +5-10 score on correct
        Medium,    // +10-20 score on correct
        Hard,      // +20-40 score on correct
        Expert     // +40-80 score on correct
    }

    enum ChallengeStatus {
        Active,
        Inactive,
        Disputed
    }

    struct ChallengeData {
        uint64 id;
        address creator;
        uint32 topicId;
        DifficultyLevel difficulty;
        ChallengeStatus status;
        bytes32 questionHash;      // Hash of question content (stored off-chain)
        bytes32 correctAnswerHash; // Hash of correct answer
        uint64 createdAt;
        uint32 totalAttempts;
        uint32 correctAttempts;
    }

    struct ChallengeAttempt {
        address user;
        uint64 challengeId;
        bytes32 answerHash;
        bool isCorrect;
        uint64 attemptedAt;
    }

    /*///////////////////////////
       STATE VARIABLES
    ///////////////////////////*/

    mapping(uint64 => ChallengeData) public challenges;
    mapping(address => mapping(uint64 => ChallengeAttempt)) public userAttempts; // user => challengeId => attempt
    mapping(address => uint64[]) public userChallengeHistory; // user => challengeIds[]
    mapping(uint32 => uint64[]) public topicChallenges; // topicId => challengeIds[]

    uint64 public challengeCount;
    TopicRegistry public immutable topicRegistry;
    User public immutable userContract;
    address public reputationEngine;

    /*///////////////////////////
           EVENTS
    ///////////////////////////*/

    event ChallengeCreated(
        uint64 indexed challengeId,
        address indexed creator,
        uint32 indexed topicId,
        DifficultyLevel difficulty
    );
    event ChallengeAttempted(
        uint64 indexed challengeId,
        address indexed user,
        bool isCorrect,
        uint64 timestamp
    );
    event ChallengeStatusUpdated(uint64 indexed challengeId, ChallengeStatus newStatus);

    /*///////////////////////////
         MODIFIERS
    ///////////////////////////*/

    modifier onlyReputationEngine() {
        if (msg.sender != reputationEngine) revert Unauthorized();
        _;
    }

    /*///////////////////////////
         CONSTRUCTOR
    ///////////////////////////*/

    constructor(address _topicRegistry, address _userContract) {
        topicRegistry = TopicRegistry(_topicRegistry);
        userContract = User(_userContract);
        challengeCount = 0;
    }

    /*///////////////////////////
      EXTERNAL FUNCTIONS
    ///////////////////////////*/

    /**
     * @notice Set reputation engine address (one-time)
     * @param _reputationEngine ReputationEngine contract address
     */
    function setReputationEngine(address _reputationEngine) external {
        if (reputationEngine != address(0)) revert Unauthorized();
        reputationEngine = _reputationEngine;
    }

    /**
     * @notice Create a new challenge
     * @param topicId Topic ID for this challenge
     * @param difficulty Difficulty level
     * @param questionHash Hash of the question content
     * @param correctAnswerHash Hash of the correct answer
     * @return challengeId The ID of the created challenge
     */
    function createChallenge(
        uint32 topicId,
        DifficultyLevel difficulty,
        bytes32 questionHash,
        bytes32 correctAnswerHash
    ) external returns (uint64) {
        if (questionHash == bytes32(0) || correctAnswerHash == bytes32(0)) revert EmptyHash();

        // Verify topic exists and is active
        TopicRegistry.Topic memory topic = topicRegistry.getTopic(topicId);
        if (!topic.isActive) revert InvalidTopic();

        // Ensure user is registered
        if (!userContract.isRegistered(msg.sender)) revert UserNotRegistered();

        challengeCount++;
        uint64 newChallengeId = challengeCount;

        challenges[newChallengeId] = ChallengeData({
            id: newChallengeId,
            creator: msg.sender,
            topicId: topicId,
            difficulty: difficulty,
            status: ChallengeStatus.Active,
            questionHash: questionHash,
            correctAnswerHash: correctAnswerHash,
            createdAt: uint64(block.timestamp),
            totalAttempts: 0,
            correctAttempts: 0
        });

        topicChallenges[topicId].push(newChallengeId);

        emit ChallengeCreated(newChallengeId, msg.sender, topicId, difficulty);
        return newChallengeId;
    }

    /**
     * @notice Attempt to answer a challenge
     * @param challengeId Challenge ID
     * @param answerHash Hash of the user's answer
     */
    function attemptChallenge(uint64 challengeId, bytes32 answerHash) external {
        ChallengeData storage challenge = challenges[challengeId];

        if (challenge.id == 0) revert ChallengeNotFound();
        if (challenge.status != ChallengeStatus.Active) revert ChallengeNotActive();
        if (!userContract.isRegistered(msg.sender)) revert UserNotRegistered();
        if (userAttempts[msg.sender][challengeId].attemptedAt != 0) revert AlreadyAttempted();

        bool isCorrect = (answerHash == challenge.correctAnswerHash);

        // Record attempt
        userAttempts[msg.sender][challengeId] = ChallengeAttempt({
            user: msg.sender,
            challengeId: challengeId,
            answerHash: answerHash,
            isCorrect: isCorrect,
            attemptedAt: uint64(block.timestamp)
        });

        userChallengeHistory[msg.sender].push(challengeId);

        // Update challenge stats
        challenge.totalAttempts++;
        if (isCorrect) {
            challenge.correctAttempts++;
        }

        emit ChallengeAttempted(challengeId, msg.sender, isCorrect, uint64(block.timestamp));
    }

    /**
     * @notice Update challenge status (creator or admin only)
     * @param challengeId Challenge ID
     * @param newStatus New status
     */
    function updateChallengeStatus(uint64 challengeId, ChallengeStatus newStatus) external {
        ChallengeData storage challenge = challenges[challengeId];
        if (challenge.id == 0) revert ChallengeNotFound();
        if (msg.sender != challenge.creator && msg.sender != topicRegistry.admin()) {
            revert Unauthorized();
        }

        challenge.status = newStatus;
        emit ChallengeStatusUpdated(challengeId, newStatus);
    }

    /*///////////////////////////
        VIEW FUNCTIONS
    ///////////////////////////*/

    /**
     * @notice Get challenge data
     * @param challengeId Challenge ID
     * @return ChallengeData struct
     */
    function getChallenge(uint64 challengeId) external view returns (ChallengeData memory) {
        if (challenges[challengeId].id == 0) revert ChallengeNotFound();
        return challenges[challengeId];
    }

    /**
     * @notice Get user's attempt for a challenge
     * @param user User address
     * @param challengeId Challenge ID
     * @return ChallengeAttempt struct (attemptedAt = 0 if not attempted)
     */
    function getUserAttempt(
        address user,
        uint64 challengeId
    ) external view returns (ChallengeAttempt memory) {
        return userAttempts[user][challengeId];
    }

    /**
     * @notice Get all challenges for a topic
     * @param topicId Topic ID
     * @return Array of challenge IDs
     */
    function getTopicChallenges(uint32 topicId) external view returns (uint64[] memory) {
        return topicChallenges[topicId];
    }

    /**
     * @notice Get user's challenge history
     * @param user User address
     * @return Array of attempted challenge IDs
     */
    function getUserChallengeHistory(address user) external view returns (uint64[] memory) {
        return userChallengeHistory[user];
    }

    /**
     * @notice Check if user has attempted a challenge
     * @param user User address
     * @param challengeId Challenge ID
     * @return true if attempted
     */
    function hasAttempted(address user, uint64 challengeId) external view returns (bool) {
        return userAttempts[user][challengeId].attemptedAt != 0;
    }

    /*///////////////////////////
        PURE FUNCTIONS
    ///////////////////////////*/

    /**
     * @notice Get challenge difficulty multiplier for scoring
     * @param difficulty Difficulty level
     * @return multiplier (10 = 1.0x, 20 = 2.0x, etc.)
     */
    function getDifficultyMultiplier(DifficultyLevel difficulty) public pure returns (uint16) {
        if (difficulty == DifficultyLevel.Easy) return 10;
        if (difficulty == DifficultyLevel.Medium) return 15;
        if (difficulty == DifficultyLevel.Hard) return 25;
        return 40; // Expert
    }
}
