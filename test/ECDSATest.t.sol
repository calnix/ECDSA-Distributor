// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ECDSADistributor} from "../src/ECDSADistributor.sol";

import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

contract ECDSATest is Test {    

    ECDSADistributor public distributor;
    ERC20Mock public token;

    address public userA;
    address public userB;
    address public userC;
    address public owner;
    address public operator;

    uint256 public userATokens;
    uint256 public userBTokens;
    uint256 public userCTokens;
    uint256 public updaterTokens;

    uint256 public deadline;

// --- events
    event Claimed(address indexed user, uint128 indexed round, uint128 amount);
    event ClaimedMultiple(address indexed user, uint128[] indexed rounds, uint128 totalAmount);
    event SetupRounds(uint256 indexed numOfRounds, uint256 indexed totalAmount, uint256 indexed lastClaimTime);
    event AddedRounds(uint256 indexed numOfRounds, uint256 indexed totalAmount, uint256 indexed lastClaimTime);
    event DeadlineUpdated(uint256 newDeadline);
    event Frozen(uint256 indexed timestamp);

// ------------------------------------
    function setUp() public virtual {
    
        // users
        userA = makeAddr("userA");
        userB = makeAddr("userB");
        userC = makeAddr("userC");
        owner = makeAddr("owner");
        operator = makeAddr("operator");

        // values
        userATokens = 20 ether;
        userBTokens = 50 ether;
        userCTokens = 80 ether;
        updaterTokens = (userATokens + userBTokens + userCTokens) * 2;

        deadline = 10;

        // contracts
        token = new ERC20Mock();       
        distributor = new ECDSADistributor();

    }

}