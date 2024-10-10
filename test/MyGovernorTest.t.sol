// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import {Test} from "forge-std/Test.sol";
// import {MyGovernor} from "../src/MyGovernor.sol";
// import {Box} from "../src/Box.sol";
// import {TimeLock} from "../src/TimeLock.sol";
// import {GovToken} from "../src/GovToken.sol";

// contract MyGovernorTest is Test {
//     MyGovernor myGovernor;
//     GovToken govToken;
//     TimeLock timelock;
//     Box box;

//     address public USER = makeAddr("USER");
//     uint256 public constant INITIAL_SUPPLY = 100 ether;

//     address[] proposers;
//     address[] executors;

//     uint256 public constant MIN_DELAY = 3600; // 1 hour after a vote passes

//     function setUp() public {
//         govToken = new GovToken();
//         govToken.mint(USER, INITIAL_SUPPLY);

//         vm.startPrank(USER);
//         govToken.delegate(USER);
//         timelock = new TimeLock(MIN_DELAY, proposers, executors, address(this));
//         myGovernor = new MyGovernor(govToken, timelock);

//         bytes32 proposerRole = timelock.PROPOSER_ROLE();
//         bytes32 executorRole = timelock.EXECUTOR_ROLE();
//         bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();

//         timelock.grantRole(proposerRole, address(myGovernor));
//         timelock.grantRole(executorRole, address(0));
//         timelock.revokeRole(adminRole, address(this));

//         vm.stopPrank();

//         box = new Box();
//         box.transferOwnership(address(timelock));
//     }

//     function testCantUpdateBoxWithoutGovernance() public {
//         vm.expectRevert();
//         box.store(1);
//     }
// }

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {MyGovernor} from "../src/MyGovernor.sol";
import {GovToken} from "../src/GovToken.sol";
import {TimeLock} from "../src/TimeLock.sol";
import {Box} from "../src/Box.sol";

contract MyGovernorTest is Test {
    GovToken token;
    TimeLock timelock;
    MyGovernor governor;
    Box box;

    uint256 public constant MIN_DELAY = 3600; // 1 hour - after a vote passes, you have 1 hour before you can enact
    uint256 public constant QUORUM_PERCENTAGE = 4; // Need 4% of voters to pass
    uint256 public constant VOTING_PERIOD = 50400; // This is how long voting lasts
    uint256 public constant VOTING_DELAY = 1; // How many blocks till a proposal vote becomes active

    address[] proposers;
    address[] executors;

    bytes[] functionCalls;
    address[] addressesToCall;
    uint256[] values;

    address public constant VOTER = address(1);

    function setUp() public {
        // Step 1: Deploy GovToken, TimeLock, MyGovernor, and Box
        token = new GovToken();
        token.mint(VOTER, 100e18); // Mint some tokens to VOTER

        // Step 2: Delegate voting power
        vm.prank(VOTER);
        token.delegate(VOTER);

        // Step 3: Deploy the TimeLock and Governor contracts
        timelock = new TimeLock(MIN_DELAY, proposers, executors);
        governor = new MyGovernor(token, timelock);

        // Step 4: Grant roles to the governor contract within TimeLock
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();

        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(executorRole, address(0)); // Anyone can execute
        timelock.revokeRole(adminRole, msg.sender); // Remove admin rights from the deployer

        // Step 5: Deploy the Box contract and transfer ownership to TimeLock
        box = new Box(); // The deployer is msg.sender initially
        box.transferOwnership(address(timelock)); // Transfer ownership to TimeLock

        // From now on, any interaction with the `Box` contract must happen through the governance process
    }

    function testCantUpdateBoxWithoutGovernance() public {
        // Ensure the box cannot be updated directly
        vm.expectRevert();
        box.store(1);
    }

    function testGovernanceUpdatesBox() public {
        uint256 valueToStore = 777;
        string memory description = "Store 777 in Box";

        // Prepare the function call for governance proposal
        bytes memory encodedFunctionCall = abi.encodeWithSignature("store(uint256)", valueToStore);
        addressesToCall.push(address(box));
        values.push(0); // No ETH value required for this call
        functionCalls.push(encodedFunctionCall);

        // 1. Propose to the DAO
        uint256 proposalId = governor.propose(addressesToCall, values, functionCalls, description);

        // Log the proposal state
        console.log("Proposal State:", uint256(governor.state(proposalId)));

        // 2. Wait for the voting delay
        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.roll(block.number + VOTING_DELAY + 1);

        // Log the proposal state after the voting delay
        console.log("Proposal State after voting delay:", uint256(governor.state(proposalId)));

        // 3. Vote on the proposal
        string memory reason = "I like this proposal"; // Voting reason
        uint8 voteWay = 1; // Vote 'For'

        // Use VOTER account to cast the vote
        vm.prank(VOTER);
        governor.castVoteWithReason(proposalId, voteWay, reason);

        // Wait for the voting period to pass
        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        // Log the proposal state after the voting period
        console.log("Proposal State after voting period:", uint256(governor.state(proposalId)));

        // 4. Queue the proposal in the TimeLock
        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        governor.queue(addressesToCall, values, functionCalls, descriptionHash);

        // Fast-forward the blockchain to pass the minimum delay for execution
        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.roll(block.number + MIN_DELAY + 1);

        // 5. Execute the proposal to update the Box value
        governor.execute(addressesToCall, values, functionCalls, descriptionHash);

        // Assert that the Box value has been updated correctly
        assert(box.getNumber() == valueToStore);
    }
}
