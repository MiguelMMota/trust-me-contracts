// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title TopicRegistry
 * @notice Manages hierarchical topic taxonomy for expertise tracking
 * @dev Topics can have parent-child relationships (e.g., Tech -> Software -> Backend -> Python)
 */
contract TopicRegistry {
    /*///////////////////////////
           ERRORS
    ///////////////////////////*/

    error Unauthorized();
    error TopicNotFound();
    error TopicAlreadyExists();
    error InvalidParentTopic();
    error TopicNameEmpty();

    /*///////////////////////////
      TYPE DECLARATIONS
    ///////////////////////////*/

    struct Topic {
        uint32 id;
        string name;
        uint32 parentId; // 0 if root topic
        bool isActive;
        uint64 createdAt;
    }

    /*///////////////////////////
       STATE VARIABLES
    ///////////////////////////*/

    mapping(uint32 => Topic) public topics;
    mapping(uint32 => uint32[]) public childTopics; // parentId => childIds[]
    mapping(string => uint32) public topicNameToId; // name => id (for lookups)
    uint32 public topicCount;
    address public admin;

    /*///////////////////////////
           EVENTS
    ///////////////////////////*/

    event TopicCreated(uint32 indexed topicId, string name, uint32 indexed parentId);
    event TopicUpdated(uint32 indexed topicId, string name, bool isActive);
    event AdminTransferred(address indexed previousAdmin, address indexed newAdmin);

    /*///////////////////////////
         MODIFIERS
    ///////////////////////////*/

    modifier onlyAdmin() {
        if (msg.sender != admin) revert Unauthorized();
        _;
    }

    /*///////////////////////////
         CONSTRUCTOR
    ///////////////////////////*/

    constructor() {
        admin = msg.sender;
        topicCount = 0;
    }

    /*///////////////////////////
      EXTERNAL FUNCTIONS
    ///////////////////////////*/

    /**
     * @notice Create a new topic
     * @param name Topic name (must be unique)
     * @param parentId Parent topic ID (0 for root topics)
     * @return topicId The ID of the created topic
     */
    function createTopic(string calldata name, uint32 parentId) external onlyAdmin returns (uint32) {
        if (bytes(name).length == 0) revert TopicNameEmpty();
        if (topicNameToId[name] != 0) revert TopicAlreadyExists();
        if (parentId != 0 && !topics[parentId].isActive) revert InvalidParentTopic();

        topicCount++;
        uint32 newTopicId = topicCount;

        topics[newTopicId] = Topic({
            id: newTopicId,
            name: name,
            parentId: parentId,
            isActive: true,
            createdAt: uint64(block.timestamp)
        });

        topicNameToId[name] = newTopicId;

        if (parentId != 0) {
            childTopics[parentId].push(newTopicId);
        }

        emit TopicCreated(newTopicId, name, parentId);
        return newTopicId;
    }

    /**
     * @notice Update topic active status
     * @param topicId Topic ID to update
     * @param isActive New active status
     */
    function setTopicActive(uint32 topicId, bool isActive) external onlyAdmin {
        if (topics[topicId].id == 0) revert TopicNotFound();
        topics[topicId].isActive = isActive;
        emit TopicUpdated(topicId, topics[topicId].name, isActive);
    }

    /**
     * @notice Transfer admin rights
     * @param newAdmin New admin address
     */
    function transferAdmin(address newAdmin) external onlyAdmin {
        address previousAdmin = admin;
        admin = newAdmin;
        emit AdminTransferred(previousAdmin, newAdmin);
    }

    /*///////////////////////////
        VIEW FUNCTIONS
    ///////////////////////////*/

    /**
     * @notice Get all child topics of a parent
     * @param parentId Parent topic ID
     * @return Array of child topic IDs
     */
    function getChildTopics(uint32 parentId) external view returns (uint32[] memory) {
        return childTopics[parentId];
    }

    /**
     * @notice Get topic by ID
     * @param topicId Topic ID
     * @return Topic struct
     */
    function getTopic(uint32 topicId) external view returns (Topic memory) {
        if (topics[topicId].id == 0) revert TopicNotFound();
        return topics[topicId];
    }

    /**
     * @notice Get topic ID by name
     * @param name Topic name
     * @return Topic ID (0 if not found)
     */
    function getTopicIdByName(string calldata name) external view returns (uint32) {
        return topicNameToId[name];
    }

    /**
     * @notice Get all root topics (topics with parentId = 0)
     * @return Array of root topic IDs
     */
    function getRootTopics() external view returns (uint32[] memory) {
        return childTopics[0];
    }

    /*///////////////////////////
       PUBLIC FUNCTIONS
    ///////////////////////////*/

    /**
     * @notice Check if a topic is a descendant of another topic
     * @param childId Potential child topic ID
     * @param ancestorId Potential ancestor topic ID
     * @return true if childId is a descendant of ancestorId
     */
    function isDescendant(uint32 childId, uint32 ancestorId) public view returns (bool) {
        if (childId == 0 || ancestorId == 0) return false;

        uint32 currentId = childId;
        uint256 maxDepth = 100; // Prevent infinite loops
        uint256 depth = 0;

        while (currentId != 0 && depth < maxDepth) {
            if (currentId == ancestorId) return true;
            currentId = topics[currentId].parentId;
            depth++;
        }

        return false;
    }
}
