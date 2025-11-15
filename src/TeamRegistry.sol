// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title TeamRegistry
 * @notice Manages team creation, membership, and access control for the reputation system
 * @dev Supports role-based access control with Owner, Admin, and Member roles
 *      Teams provide isolated contexts for reputation, ratings, and polls
 */
contract TeamRegistry is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    /*//////////////////////////
           ERRORS
    //////////////////////////*/

    error TeamRegistry__TeamDoesNotExist();
    error TeamRegistry__TeamAlreadyExists();
    error TeamRegistry__TeamInactive();
    error TeamRegistry__NotTeamOwner();
    error TeamRegistry__NotTeamAdmin();
    error TeamRegistry__NotTeamMember();
    error TeamRegistry__UserAlreadyMember();
    error TeamRegistry__UserNotMember();
    error TeamRegistry__CannotRemoveOwner();
    error TeamRegistry__InvalidRole();
    error TeamRegistry__InvalidTeamName();
    error TeamRegistry__CannotRemoveSelf();

    /*//////////////////////////
      TYPE DECLARATIONS
    //////////////////////////*/

    enum TeamRole {
        None, // 0: Not a member
        Member, // 1: Regular member
        Admin, // 2: Can manage members
        Owner // 3: Full control

    }

    struct Team {
        uint64 teamId;
        string name;
        address owner;
        uint64 createdAt;
        bool isActive;
    }

    struct TeamMember {
        TeamRole role;
        uint64 joinedAt;
        bool isActive; // For soft deletes
    }

    /*//////////////////////////
       STATE VARIABLES
    //////////////////////////*/

    // Team counter for unique IDs (0 reserved for global system)
    uint64 private _teamIdCounter;

    // Team data: teamId => Team
    mapping(uint64 => Team) private _teams;

    // Team membership: teamId => user => TeamMember
    mapping(uint64 => mapping(address => TeamMember)) private _teamMembers;

    // User's teams: user => teamId[]
    mapping(address => uint64[]) private _userTeams;

    // Team members list: teamId => address[]
    mapping(uint64 => address[]) private _teamMembersList;

    /*//////////////////////////
           EVENTS
    //////////////////////////*/

    event TeamCreated(uint64 indexed teamId, string name, address indexed owner, uint64 createdAt);
    event TeamDeactivated(uint64 indexed teamId, uint64 deactivatedAt);
    event TeamReactivated(uint64 indexed teamId, uint64 reactivatedAt);
    event MemberAdded(uint64 indexed teamId, address indexed member, TeamRole role, uint64 joinedAt);
    event MemberRemoved(uint64 indexed teamId, address indexed member, uint64 removedAt);
    event MemberRoleChanged(uint64 indexed teamId, address indexed member, TeamRole oldRole, TeamRole newRole);
    event OwnershipTransferred(uint64 indexed teamId, address indexed previousOwner, address indexed newOwner);

    /*//////////////////////////
         MODIFIERS
    //////////////////////////*/

    modifier teamExists(uint64 teamId) {
        if (_teams[teamId].createdAt == 0) {
            revert TeamRegistry__TeamDoesNotExist();
        }
        _;
    }

    modifier teamActive(uint64 teamId) {
        if (!_teams[teamId].isActive) {
            revert TeamRegistry__TeamInactive();
        }
        _;
    }

    modifier onlyTeamOwner(uint64 teamId) {
        if (_teams[teamId].owner != msg.sender) {
            revert TeamRegistry__NotTeamOwner();
        }
        _;
    }

    modifier onlyTeamAdmin(uint64 teamId) {
        TeamMember memory member = _teamMembers[teamId][msg.sender];
        if (!member.isActive || (member.role != TeamRole.Admin && member.role != TeamRole.Owner)) {
            revert TeamRegistry__NotTeamAdmin();
        }
        _;
    }

    modifier onlyTeamMember(uint64 teamId) {
        TeamMember memory member = _teamMembers[teamId][msg.sender];
        if (!member.isActive || member.role == TeamRole.None) {
            revert TeamRegistry__NotTeamMember();
        }
        _;
    }

    /*//////////////////////////
         CONSTRUCTOR
    //////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*//////////////////////////
         FUNCTIONS
    //////////////////////////*/

    function initialize() public initializer {
        __Ownable_init(msg.sender);
        _teamIdCounter = 1; // Start from 1 (0 reserved for global system)
    }

    /*//////////////////////////
    EXTERNAL FUNCTIONS
    //////////////////////////*/

    /**
     * @notice Creates a new team
     * @param name The name of the team
     * @return teamId The ID of the newly created team
     */
    function createTeam(string calldata name) external returns (uint64 teamId) {
        if (bytes(name).length == 0 || bytes(name).length > 100) {
            revert TeamRegistry__InvalidTeamName();
        }

        teamId = _teamIdCounter++;

        _teams[teamId] =
            Team({teamId: teamId, name: name, owner: msg.sender, createdAt: uint64(block.timestamp), isActive: true});

        // Add creator as owner
        _teamMembers[teamId][msg.sender] =
            TeamMember({role: TeamRole.Owner, joinedAt: uint64(block.timestamp), isActive: true});

        _userTeams[msg.sender].push(teamId);
        _teamMembersList[teamId].push(msg.sender);

        emit TeamCreated(teamId, name, msg.sender, uint64(block.timestamp));
        emit MemberAdded(teamId, msg.sender, TeamRole.Owner, uint64(block.timestamp));
    }

    /**
     * @notice Adds a member to a team
     * @param teamId The ID of the team
     * @param member The address of the member to add
     * @param role The role to assign to the member
     */
    function addMember(uint64 teamId, address member, TeamRole role)
        external
        teamExists(teamId)
        teamActive(teamId)
        onlyTeamAdmin(teamId)
    {
        if (role == TeamRole.None || role == TeamRole.Owner) {
            revert TeamRegistry__InvalidRole();
        }

        TeamMember storage existingMember = _teamMembers[teamId][member];

        // Check if already an active member
        if (existingMember.isActive && existingMember.role != TeamRole.None) {
            revert TeamRegistry__UserAlreadyMember();
        }

        // If member was previously removed, reactivate them
        if (!existingMember.isActive && existingMember.joinedAt > 0) {
            existingMember.isActive = true;
            existingMember.role = role;
        } else {
            // New member
            _teamMembers[teamId][member] = TeamMember({role: role, joinedAt: uint64(block.timestamp), isActive: true});
            _userTeams[member].push(teamId);
            _teamMembersList[teamId].push(member);
        }

        emit MemberAdded(teamId, member, role, uint64(block.timestamp));
    }

    /**
     * @notice Removes a member from a team (soft delete)
     * @param teamId The ID of the team
     * @param member The address of the member to remove
     */
    function removeMember(uint64 teamId, address member) external teamExists(teamId) onlyTeamAdmin(teamId) {
        if (member == msg.sender) {
            revert TeamRegistry__CannotRemoveSelf();
        }

        TeamMember storage teamMember = _teamMembers[teamId][member];

        if (!teamMember.isActive || teamMember.role == TeamRole.None) {
            revert TeamRegistry__UserNotMember();
        }

        if (teamMember.role == TeamRole.Owner) {
            revert TeamRegistry__CannotRemoveOwner();
        }

        teamMember.isActive = false;
        teamMember.role = TeamRole.None;

        emit MemberRemoved(teamId, member, uint64(block.timestamp));
    }

    /**
     * @notice Changes a member's role
     * @param teamId The ID of the team
     * @param member The address of the member
     * @param newRole The new role to assign
     */
    function changeMemberRole(uint64 teamId, address member, TeamRole newRole)
        external
        teamExists(teamId)
        teamActive(teamId)
        onlyTeamOwner(teamId)
    {
        if (newRole == TeamRole.None || newRole == TeamRole.Owner) {
            revert TeamRegistry__InvalidRole();
        }

        TeamMember storage teamMember = _teamMembers[teamId][member];

        if (!teamMember.isActive || teamMember.role == TeamRole.None) {
            revert TeamRegistry__UserNotMember();
        }

        TeamRole oldRole = teamMember.role;
        teamMember.role = newRole;

        emit MemberRoleChanged(teamId, member, oldRole, newRole);
    }

    /**
     * @notice Transfers team ownership to a new owner
     * @param teamId The ID of the team
     * @param newOwner The address of the new owner
     */
    function transferTeamOwnership(uint64 teamId, address newOwner)
        external
        teamExists(teamId)
        teamActive(teamId)
        onlyTeamOwner(teamId)
    {
        address previousOwner = _teams[teamId].owner;
        _teams[teamId].owner = newOwner;

        // Update roles
        _teamMembers[teamId][previousOwner].role = TeamRole.Admin;

        TeamMember storage newOwnerMember = _teamMembers[teamId][newOwner];
        if (!newOwnerMember.isActive || newOwnerMember.role == TeamRole.None) {
            // New owner wasn't a member, add them
            _teamMembers[teamId][newOwner] =
                TeamMember({role: TeamRole.Owner, joinedAt: uint64(block.timestamp), isActive: true});
            _userTeams[newOwner].push(teamId);
            _teamMembersList[teamId].push(newOwner);
        } else {
            newOwnerMember.role = TeamRole.Owner;
        }

        emit OwnershipTransferred(teamId, previousOwner, newOwner);
    }

    /**
     * @notice Deactivates a team
     * @param teamId The ID of the team to deactivate
     */
    function deactivateTeam(uint64 teamId) external teamExists(teamId) onlyTeamOwner(teamId) {
        _teams[teamId].isActive = false;
        emit TeamDeactivated(teamId, uint64(block.timestamp));
    }

    /**
     * @notice Reactivates a team
     * @param teamId The ID of the team to reactivate
     */
    function reactivateTeam(uint64 teamId) external teamExists(teamId) onlyTeamOwner(teamId) {
        _teams[teamId].isActive = true;
        emit TeamReactivated(teamId, uint64(block.timestamp));
    }

    /*//////////////////////////
       VIEW FUNCTIONS
    //////////////////////////*/

    /**
     * @notice Gets team information
     * @param teamId The ID of the team
     * @return team The team struct
     */
    function getTeam(uint64 teamId) external view teamExists(teamId) returns (Team memory team) {
        return _teams[teamId];
    }

    /**
     * @notice Gets a member's information in a team
     * @param teamId The ID of the team
     * @param member The address of the member
     * @return teamMember The team member struct
     */
    function getTeamMember(uint64 teamId, address member)
        external
        view
        teamExists(teamId)
        returns (TeamMember memory teamMember)
    {
        return _teamMembers[teamId][member];
    }

    /**
     * @notice Gets all teams a user belongs to
     * @param user The address of the user
     * @return teamIds Array of team IDs
     */
    function getUserTeams(address user) external view returns (uint64[] memory teamIds) {
        return _userTeams[user];
    }

    /**
     * @notice Gets all members of a team
     * @param teamId The ID of the team
     * @return members Array of member addresses
     */
    function getTeamMembers(uint64 teamId) external view teamExists(teamId) returns (address[] memory members) {
        return _teamMembersList[teamId];
    }

    /**
     * @notice Checks if a user is an active member of a team
     * @param teamId The ID of the team
     * @param user The address to check
     * @return isMember True if the user is an active member
     */
    function isTeamMember(uint64 teamId, address user) external view returns (bool isMember) {
        TeamMember memory member = _teamMembers[teamId][user];
        return member.isActive && member.role != TeamRole.None;
    }

    /**
     * @notice Checks if a user is an admin or owner of a team
     * @param teamId The ID of the team
     * @param user The address to check
     * @return isAdmin True if the user is an admin or owner
     */
    function isTeamAdmin(uint64 teamId, address user) external view returns (bool isAdmin) {
        TeamMember memory member = _teamMembers[teamId][user];
        return member.isActive && (member.role == TeamRole.Admin || member.role == TeamRole.Owner);
    }

    /**
     * @notice Checks if a user is the owner of a team
     * @param teamId The ID of the team
     * @param user The address to check
     * @return isOwner True if the user is the owner
     */
    function isTeamOwner(uint64 teamId, address user) external view returns (bool isOwner) {
        return _teams[teamId].owner == user;
    }

    /**
     * @notice Gets a user's role in a team
     * @param teamId The ID of the team
     * @param user The address to check
     * @return role The user's role
     */
    function getTeamRole(uint64 teamId, address user) external view returns (TeamRole role) {
        return _teamMembers[teamId][user].role;
    }

    /**
     * @notice Gets the current team ID counter
     * @return counter The current counter value
     */
    function getTeamIdCounter() external view returns (uint64 counter) {
        return _teamIdCounter;
    }

    /*//////////////////////////
      INTERNAL FUNCTIONS
    //////////////////////////*/

    /**
     * @notice Authorizes contract upgrades (UUPS pattern)
     * @dev Only the owner can authorize upgrades
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
