// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./User.sol";
import "./Challenge.sol";
import "./TopicRegistry.sol";
import "./PeerRating.sol";

/**
 * @title ReputationEngine
 * @notice Calculates and updates user expertise scores based on challenge performance and peer ratings
 * @dev Implements time-weighted scoring with accuracy, volume, and peer rating factors
 */
contract ReputationEngine {
    /*///////////////////////////
           ERRORS
    ///////////////////////////*/

    error Unauthorized();
    error InvalidInput();

    /*///////////////////////////
       STATE VARIABLES
    ///////////////////////////*/

    // Constants for scoring algorithm
    uint16 public constant MIN_SCORE = 50;
    uint16 public constant MAX_SCORE = 1000;
    uint16 public constant ACCURACY_WEIGHT = 70;  // 70% weight
    uint16 public constant VOLUME_WEIGHT = 30;    // 30% weight

    // Time decay periods (in seconds)
    uint64 public constant RECENT_PERIOD = 30 days;
    uint64 public constant MID_PERIOD = 60 days;

    User public immutable userContract;
    Challenge public immutable challengeContract;
    TopicRegistry public immutable topicRegistry;
    PeerRating public peerRatingContract; // Set after deployment

    /*///////////////////////////
           EVENTS
    ///////////////////////////*/

    event ScoreCalculated(
        address indexed user,
        uint32 indexed topicId,
        uint16 oldScore,
        uint16 newScore
    );

    /*///////////////////////////
         CONSTRUCTOR
    ///////////////////////////*/

    constructor(
        address _userContract,
        address _challengeContract,
        address _topicRegistry
    ) {
        userContract = User(_userContract);
        challengeContract = Challenge(_challengeContract);
        topicRegistry = TopicRegistry(_topicRegistry);
    }

    /*///////////////////////////
      EXTERNAL FUNCTIONS
    ///////////////////////////*/

    /**
     * @notice Set the peer rating contract address (can only be done once)
     * @param _peerRatingContract Address of the PeerRating contract
     */
    function setPeerRatingContract(address _peerRatingContract) external {
        if (address(peerRatingContract) != address(0)) revert Unauthorized();
        peerRatingContract = PeerRating(_peerRatingContract);
    }

    /**
     * @notice Process challenge attempt and update user score
     * @param user User address
     * @param challengeId Challenge ID
     */
    function processChallengeAttempt(address user, uint64 challengeId) external {
        // Verify the attempt exists
        Challenge.ChallengeAttempt memory attempt = challengeContract.getUserAttempt(user, challengeId);
        if (attempt.attemptedAt == 0) revert InvalidInput();

        // Get challenge data
        Challenge.ChallengeData memory challengeData = challengeContract.getChallenge(challengeId);

        // Record attempt in user contract
        userContract.recordChallengeAttempt(user, challengeData.topicId, attempt.isCorrect);

        // Calculate and update score
        uint16 newScore = calculateExpertiseScore(user, challengeData.topicId);
        uint16 oldScore = userContract.getUserScore(user, challengeData.topicId);

        userContract.updateExpertiseScore(user, challengeData.topicId, newScore);

        emit ScoreCalculated(user, challengeData.topicId, oldScore, newScore);
    }

    /**
     * @notice Recalculate score for a user in a topic (can be called by anyone for transparency)
     * @param user User address
     * @param topicId Topic ID
     */
    function recalculateScore(address user, uint32 topicId) external {
        uint16 oldScore = userContract.getUserScore(user, topicId);
        uint16 newScore = calculateExpertiseScore(user, topicId);

        if (oldScore != newScore) {
            userContract.updateExpertiseScore(user, topicId, newScore);
            emit ScoreCalculated(user, topicId, oldScore, newScore);
        }
    }

    /**
     * @notice Batch recalculate scores for a user across multiple topics
     * @param user User address
     * @param topicIds Array of topic IDs
     */
    function batchRecalculateScores(address user, uint32[] calldata topicIds) external {
        for (uint256 i = 0; i < topicIds.length; i++) {
            uint16 oldScore = userContract.getUserScore(user, topicIds[i]);
            uint16 newScore = calculateExpertiseScore(user, topicIds[i]);

            if (oldScore != newScore) {
                userContract.updateExpertiseScore(user, topicIds[i], newScore);
                emit ScoreCalculated(user, topicIds[i], oldScore, newScore);
            }
        }
    }

    /**
     * @notice Get voting weight for a user in a topic (used by Poll contract)
     * @param user User address
     * @param topicId Topic ID
     * @return weight Voting weight based on expertise score
     */
    function getVotingWeight(address user, uint32 topicId) external view returns (uint256) {
        // Voting weight is simply the expertise score
        // Can be modified to use different calculation if needed
        return uint256(userContract.getUserScore(user, topicId));
    }

    /**
     * @notice Preview what score a user would have with an additional correct/incorrect answer
     * @param user User address
     * @param topicId Topic ID
     * @param wouldBeCorrect Whether the hypothetical answer would be correct
     * @return projectedScore Projected score after the attempt
     */
    function previewScoreChange(
        address user,
        uint32 topicId,
        bool wouldBeCorrect
    ) external view returns (uint16) {
        User.UserTopicExpertise memory expertise = userContract.getUserExpertise(user, topicId);

        // Simulate the attempt
        uint32 newTotal = expertise.totalChallenges + 1;
        uint32 newCorrect = expertise.correctChallenges + (wouldBeCorrect ? 1 : 0);

        // Calculate projected accuracy
        uint256 projectedAccuracy = (uint256(newCorrect) * 1000) / newTotal;

        // Calculate volume bonus with new total
        uint256 volumeBonus = calculateVolumeBonus(newTotal);

        // Use current time for decay (assuming attempt happens now)
        uint256 timeDecayFactor = 100; // Full weight for current attempt

        uint256 weightedAccuracy = (projectedAccuracy * ACCURACY_WEIGHT) / 100;
        uint256 weightedVolume = (volumeBonus * VOLUME_WEIGHT) / 100;

        uint256 rawScore = ((weightedAccuracy + weightedVolume) * timeDecayFactor) / 100;

        if (rawScore < MIN_SCORE) return MIN_SCORE;
        if (rawScore > MAX_SCORE) return MAX_SCORE;

        return uint16(rawScore);
    }

    /*///////////////////////////
       PUBLIC FUNCTIONS
    ///////////////////////////*/

    /**
     * @notice Calculate expertise score for a user in a topic
     * @param user User address
     * @param topicId Topic ID
     * @return finalScore Calculated score (50-1000)
     * @dev Combines challenge-based and peer rating scores, allowing max score via either path
     */
    function calculateExpertiseScore(
        address user,
        uint32 topicId
    ) public view returns (uint16) {
        uint16 challengeScore = calculateChallengeScore(user, topicId);
        uint16 peerRatingScore = calculatePeerRatingScore(user, topicId);

        // If neither score exists, return minimum
        if (challengeScore == 0 && peerRatingScore == 0) {
            return MIN_SCORE;
        }

        // If only one exists, return that score
        if (challengeScore == 0) return peerRatingScore;
        if (peerRatingScore == 0) return challengeScore;

        // If both exist, use a blended approach that rewards having both
        // Take the maximum of: challenge score, peer rating score, or weighted blend
        uint256 blendedScore = (uint256(challengeScore) * 60 + uint256(peerRatingScore) * 40) / 100;

        // Return the highest score to ensure users can reach max via either path
        uint16 maxScore = challengeScore > peerRatingScore ? challengeScore : peerRatingScore;
        uint16 finalScore = uint16(blendedScore) > maxScore ? uint16(blendedScore) : maxScore;

        // Ensure score is within bounds
        if (finalScore < MIN_SCORE) return MIN_SCORE;
        if (finalScore > MAX_SCORE) return MAX_SCORE;

        return finalScore;
    }

    /**
     * @notice Calculate challenge-based expertise score
     * @param user User address
     * @param topicId Topic ID
     * @return score Challenge-based score (0-1000)
     */
    function calculateChallengeScore(
        address user,
        uint32 topicId
    ) public view returns (uint16) {
        User.UserTopicExpertise memory expertise = userContract.getUserExpertise(user, topicId);

        // If no challenges attempted, return 0
        if (expertise.totalChallenges == 0) {
            return 0;
        }

        // Calculate accuracy component (0-1000)
        uint256 accuracyScore = (uint256(expertise.correctChallenges) * 1000) / expertise.totalChallenges;

        // Calculate volume bonus (0-200 points, using square root for diminishing returns)
        uint256 volumeBonus = calculateVolumeBonus(expertise.totalChallenges);

        // Calculate time decay factor (reduces impact of old activity)
        uint256 timeDecayFactor = calculateTimeDecay(expertise.lastActivityTime);

        // Combine components with weights
        // accuracyScore is already 0-1000, volumeBonus is 0-200
        uint256 weightedAccuracy = (accuracyScore * ACCURACY_WEIGHT) / 100;
        uint256 weightedVolume = (volumeBonus * VOLUME_WEIGHT) / 100;

        // Apply time decay
        uint256 rawScore = ((weightedAccuracy + weightedVolume) * timeDecayFactor) / 100;

        // Ensure score is within bounds
        if (rawScore < MIN_SCORE) rawScore = MIN_SCORE;
        if (rawScore > MAX_SCORE) rawScore = MAX_SCORE;

        return uint16(rawScore);
    }

    /**
     * @notice Calculate peer rating-based expertise score
     * @param user User address
     * @param topicId Topic ID
     * @return score Peer rating score (0-1000)
     */
    function calculatePeerRatingScore(
        address user,
        uint32 topicId
    ) public view returns (uint16) {
        // Return 0 if peer rating contract not set
        if (address(peerRatingContract) == address(0)) {
            return 0;
        }

        PeerRating.UserTopicRatings memory ratings = peerRatingContract.getUserTopicRating(user, topicId);

        // If no ratings received, return 0
        if (ratings.totalRatings == 0) {
            return 0;
        }

        // Base score is the average peer rating (0-1000)
        uint256 baseScore = ratings.averageScore;

        // Apply volume bonus based on number of ratings (credibility increases with more raters)
        // More ratings = more reliable score
        uint256 ratingVolumeBonus = calculateRatingVolumeBonus(ratings.totalRatings);

        // Apply time decay based on last rating time
        uint256 timeDecayFactor = calculateTimeDecay(ratings.lastRatingTime);

        // Combine base score with volume bonus
        // Base score weighted 80%, volume bonus weighted 20%
        uint256 weightedBase = (baseScore * 80) / 100;
        uint256 weightedVolumeBonus = (ratingVolumeBonus * 20) / 100;

        // Apply time decay
        uint256 rawScore = ((weightedBase + weightedVolumeBonus) * timeDecayFactor) / 100;

        // Ensure score is within bounds
        if (rawScore < MIN_SCORE) rawScore = MIN_SCORE;
        if (rawScore > MAX_SCORE) rawScore = MAX_SCORE;

        return uint16(rawScore);
    }

    /*///////////////////////////
        PURE FUNCTIONS
    ///////////////////////////*/

    /**
     * @notice Calculate volume bonus based on total challenges
     * @param totalChallenges Total challenges attempted
     * @return bonus Volume bonus (0-200)
     */
    function calculateVolumeBonus(uint32 totalChallenges) public pure returns (uint256) {
        if (totalChallenges == 0) return 0;

        // Using approximation of square root for gas efficiency
        // sqrt(n) * 10, capped at 200
        uint256 bonus = sqrt(totalChallenges) * 10;
        return bonus > 200 ? 200 : bonus;
    }

    /**
     * @notice Calculate volume bonus based on number of peer ratings received
     * @param totalRatings Total ratings received
     * @return bonus Volume bonus (0-1000) - more ratings = higher credibility
     */
    function calculateRatingVolumeBonus(uint32 totalRatings) public pure returns (uint256) {
        if (totalRatings == 0) return 0;

        // Similar to challenge volume bonus but scaled differently
        // More peer ratings = higher confidence in the score
        // Using sqrt for diminishing returns, scaled to reach 1000 at ~100 ratings
        uint256 bonus = sqrt(totalRatings) * 100;
        return bonus > 1000 ? 1000 : bonus;
    }

    /**
     * @notice Calculate time decay factor based on last activity
     * @param lastActivityTime Timestamp of last activity
     * @return decayFactor Factor from 50-100 (representing 50%-100%)
     */
    function calculateTimeDecay(uint64 lastActivityTime) public view returns (uint256) {
        uint64 timeSinceActivity = uint64(block.timestamp) - lastActivityTime;

        // Recent activity (0-30 days): 100% weight
        if (timeSinceActivity < RECENT_PERIOD) {
            return 100;
        }

        // Mid-term activity (30-60 days): 75% weight
        if (timeSinceActivity < MID_PERIOD) {
            return 75;
        }

        // Old activity (60+ days): 50% weight (minimum to prevent score from going too low)
        return 50;
    }

    /*///////////////////////////
      INTERNAL FUNCTIONS
    ///////////////////////////*/

    /**
     * @notice Integer square root using Babylonian method
     * @param x Input value
     * @return y Square root of x
     */
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;

        uint256 z = (x + 1) / 2;
        uint256 y = x;

        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }

        return y;
    }
}
