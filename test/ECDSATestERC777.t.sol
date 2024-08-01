// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import "../src/ECDSADistributor.sol";

import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";


import { MockCallbackToken, ERC20Reentrant } from "test/MockCallbackToken.sol";
import { MockAttackContract } from "test/MockAttackContract.sol"; 
 
/**

user -> attack contract -> distributor -> token callback -> attack contract -> distributor,

*/ 

abstract contract StateDeploy is Test {    

    ECDSADistributor public distributor;
    MockCallbackToken public token;
    MockAttackContract public attackerContract;

    // entities
    address public userA;
    address public userB;
    address public userC;
    address public owner;
    address public operator;
    address public storedSigner;
    address public attacker;

    uint256 public storedSignerPrivateKey;

    // token balances
    uint128 public userATokens;
    uint128 public userBTokens;
    uint128 public userCTokens;
    uint128 public operatorTokens;
    uint128 public attackerTokens;

    // round balances
    uint128 totalAmountForAllRounds;
    uint128 totalAmountForRoundOne;
    uint128 totalAmountForRoundTwo;

    // signatures
    bytes public userARound1;
    bytes public userARound2;
    
    bytes public userBRound1;
    bytes public userBRound2;
    
    bytes public userCRound1;
    bytes public userCRound2;

    bytes public attackerRound1;
    bytes public attackerRound2;
    
// --- events
    event Claimed(address indexed user, uint128 indexed round, uint128 amount);
    event ClaimedMultiple(address indexed user, uint128[] indexed rounds, uint128 totalAmount);
    event SetupRounds(uint256 indexed numOfRounds, uint256 indexed firstClaimTime, uint256 indexed lastClaimTime, uint256 totalAmount);
    event AddedRounds(uint256 indexed numOfRounds, uint256 indexed totalAmount, uint256 indexed lastClaimTime);
    event DeadlineUpdated(uint256 indexed newDeadline);
    event Deposited(address indexed operator, uint256 indexed amount);
    event Withdrawn(address indexed operator, uint256 indexed amount);
    event OperatorUpdated(address indexed oldOperator, address indexed newOperator);
    event Frozen(uint256 indexed timestamp);
    event EmergencyExit(address indexed receiver, uint256 indexed balance);

// ------------------------------------
    function setUp() public virtual {
    
        // users
        userA = makeAddr("userA");
        userB = makeAddr("userB");
        userC = makeAddr("userC");
        owner = makeAddr("owner");
        operator = makeAddr("operator");
        attacker = makeAddr("attacker");

        // signer
        (storedSigner, storedSignerPrivateKey) = makeAddrAndKey("storedSigner");

        // tokens
        userATokens = 20 ether; 
        userBTokens = 50 ether;
        userCTokens = 80 ether;
        attackerTokens = 20 ether;
        operatorTokens = (userATokens + userBTokens + userCTokens + attackerTokens);
        
        // rounds
        totalAmountForAllRounds = operatorTokens;
        totalAmountForRoundOne = totalAmountForRoundTwo = totalAmountForAllRounds/2;

        // contracts
        vm.startPrank(owner);
        
        token = new MockCallbackToken();       
        
        string memory name = "TestDistributor";
        string memory version = "v1";
        distributor = new ECDSADistributor(name, version, address(token), storedSigner, owner, operator);

        // attacker contract
        attackerContract = new MockAttackContract(address(distributor));

        // mint tokens
        token.mint(operator, operatorTokens);

        vm.stopPrank();

        // Allowances
        vm.prank(operator);
        token.approve(address(distributor), operatorTokens); 


        // generate signatures
        userARound1 = generateSignature(userA, 0, userATokens/2);
        userARound2 = generateSignature(userA, 1, userATokens/2);

        userBRound1 = generateSignature(userB, 0, userBTokens/2);
        userBRound2 = generateSignature(userB, 1, userBTokens/2);

        userCRound1 = generateSignature(userC, 0, userCTokens/2);
        userCRound2 = generateSignature(userC, 1, userCTokens/2);

        attackerRound1 = generateSignature(address(attackerContract), 0, userATokens/2);
        attackerRound2 = generateSignature(address(attackerContract), 1, userATokens/2);

        // starting point: T0
        vm.warp(30 days);        
    }

    function generateSignature(address user, uint128 round, uint128 amount) public returns (bytes memory) {
        
        bytes32 digest = distributor.hashTypedDataV4(keccak256(abi.encode(keccak256("Claim(address user,uint128 round,uint128 amount)"), user, round, amount)));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(storedSignerPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        return signature;
    }

}

//Note: Owner set ups rounnds on distributor contract
//      t = 31 days
abstract contract StateSetup is StateDeploy {

    function setUp() public override virtual {
        super.setUp();

        vm.warp(30 days + 1 days);        

        uint128[] memory startTimes = new uint128[](2);
            startTimes[0] = (30 days + 2 days);
            startTimes[1] = (30 days + 3 days);

        uint128[] memory allocations = new uint128[](2);
            allocations[0] = totalAmountForRoundOne;
            allocations[1] = totalAmountForRoundTwo;
        
        vm.prank(owner);
        distributor.setupRounds(startTimes, allocations);
    }
}

abstract contract StateDeposited is StateSetup {

    function setUp() public override virtual {
        super.setUp();

        uint256[] memory rounds = new uint256[](2);
            rounds[0] = 0;
            rounds[1] = 1;

        // for all rounds
        uint256 totalAmount = userATokens + userBTokens + userCTokens;

        vm.prank(operator);
        distributor.deposit(rounds);
    }
}

//      t = 31 days
abstract contract StateRoundOne is StateDeposited {

    function setUp() public override virtual {
        super.setUp();

        // forward to first round claim time
        vm.warp(30 days + 2 days);

        vm.prank(userA);
        distributor.claim(0, userATokens/2, userARound1);
    }
}

//  t = 33 days
abstract contract StateRoundTwo is StateRoundOne {

    function setUp() public override virtual {
        super.setUp();

        // forward to second round claim time
        vm.warp(30 days + 3 days);
    }
}


contract StateAttackerTest is StateRoundTwo {

    function testAttackerCannotClaimTwice() public {

        // setup reentry
        ERC20Reentrant.Type when = ERC20Reentrant.Type.After;
        address target = address(attackerContract);

        uint128 round = 0;
        uint128 amount = attackerTokens/2; 
        bytes memory signature = attackerRound1;

        bytes memory data = abi.encodeWithSignature("claim(uint128,uint128,bytes)", round, amount, signature);

        token.scheduleReenter(when, target, data);

        // call w/ reentry
        vm.expectRevert(abi.encodeWithSelector(ECDSADistributor.UserHasClaimed.selector));

        vm.prank(attacker);
        attackerContract.claim(round, amount, signature);
    }

    function testAttackerCannotClaimMultipleTwice() public {

        // setup reentry
        ERC20Reentrant.Type when = ERC20Reentrant.Type.After;
        address target = address(attackerContract);

         uint128[] memory rounds = new uint128[](2);
            rounds[0] = 0;
            rounds[1] = 1;

        uint128[] memory amounts = new uint128[](2);
            amounts[0] = attackerTokens/2;
            amounts[1] = attackerTokens/2;
        
        bytes[] memory signatures = new bytes[](2);
            signatures[0] = attackerRound1;
            signatures[1] = attackerRound2;

        bytes memory data = abi.encodeWithSignature("claimMultiple(uint128[],uint128[],bytes[])", rounds, amounts, signatures);

        token.scheduleReenter(when, target, data);

        // call w/ reentry
        vm.expectRevert(abi.encodeWithSelector(ECDSADistributor.UserHasClaimed.selector));

        vm.prank(userB);
        attackerContract.claimMultiple(rounds, amounts, signatures);

    }
}