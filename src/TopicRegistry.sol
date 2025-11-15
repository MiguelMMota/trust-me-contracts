// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {TeamRegistry} from "./TeamRegistry.sol";

/**
 * @title TopicRegistry
 * @notice Manages hierarchical topic taxonomy for expertise tracking
 * @dev Topics can have parent-child relationships (e.g., Tech -> Software -> Backend -> Python)
 */
contract TopicRegistry is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    /*///////////////////////////
           ERRORS
    ///////////////////////////*/

    error TopicNotFound();
    error TopicAlreadyExists();
    error InvalidParentTopic();
    error TopicNameEmpty();
    error TeamRegistryNotSet();
    error NotTeamAdmin();
    error TeamTopicNotFound();
    error GlobalTopicId();

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

    struct TeamTopicSettings {
        bool isEnabled; // Whether this topic is enabled for the team
        bool isConfigured; // Whether explicitly configured (false = use default)
    }

    /*///////////////////////////
       STATE VARIABLES
    ///////////////////////////*/

    // Global topic registry (teamId = 0)
    mapping(uint32 => Topic) public topics;
    mapping(uint32 => uint32[]) public childTopics; // parentId => childIds[]
    mapping(string => uint32) public topicNameToId; // name => id (for lookups)
    uint32 public topicCount;

    // Team-specific topics (teamId => topicId => Topic)
    mapping(uint64 => mapping(uint32 => Topic)) private _teamTopics;

    // Topic enablement per team (teamId => topicId => settings)
    mapping(uint64 => mapping(uint32 => TeamTopicSettings)) private _teamTopicSettings;

    // Team-specific child topics (teamId => parentId => childIds[])
    mapping(uint64 => mapping(uint32 => uint32[])) private _teamChildTopics;

    // Counter for team-specific topic IDs (teamId => counter)
    mapping(uint64 => uint32) private _teamTopicCounter;

    // Team-specific topic name to ID mapping (teamId => name => id)
    mapping(uint64 => mapping(string => uint32)) private _teamTopicNameToId;

    // TeamRegistry contract reference
    TeamRegistry private _teamRegistry;

    /*///////////////////////////
           EVENTS
    ///////////////////////////*/

    event TopicCreated(uint32 indexed topicId, string name, uint32 indexed parentId);
    event TopicUpdated(uint32 indexed topicId, string name, bool isActive);
    event TeamTopicCreated(uint64 indexed teamId, uint32 indexed topicId, string name, uint32 indexed parentId);
    event TeamTopicUpdated(uint64 indexed teamId, uint32 indexed topicId, bool isEnabled);
    event TeamRegistrySet(address indexed teamRegistry);

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
     */
    function initialize(address initialOwner) external initializer {
        __Ownable_init(initialOwner);
        topicCount = 0;
    }

    /*///////////////////////////
         MODIFIERS
    ///////////////////////////*/

    modifier onlyTeamAdmin(uint64 teamId) {
        if (address(_teamRegistry) == address(0)) revert TeamRegistryNotSet();
        if (!_teamRegistry.isTeamAdmin(teamId, msg.sender)) revert NotTeamAdmin();
        _;
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
    function createTopic(string calldata name, uint32 parentId) external onlyOwner returns (uint32) {
        if (bytes(name).length == 0) revert TopicNameEmpty();
        if (topicNameToId[name] != 0) revert TopicAlreadyExists();
        if (parentId != 0 && !topics[parentId].isActive) revert InvalidParentTopic();

        topicCount++;
        uint32 newTopicId = topicCount;

        topics[newTopicId] =
            Topic({id: newTopicId, name: name, parentId: parentId, isActive: true, createdAt: uint64(block.timestamp)});

        topicNameToId[name] = newTopicId;

        childTopics[parentId].push(newTopicId);

        emit TopicCreated(newTopicId, name, parentId);
        return newTopicId;
    }

    /**
     * @notice Update topic active status
     * @param topicId Topic ID to update
     * @param isActive New active status
     */
    function setTopicActive(uint32 topicId, bool isActive) external onlyOwner {
        if (topics[topicId].id == 0) revert TopicNotFound();
        topics[topicId].isActive = isActive;
        emit TopicUpdated(topicId, topics[topicId].name, isActive);
    }

    /**
     * @notice Set the TeamRegistry contract address
     * @param teamRegistry Address of the TeamRegistry contract
     */
    function setTeamRegistry(address teamRegistry) external onlyOwner {
        _teamRegistry = TeamRegistry(teamRegistry);
        emit TeamRegistrySet(teamRegistry);
    }

    /**
     * @notice Create a team-specific topic
     * @param teamId The ID of the team
     * @param name Topic name (must be unique within team)
     * @param parentId Parent topic ID (can be global or team-specific)
     * @return topicId The ID of the created topic
     */
    function createTeamTopic(uint64 teamId, string calldata name, uint32 parentId)
        external
        onlyTeamAdmin(teamId)
        returns (uint32)
    {
        if (bytes(name).length == 0) revert TopicNameEmpty();
        if (_teamTopicNameToId[teamId][name] != 0) revert TopicAlreadyExists();

        // Validate parent exists (either in global or team registry)
        if (parentId != 0) {
            bool parentExists = false;

            // Check if parent is a global topic
            if (topics[parentId].id != 0 && topics[parentId].isActive) {
                parentExists = true;
            }
            // Check if parent is a team topic
            else if (_teamTopics[teamId][parentId].id != 0 && _teamTopics[teamId][parentId].isActive) {
                parentExists = true;
            }

            if (!parentExists) revert InvalidParentTopic();
        }

        // Increment team topic counter
        _teamTopicCounter[teamId]++;
        uint32 newTopicId = _teamTopicCounter[teamId];

        // Create the team topic
        _teamTopics[teamId][newTopicId] =
            Topic({id: newTopicId, name: name, parentId: parentId, isActive: true, createdAt: uint64(block.timestamp)});

        _teamTopicNameToId[teamId][name] = newTopicId;
        _teamChildTopics[teamId][parentId].push(newTopicId);

        // Enable by default
        _teamTopicSettings[teamId][newTopicId] = TeamTopicSettings({isEnabled: true, isConfigured: true});

        emit TeamTopicCreated(teamId, newTopicId, name, parentId);
        return newTopicId;
    }

    /**
     * @notice Enable or disable a topic for a team (works for both global and team topics)
     * @param teamId The ID of the team
     * @param topicId The ID of the topic
     * @param isEnabled Whether to enable or disable the topic
     * @dev Disabling a topic cascades to all child topics
     */
    function setTopicEnabledInTeam(uint64 teamId, uint32 topicId, bool isEnabled) external onlyTeamAdmin(teamId) {
        // Verify topic exists (either global or team-specific)
        bool topicExists = false;

        if (topics[topicId].id != 0) {
            topicExists = true; // Global topic
        } else if (_teamTopics[teamId][topicId].id != 0) {
            topicExists = true; // Team topic
        }

        if (!topicExists) revert TopicNotFound();

        // Set the topic enablement
        _teamTopicSettings[teamId][topicId] = TeamTopicSettings({isEnabled: isEnabled, isConfigured: true});

        emit TeamTopicUpdated(teamId, topicId, isEnabled);

        // Cascade to children if disabling
        if (!isEnabled) {
            _disableChildTopicsInTeam(teamId, topicId);
        }
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

    /**
     * @notice Get a team-specific topic
     * @param teamId The ID of the team
     * @param topicId The ID of the topic
     * @return topic The topic struct
     */
    function getTeamTopic(uint64 teamId, uint32 topicId) external view returns (Topic memory topic) {
        if (_teamTopics[teamId][topicId].id == 0) revert TeamTopicNotFound();
        return _teamTopics[teamId][topicId];
    }

    /**
     * @notice Get topic in team context (global or team-specific)
     * @param teamId The ID of the team
     * @param topicId The ID of the topic
     * @return topic The topic struct
     */
    function getTopicInTeamContext(uint64 teamId, uint32 topicId) external view returns (Topic memory topic) {
        // First check if it's a team topic
        if (_teamTopics[teamId][topicId].id != 0) {
            return _teamTopics[teamId][topicId];
        }
        // Otherwise, return global topic
        if (topics[topicId].id == 0) revert TopicNotFound();
        return topics[topicId];
    }

    /**
     * @notice Get child topics in team context (includes both global and team-specific)
     * @param teamId The ID of the team (0 for global)
     * @param parentId Parent topic ID
     * @return childIds Array of child topic IDs
     */
    function getTeamChildTopics(uint64 teamId, uint32 parentId) external view returns (uint32[] memory childIds) {
        if (teamId == 0) {
            return childTopics[parentId];
        }

        // For teams, we need to combine global and team-specific children
        uint32[] memory globalChildren = childTopics[parentId];
        uint32[] memory teamChildren = _teamChildTopics[teamId][parentId];

        // Create combined array
        uint32[] memory combined = new uint32[](globalChildren.length + teamChildren.length);
        uint256 index = 0;

        // Add global children
        for (uint256 i = 0; i < globalChildren.length; i++) {
            combined[index] = globalChildren[i];
            index++;
        }

        // Add team children
        for (uint256 i = 0; i < teamChildren.length; i++) {
            combined[index] = teamChildren[i];
            index++;
        }

        return combined;
    }

    /**
     * @notice Check if a topic is enabled for a team
     * @param teamId The ID of the team
     * @param topicId The ID of the topic
     * @return isEnabled True if the topic is enabled for the team
     */
    function isTopicEnabledInTeam(uint64 teamId, uint32 topicId) external view returns (bool isEnabled) {
        TeamTopicSettings memory settings = _teamTopicSettings[teamId][topicId];

        // If not explicitly configured, global topics are enabled by default
        if (!settings.isConfigured) {
            // Check if it's a global topic
            if (topics[topicId].id != 0) {
                return topics[topicId].isActive;
            }
            // Team topics that aren't configured shouldn't exist, but return false
            return false;
        }

        return settings.isEnabled;
    }

    /**
     * @notice Get team topic settings
     * @param teamId The ID of the team
     * @param topicId The ID of the topic
     * @return settings The topic settings for the team
     */
    function getTeamTopicSettings(uint64 teamId, uint32 topicId)
        external
        view
        returns (TeamTopicSettings memory settings)
    {
        return _teamTopicSettings[teamId][topicId];
    }

    /**
     * @notice Get the TeamRegistry contract address
     * @return teamRegistry The TeamRegistry contract address
     */
    function getTeamRegistry() external view returns (address teamRegistry) {
        return address(_teamRegistry);
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

    /*///////////////////////////
      INTERNAL FUNCTIONS
    ///////////////////////////*/

    /**
     * @notice Recursively disable all child topics in a team when a parent is disabled
     * @param teamId The ID of the team
     * @param parentId The ID of the parent topic being disabled
     */
    function _disableChildTopicsInTeam(uint64 teamId, uint32 parentId) internal {
        // Get global children
        uint32[] memory globalChildren = childTopics[parentId];
        for (uint256 i = 0; i < globalChildren.length; i++) {
            uint32 childId = globalChildren[i];
            _teamTopicSettings[teamId][childId] = TeamTopicSettings({isEnabled: false, isConfigured: true});
            emit TeamTopicUpdated(teamId, childId, false);
            _disableChildTopicsInTeam(teamId, childId);
        }

        // Get team-specific children
        uint32[] memory teamChildren = _teamChildTopics[teamId][parentId];
        for (uint256 i = 0; i < teamChildren.length; i++) {
            uint32 childId = teamChildren[i];
            _teamTopicSettings[teamId][childId] = TeamTopicSettings({isEnabled: false, isConfigured: true});
            emit TeamTopicUpdated(teamId, childId, false);
            _disableChildTopicsInTeam(teamId, childId);
        }
    }

    /**
     * @notice Authorize contract upgrade
     * @dev Only owner can upgrade the contract
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
