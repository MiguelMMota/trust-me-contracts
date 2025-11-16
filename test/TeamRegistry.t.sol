// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TeamRegistry} from "../src/TeamRegistry.sol";

contract TeamRegistryTest is Test {
    TeamRegistry public teamRegistry;

    address public owner = address(1);
    address public alice = address(2);
    address public bob = address(3);
    address public charlie = address(4);
    address public dave = address(5);

    function setUp() public {
        // Deploy TeamRegistry with proxy
        TeamRegistry teamImpl = new TeamRegistry();
        bytes memory initData = abi.encodeWithSelector(TeamRegistry.initialize.selector);
        ERC1967Proxy proxy = new ERC1967Proxy(address(teamImpl), initData);
        teamRegistry = TeamRegistry(address(proxy));
    }

    /*///////////////////////////
      TEAM CREATION TESTS
    ///////////////////////////*/

    function testCreateTeam() public {
        vm.prank(alice);
        uint64 teamId = teamRegistry.createTeam("Engineering Team");

        assertEq(teamId, 1);

        TeamRegistry.Team memory team = teamRegistry.getTeam(teamId);
        assertEq(team.teamId, teamId);
        assertEq(team.name, "Engineering Team");
        assertEq(team.owner, alice);
        assertTrue(team.isActive);
        assertEq(team.createdAt, block.timestamp);
    }

    function testCreateMultipleTeams() public {
        vm.prank(alice);
        uint64 team1 = teamRegistry.createTeam("Team 1");

        vm.prank(bob);
        uint64 team2 = teamRegistry.createTeam("Team 2");

        assertEq(team1, 1);
        assertEq(team2, 2);
    }

    function testCreateTeamEmitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit TeamRegistry.TeamCreated(1, "Engineering Team", alice, uint64(block.timestamp));
        teamRegistry.createTeam("Engineering Team");
    }

    function testCreateTeamWithEmptyName() public {
        vm.prank(alice);
        vm.expectRevert(TeamRegistry.TeamRegistry__InvalidTeamName.selector);
        teamRegistry.createTeam("");
    }

    function testCreateTeamWithTooLongName() public {
        vm.prank(alice);
        string memory longName =
            "This is a very long team name that exceeds the maximum allowed length of 100 characters for team names";
        vm.expectRevert(TeamRegistry.TeamRegistry__InvalidTeamName.selector);
        teamRegistry.createTeam(longName);
    }

    function testCreatorIsOwner() public {
        vm.prank(alice);
        uint64 teamId = teamRegistry.createTeam("Team");

        assertTrue(teamRegistry.isTeamOwner(teamId, alice));
        assertTrue(teamRegistry.isTeamAdmin(teamId, alice));
        assertTrue(teamRegistry.isTeamMember(teamId, alice));

        TeamRegistry.TeamMember memory member = teamRegistry.getTeamMember(teamId, alice);
        assertTrue(member.role == TeamRegistry.TeamRole.Owner);
        assertTrue(member.isActive);
    }

    /*///////////////////////////
      MEMBER MANAGEMENT TESTS
    ///////////////////////////*/

    function testAddMember() public {
        vm.prank(alice);
        uint64 teamId = teamRegistry.createTeam("Team");

        vm.prank(alice);
        teamRegistry.addMember(teamId, bob, TeamRegistry.TeamRole.Member);

        assertTrue(teamRegistry.isTeamMember(teamId, bob));
        assertFalse(teamRegistry.isTeamAdmin(teamId, bob));

        TeamRegistry.TeamMember memory member = teamRegistry.getTeamMember(teamId, bob);
        assertTrue(member.role == TeamRegistry.TeamRole.Member);
        assertTrue(member.isActive);
    }

    function testAddAdmin() public {
        vm.prank(alice);
        uint64 teamId = teamRegistry.createTeam("Team");

        vm.prank(alice);
        teamRegistry.addMember(teamId, bob, TeamRegistry.TeamRole.Admin);

        assertTrue(teamRegistry.isTeamMember(teamId, bob));
        assertTrue(teamRegistry.isTeamAdmin(teamId, bob));
        assertFalse(teamRegistry.isTeamOwner(teamId, bob));
    }

    function testAddMemberEmitsEvent() public {
        vm.prank(alice);
        uint64 teamId = teamRegistry.createTeam("Team");

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit TeamRegistry.MemberAdded(teamId, bob, TeamRegistry.TeamRole.Member, uint64(block.timestamp));
        teamRegistry.addMember(teamId, bob, TeamRegistry.TeamRole.Member);
    }

    function testOnlyAdminCanAddMember() public {
        vm.prank(alice);
        uint64 teamId = teamRegistry.createTeam("Team");

        vm.prank(alice);
        teamRegistry.addMember(teamId, bob, TeamRegistry.TeamRole.Member);

        vm.prank(bob);
        vm.expectRevert(TeamRegistry.TeamRegistry__NotTeamAdmin.selector);
        teamRegistry.addMember(teamId, charlie, TeamRegistry.TeamRole.Member);
    }

    function testCannotAddOwnerRole() public {
        vm.prank(alice);
        uint64 teamId = teamRegistry.createTeam("Team");

        vm.prank(alice);
        vm.expectRevert(TeamRegistry.TeamRegistry__InvalidRole.selector);
        teamRegistry.addMember(teamId, bob, TeamRegistry.TeamRole.Owner);
    }

    function testCannotAddNoneRole() public {
        vm.prank(alice);
        uint64 teamId = teamRegistry.createTeam("Team");

        vm.prank(alice);
        vm.expectRevert(TeamRegistry.TeamRegistry__InvalidRole.selector);
        teamRegistry.addMember(teamId, bob, TeamRegistry.TeamRole.None);
    }

    function testCannotAddDuplicateMember() public {
        vm.prank(alice);
        uint64 teamId = teamRegistry.createTeam("Team");

        vm.prank(alice);
        teamRegistry.addMember(teamId, bob, TeamRegistry.TeamRole.Member);

        vm.prank(alice);
        vm.expectRevert(TeamRegistry.TeamRegistry__UserAlreadyMember.selector);
        teamRegistry.addMember(teamId, bob, TeamRegistry.TeamRole.Member);
    }

    function testRemoveMember() public {
        vm.prank(alice);
        uint64 teamId = teamRegistry.createTeam("Team");

        vm.prank(alice);
        teamRegistry.addMember(teamId, bob, TeamRegistry.TeamRole.Member);

        vm.prank(alice);
        teamRegistry.removeMember(teamId, bob);

        assertFalse(teamRegistry.isTeamMember(teamId, bob));

        TeamRegistry.TeamMember memory member = teamRegistry.getTeamMember(teamId, bob);
        assertFalse(member.isActive);
        assertTrue(member.role == TeamRegistry.TeamRole.None);
    }

    function testRemoveMemberEmitsEvent() public {
        vm.prank(alice);
        uint64 teamId = teamRegistry.createTeam("Team");

        vm.prank(alice);
        teamRegistry.addMember(teamId, bob, TeamRegistry.TeamRole.Member);

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit TeamRegistry.MemberRemoved(teamId, bob, uint64(block.timestamp));
        teamRegistry.removeMember(teamId, bob);
    }

    function testCannotRemoveSelf() public {
        vm.prank(alice);
        uint64 teamId = teamRegistry.createTeam("Team");

        vm.prank(alice);
        vm.expectRevert(TeamRegistry.TeamRegistry__CannotRemoveSelf.selector);
        teamRegistry.removeMember(teamId, alice);
    }

    function testCannotRemoveOwner() public {
        vm.prank(alice);
        uint64 teamId = teamRegistry.createTeam("Team");

        vm.prank(alice);
        teamRegistry.addMember(teamId, bob, TeamRegistry.TeamRole.Admin);

        vm.prank(bob);
        vm.expectRevert(TeamRegistry.TeamRegistry__CannotRemoveOwner.selector);
        teamRegistry.removeMember(teamId, alice);
    }

    function testReactivateMember() public {
        vm.prank(alice);
        uint64 teamId = teamRegistry.createTeam("Team");

        vm.prank(alice);
        teamRegistry.addMember(teamId, bob, TeamRegistry.TeamRole.Member);

        vm.prank(alice);
        teamRegistry.removeMember(teamId, bob);

        assertFalse(teamRegistry.isTeamMember(teamId, bob));

        vm.prank(alice);
        teamRegistry.addMember(teamId, bob, TeamRegistry.TeamRole.Admin);

        assertTrue(teamRegistry.isTeamMember(teamId, bob));
        assertTrue(teamRegistry.isTeamAdmin(teamId, bob));
    }

    /*///////////////////////////
      ROLE MANAGEMENT TESTS
    ///////////////////////////*/

    function testChangeMemberRole() public {
        vm.prank(alice);
        uint64 teamId = teamRegistry.createTeam("Team");

        vm.prank(alice);
        teamRegistry.addMember(teamId, bob, TeamRegistry.TeamRole.Member);

        vm.prank(alice);
        teamRegistry.changeMemberRole(teamId, bob, TeamRegistry.TeamRole.Admin);

        assertTrue(teamRegistry.isTeamAdmin(teamId, bob));
    }

    function testChangeMemberRoleEmitsEvent() public {
        vm.prank(alice);
        uint64 teamId = teamRegistry.createTeam("Team");

        vm.prank(alice);
        teamRegistry.addMember(teamId, bob, TeamRegistry.TeamRole.Member);

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit TeamRegistry.MemberRoleChanged(teamId, bob, TeamRegistry.TeamRole.Member, TeamRegistry.TeamRole.Admin);
        teamRegistry.changeMemberRole(teamId, bob, TeamRegistry.TeamRole.Admin);
    }

    function testOnlyOwnerCanChangeRole() public {
        vm.prank(alice);
        uint64 teamId = teamRegistry.createTeam("Team");

        vm.prank(alice);
        teamRegistry.addMember(teamId, bob, TeamRegistry.TeamRole.Admin);

        vm.prank(alice);
        teamRegistry.addMember(teamId, charlie, TeamRegistry.TeamRole.Member);

        vm.prank(bob);
        vm.expectRevert(TeamRegistry.TeamRegistry__NotTeamOwner.selector);
        teamRegistry.changeMemberRole(teamId, charlie, TeamRegistry.TeamRole.Admin);
    }

    function testCannotChangeToOwnerRole() public {
        vm.prank(alice);
        uint64 teamId = teamRegistry.createTeam("Team");

        vm.prank(alice);
        teamRegistry.addMember(teamId, bob, TeamRegistry.TeamRole.Member);

        vm.prank(alice);
        vm.expectRevert(TeamRegistry.TeamRegistry__InvalidRole.selector);
        teamRegistry.changeMemberRole(teamId, bob, TeamRegistry.TeamRole.Owner);
    }

    /*///////////////////////////
      OWNERSHIP TRANSFER TESTS
    ///////////////////////////*/

    function testTransferOwnership() public {
        vm.prank(alice);
        uint64 teamId = teamRegistry.createTeam("Team");

        vm.prank(alice);
        teamRegistry.addMember(teamId, bob, TeamRegistry.TeamRole.Member);

        vm.prank(alice);
        teamRegistry.transferTeamOwnership(teamId, bob);

        assertTrue(teamRegistry.isTeamOwner(teamId, bob));
        assertFalse(teamRegistry.isTeamOwner(teamId, alice));
        assertTrue(teamRegistry.isTeamAdmin(teamId, alice)); // Previous owner becomes admin
    }

    function testTransferOwnershipEmitsEvent() public {
        vm.prank(alice);
        uint64 teamId = teamRegistry.createTeam("Team");

        vm.prank(alice);
        vm.expectEmit(true, true, true, false);
        emit TeamRegistry.OwnershipTransferred(teamId, alice, bob);
        teamRegistry.transferTeamOwnership(teamId, bob);
    }

    function testTransferOwnershipToNonMember() public {
        vm.prank(alice);
        uint64 teamId = teamRegistry.createTeam("Team");

        vm.prank(alice);
        teamRegistry.transferTeamOwnership(teamId, bob);

        assertTrue(teamRegistry.isTeamOwner(teamId, bob));
        assertTrue(teamRegistry.isTeamMember(teamId, bob));
    }

    function testOnlyOwnerCanTransferOwnership() public {
        vm.prank(alice);
        uint64 teamId = teamRegistry.createTeam("Team");

        vm.prank(alice);
        teamRegistry.addMember(teamId, bob, TeamRegistry.TeamRole.Admin);

        vm.prank(bob);
        vm.expectRevert(TeamRegistry.TeamRegistry__NotTeamOwner.selector);
        teamRegistry.transferTeamOwnership(teamId, charlie);
    }

    /*///////////////////////////
      TEAM STATUS TESTS
    ///////////////////////////*/

    function testDeactivateTeam() public {
        vm.prank(alice);
        uint64 teamId = teamRegistry.createTeam("Team");

        vm.prank(alice);
        teamRegistry.deactivateTeam(teamId);

        TeamRegistry.Team memory team = teamRegistry.getTeam(teamId);
        assertFalse(team.isActive);
    }

    function testDeactivateTeamEmitsEvent() public {
        vm.prank(alice);
        uint64 teamId = teamRegistry.createTeam("Team");

        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit TeamRegistry.TeamDeactivated(teamId, uint64(block.timestamp));
        teamRegistry.deactivateTeam(teamId);
    }

    function testReactivateTeam() public {
        vm.prank(alice);
        uint64 teamId = teamRegistry.createTeam("Team");

        vm.prank(alice);
        teamRegistry.deactivateTeam(teamId);

        vm.prank(alice);
        teamRegistry.reactivateTeam(teamId);

        TeamRegistry.Team memory team = teamRegistry.getTeam(teamId);
        assertTrue(team.isActive);
    }

    function testReactivateTeamEmitsEvent() public {
        vm.prank(alice);
        uint64 teamId = teamRegistry.createTeam("Team");

        vm.prank(alice);
        teamRegistry.deactivateTeam(teamId);

        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit TeamRegistry.TeamReactivated(teamId, uint64(block.timestamp));
        teamRegistry.reactivateTeam(teamId);
    }

    function testOnlyOwnerCanDeactivateTeam() public {
        vm.prank(alice);
        uint64 teamId = teamRegistry.createTeam("Team");

        vm.prank(alice);
        teamRegistry.addMember(teamId, bob, TeamRegistry.TeamRole.Admin);

        vm.prank(bob);
        vm.expectRevert(TeamRegistry.TeamRegistry__NotTeamOwner.selector);
        teamRegistry.deactivateTeam(teamId);
    }

    /*///////////////////////////
      VIEW FUNCTION TESTS
    ///////////////////////////*/

    function testGetUserTeams() public {
        vm.prank(alice);
        uint64 team1 = teamRegistry.createTeam("Team 1");

        vm.prank(bob);
        uint64 team2 = teamRegistry.createTeam("Team 2");

        vm.prank(bob); // Bob adds alice to his team
        teamRegistry.addMember(team2, alice, TeamRegistry.TeamRole.Member);

        uint64[] memory aliceTeams = teamRegistry.getUserTeams(alice);
        assertEq(aliceTeams.length, 2);
        assertEq(aliceTeams[0], team1);
        assertEq(aliceTeams[1], team2);
    }

    function testGetTeamMembers() public {
        vm.prank(alice);
        uint64 teamId = teamRegistry.createTeam("Team");

        vm.prank(alice);
        teamRegistry.addMember(teamId, bob, TeamRegistry.TeamRole.Member);

        vm.prank(alice);
        teamRegistry.addMember(teamId, charlie, TeamRegistry.TeamRole.Admin);

        address[] memory members = teamRegistry.getTeamMembers(teamId);
        assertEq(members.length, 3);
        assertEq(members[0], alice);
        assertEq(members[1], bob);
        assertEq(members[2], charlie);
    }

    function testGetTeamRole() public {
        vm.prank(alice);
        uint64 teamId = teamRegistry.createTeam("Team");

        vm.prank(alice);
        teamRegistry.addMember(teamId, bob, TeamRegistry.TeamRole.Member);

        vm.prank(alice);
        teamRegistry.addMember(teamId, charlie, TeamRegistry.TeamRole.Admin);

        assertEq(uint256(teamRegistry.getTeamRole(teamId, alice)), uint256(TeamRegistry.TeamRole.Owner));
        assertEq(uint256(teamRegistry.getTeamRole(teamId, bob)), uint256(TeamRegistry.TeamRole.Member));
        assertEq(uint256(teamRegistry.getTeamRole(teamId, charlie)), uint256(TeamRegistry.TeamRole.Admin));
        assertEq(uint256(teamRegistry.getTeamRole(teamId, dave)), uint256(TeamRegistry.TeamRole.None));
    }

    function testGetTeamIdCounter() public {
        vm.prank(alice);
        teamRegistry.createTeam("Team 1");

        vm.prank(bob);
        teamRegistry.createTeam("Team 2");

        assertEq(teamRegistry.getTeamIdCounter(), 3); // Next available ID
    }
}
