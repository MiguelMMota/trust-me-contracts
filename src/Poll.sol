// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./User.sol";
import "./ReputationEngine.sol";
import "./TopicRegistry.sol";

/**
 * @title Poll
 * @notice Weighted voting system where vote weight is proportional to expertise
 * @dev Supports multiple-choice polls with expertise-weighted results
 */
contract Poll {
    /*///////////////////////////
           ERRORS
    ///////////////////////////*/

    error Unauthorized();
    error PollNotFound();
    error PollNotActive();
    error PollAlreadyClosed();
    error PollNotEnded();
    error AlreadyVoted();
    error InvalidOption();
    error InvalidTopic();
    error InvalidEndTime();
    error TooFewOptions();
    error TooManyOptions();
    error UserNotRegistered();

    /*///////////////////////////
      TYPE DECLARATIONS
    ///////////////////////////*/

    enum PollStatus {
        Active,
        Closed,
        Finalized
    }

    struct PollData {
        uint64 id;
        address creator;
        uint32 topicId;
        string question;
        bytes32 questionHash; // For verification
        uint64 createdAt;
        uint64 endTime;
        PollStatus status;
        uint8 optionCount;
        uint32 totalVoters;
    }

    struct PollOption {
        uint8 optionId;
        string optionText;
        uint256 totalWeight;    // Sum of all weighted votes for this option
        uint32 voteCount;       // Number of votes (unweighted count)
    }

    struct Vote {
        address voter;
        uint64 pollId;
        uint8 selectedOption;
        uint256 weight;         // Voter's expertise score at time of vote
        uint64 votedAt;
    }

    struct PollResults {
        uint64 pollId;
        uint8 winningOption;
        uint256 totalWeight;
        uint256[] optionWeights;
        uint32[] optionVoteCounts;
    }

    /*///////////////////////////
       STATE VARIABLES
    ///////////////////////////*/

    mapping(uint64 => PollData) public polls;
    mapping(uint64 => mapping(uint8 => PollOption)) public pollOptions; // pollId => optionId => option
    mapping(uint64 => mapping(address => Vote)) public votes; // pollId => voter => vote
    mapping(address => uint64[]) public userPolls; // user => pollIds they created
    mapping(address => uint64[]) public userVotes; // user => pollIds they voted on
    mapping(uint32 => uint64[]) public topicPolls; // topicId => pollIds

    uint64 public pollCount;

    User public immutable userContract;
    ReputationEngine public immutable reputationEngine;
    TopicRegistry public immutable topicRegistry;

    /*///////////////////////////
           EVENTS
    ///////////////////////////*/

    event PollCreated(
        uint64 indexed pollId,
        address indexed creator,
        uint32 indexed topicId,
        string question,
        uint64 endTime
    );
    event VoteCast(
        uint64 indexed pollId,
        address indexed voter,
        uint8 optionId,
        uint256 weight
    );
    event PollClosed(uint64 indexed pollId);
    event PollFinalized(uint64 indexed pollId, uint8 winningOption);

    /*///////////////////////////
         CONSTRUCTOR
    ///////////////////////////*/

    constructor(
        address _userContract,
        address _reputationEngine,
        address _topicRegistry
    ) {
        userContract = User(_userContract);
        reputationEngine = ReputationEngine(_reputationEngine);
        topicRegistry = TopicRegistry(_topicRegistry);
        pollCount = 0;
    }

    /*///////////////////////////
      EXTERNAL FUNCTIONS
    ///////////////////////////*/

    /**
     * @notice Create a new poll
     * @param topicId Topic ID for expertise weighting
     * @param question Poll question
     * @param options Array of option texts (2-10 options)
     * @param durationInDays Poll duration in days
     * @return pollId The ID of the created poll
     */
    function createPoll(
        uint32 topicId,
        string calldata question,
        string[] calldata options,
        uint64 durationInDays
    ) external returns (uint64) {
        if (!userContract.isRegistered(msg.sender)) revert UserNotRegistered();
        if (options.length < 2) revert TooFewOptions();
        if (options.length > 10) revert TooManyOptions();
        if (durationInDays == 0) revert InvalidEndTime();

        // Verify topic exists
        TopicRegistry.Topic memory topic = topicRegistry.getTopic(topicId);
        if (!topic.isActive) revert InvalidTopic();

        pollCount++;
        uint64 newPollId = pollCount;
        uint64 endTime = uint64(block.timestamp) + (durationInDays * 1 days);

        polls[newPollId] = PollData({
            id: newPollId,
            creator: msg.sender,
            topicId: topicId,
            question: question,
            questionHash: keccak256(abi.encodePacked(question)),
            createdAt: uint64(block.timestamp),
            endTime: endTime,
            status: PollStatus.Active,
            optionCount: uint8(options.length),
            totalVoters: 0
        });

        // Create poll options
        for (uint8 i = 0; i < options.length; i++) {
            pollOptions[newPollId][i] = PollOption({
                optionId: i,
                optionText: options[i],
                totalWeight: 0,
                voteCount: 0
            });
        }

        userPolls[msg.sender].push(newPollId);
        topicPolls[topicId].push(newPollId);

        emit PollCreated(newPollId, msg.sender, topicId, question, endTime);
        return newPollId;
    }

    /**
     * @notice Cast a vote on a poll
     * @param pollId Poll ID
     * @param optionId Selected option ID (0-based index)
     */
    function vote(uint64 pollId, uint8 optionId) external {
        PollData storage poll = polls[pollId];

        if (poll.id == 0) revert PollNotFound();
        if (poll.status != PollStatus.Active) revert PollNotActive();
        if (block.timestamp >= poll.endTime) revert PollNotActive();
        if (!userContract.isRegistered(msg.sender)) revert UserNotRegistered();
        if (votes[pollId][msg.sender].votedAt != 0) revert AlreadyVoted();
        if (optionId >= poll.optionCount) revert InvalidOption();

        // Get voter's expertise weight in this topic
        uint256 voterWeight = reputationEngine.getVotingWeight(msg.sender, poll.topicId);

        // Record vote
        votes[pollId][msg.sender] = Vote({
            voter: msg.sender,
            pollId: pollId,
            selectedOption: optionId,
            weight: voterWeight,
            votedAt: uint64(block.timestamp)
        });

        // Update option totals
        pollOptions[pollId][optionId].totalWeight += voterWeight;
        pollOptions[pollId][optionId].voteCount++;

        // Update poll stats
        poll.totalVoters++;

        userVotes[msg.sender].push(pollId);

        emit VoteCast(pollId, msg.sender, optionId, voterWeight);
    }

    /**
     * @notice Close a poll (can be called after end time or by creator)
     * @param pollId Poll ID
     */
    function closePoll(uint64 pollId) external {
        PollData storage poll = polls[pollId];

        if (poll.id == 0) revert PollNotFound();
        if (poll.status != PollStatus.Active) revert PollAlreadyClosed();

        // Only creator can close early, anyone can close after end time
        if (block.timestamp < poll.endTime && msg.sender != poll.creator) {
            revert Unauthorized();
        }

        poll.status = PollStatus.Closed;
        emit PollClosed(pollId);
    }

    /**
     * @notice Finalize poll results
     * @param pollId Poll ID
     */
    function finalizePoll(uint64 pollId) external {
        PollData storage poll = polls[pollId];

        if (poll.id == 0) revert PollNotFound();
        if (poll.status != PollStatus.Closed) revert PollNotActive();

        // Determine winning option (highest total weight)
        uint8 winningOption = 0;
        uint256 maxWeight = 0;

        for (uint8 i = 0; i < poll.optionCount; i++) {
            if (pollOptions[pollId][i].totalWeight > maxWeight) {
                maxWeight = pollOptions[pollId][i].totalWeight;
                winningOption = i;
            }
        }

        poll.status = PollStatus.Finalized;
        emit PollFinalized(pollId, winningOption);
    }

    /*///////////////////////////
        VIEW FUNCTIONS
    ///////////////////////////*/

    /**
     * @notice Get poll data
     * @param pollId Poll ID
     * @return PollData struct
     */
    function getPoll(uint64 pollId) external view returns (PollData memory) {
        if (polls[pollId].id == 0) revert PollNotFound();
        return polls[pollId];
    }

    /**
     * @notice Get poll option
     * @param pollId Poll ID
     * @param optionId Option ID
     * @return PollOption struct
     */
    function getPollOption(uint64 pollId, uint8 optionId) external view returns (PollOption memory) {
        return pollOptions[pollId][optionId];
    }

    /**
     * @notice Get all options for a poll
     * @param pollId Poll ID
     * @return Array of PollOption structs
     */
    function getPollOptions(uint64 pollId) external view returns (PollOption[] memory) {
        PollData memory poll = polls[pollId];
        if (poll.id == 0) revert PollNotFound();

        PollOption[] memory options = new PollOption[](poll.optionCount);
        for (uint8 i = 0; i < poll.optionCount; i++) {
            options[i] = pollOptions[pollId][i];
        }
        return options;
    }

    /**
     * @notice Get user's vote on a poll
     * @param pollId Poll ID
     * @param voter Voter address
     * @return Vote struct (votedAt = 0 if not voted)
     */
    function getUserVote(uint64 pollId, address voter) external view returns (Vote memory) {
        return votes[pollId][voter];
    }

    /**
     * @notice Get poll results
     * @param pollId Poll ID
     * @return PollResults struct
     */
    function getPollResults(uint64 pollId) external view returns (PollResults memory) {
        PollData memory poll = polls[pollId];
        if (poll.id == 0) revert PollNotFound();

        uint256[] memory optionWeights = new uint256[](poll.optionCount);
        uint32[] memory optionVoteCounts = new uint32[](poll.optionCount);
        uint256 totalWeight = 0;
        uint8 winningOption = 0;
        uint256 maxWeight = 0;

        for (uint8 i = 0; i < poll.optionCount; i++) {
            PollOption memory option = pollOptions[pollId][i];
            optionWeights[i] = option.totalWeight;
            optionVoteCounts[i] = option.voteCount;
            totalWeight += option.totalWeight;

            if (option.totalWeight > maxWeight) {
                maxWeight = option.totalWeight;
                winningOption = i;
            }
        }

        return PollResults({
            pollId: pollId,
            winningOption: winningOption,
            totalWeight: totalWeight,
            optionWeights: optionWeights,
            optionVoteCounts: optionVoteCounts
        });
    }

    /**
     * @notice Get polls created by a user
     * @param user User address
     * @return Array of poll IDs
     */
    function getUserCreatedPolls(address user) external view returns (uint64[] memory) {
        return userPolls[user];
    }

    /**
     * @notice Get polls a user has voted on
     * @param user User address
     * @return Array of poll IDs
     */
    function getUserVotedPolls(address user) external view returns (uint64[] memory) {
        return userVotes[user];
    }

    /**
     * @notice Get all polls for a topic
     * @param topicId Topic ID
     * @return Array of poll IDs
     */
    function getTopicPolls(uint32 topicId) external view returns (uint64[] memory) {
        return topicPolls[topicId];
    }

    /**
     * @notice Check if poll is still active
     * @param pollId Poll ID
     * @return true if active and not expired
     */
    function isPollActive(uint64 pollId) external view returns (bool) {
        PollData memory poll = polls[pollId];
        return poll.status == PollStatus.Active && block.timestamp < poll.endTime;
    }

    /**
     * @notice Get percentage distribution of weighted votes
     * @param pollId Poll ID
     * @return Array of percentages (in basis points, 10000 = 100%)
     */
    function getWeightedPercentages(uint64 pollId) external view returns (uint256[] memory) {
        PollData memory poll = polls[pollId];
        if (poll.id == 0) revert PollNotFound();

        uint256[] memory percentages = new uint256[](poll.optionCount);
        uint256 totalWeight = 0;

        // Calculate total weight
        for (uint8 i = 0; i < poll.optionCount; i++) {
            totalWeight += pollOptions[pollId][i].totalWeight;
        }

        // Calculate percentages
        if (totalWeight == 0) {
            return percentages; // All zeros
        }

        for (uint8 i = 0; i < poll.optionCount; i++) {
            percentages[i] = (pollOptions[pollId][i].totalWeight * 10000) / totalWeight;
        }

        return percentages;
    }
}
