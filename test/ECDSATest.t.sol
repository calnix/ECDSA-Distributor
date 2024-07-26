// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import "../src/ECDSADistributor.sol";

import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";

abstract contract StateDeploy is Test {    

    ECDSADistributor public distributor;
    ERC20Mock public token;

    // entities
    address public userA;
    address public userB;
    address public userC;
    address public owner;
    address public operator;
    address public storedSigner;

    uint256 public storedSignerPrivateKey;

    // token balances
    uint128 public userATokens;
    uint128 public userBTokens;
    uint128 public userCTokens;
    uint128 public operatorTokens;

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

        // signer
        (storedSigner, storedSignerPrivateKey) = makeAddrAndKey("storedSigner");

        // tokens
        userATokens = 20 ether;
        userBTokens = 50 ether;
        userCTokens = 80 ether;
        operatorTokens = (userATokens + userBTokens + userCTokens);
        
        // rounds
        totalAmountForAllRounds = operatorTokens;
        totalAmountForRoundOne = totalAmountForRoundTwo = totalAmountForAllRounds/2;

        // contracts
        vm.startPrank(owner);
        
        token = new ERC20Mock();       
        
        string memory name = "TestDistributor";
        string memory version = "v1";
        distributor = new ECDSADistributor(name, version, address(token), storedSigner, owner, operator);

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

//Note: Contracts deployed but rounds are not setup
//      t = 30 days
contract StateDeployTest is StateDeploy {

    // cannot claim
    function testUserCannotClaim() public {
        
        vm.expectRevert(abi.encodeWithSelector(ECDSADistributor.RoundNotFinanced.selector));

        vm.prank(userA);        
        distributor.claim(0, userATokens/2, userARound1);
    }

    function testSetupRounds() public {

        uint128[] memory startTimes = new uint128[](2);
            startTimes[0] = (30 days + 2 days);
            startTimes[1] = (30 days + 3 days);

        uint128[] memory allocations = new uint128[](2);
            allocations[0] = totalAmountForRoundOne;
            allocations[1] = totalAmountForRoundTwo;
        
        // event params
        uint256 firstClaimTime = startTimes[0];
        uint256 lastClaimTime = startTimes[1];

        // check events
        vm.expectEmit(true, true, true, false);
        emit SetupRounds(2, firstClaimTime, lastClaimTime, (totalAmountForRoundOne + totalAmountForRoundTwo));

        vm.prank(owner);
        distributor.setupRounds(startTimes, allocations);

        // check storage vars
//        assertEq(distributor.firstClaimTime(), startTimes[0]);
        assertEq(distributor.lastClaimTime(),  startTimes[1]);
        assertEq(distributor.numberOfRounds(), startTimes.length);

        // check mapping: first round
        (uint128 startTime_1, uint128 allocation_1, uint128 deposited_1, uint128 claimed_1) = distributor.allRounds(0);
        assertEq(startTime_1, startTimes[0]);
        assertEq(allocation_1, allocations[0]);
        assertEq(deposited_1, 0);
        assertEq(claimed_1, 0);

        // check mapping: 2nd round
        (uint128 startTime_2, uint128 allocation_2, uint128 deposited_2, uint128 claimed_2) = distributor.allRounds(1);
        assertEq(startTime_2, startTimes[1]);
        assertEq(allocation_2, allocations[1]);
        assertEq(deposited_2, 0);
        assertEq(claimed_2, 0);
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

contract StateSetupTest is StateSetup {

    function testCannotSetupAgain() public {

        uint128[] memory startTimes = new uint128[](2);
            startTimes[0] = (30 days + 2 days);
            startTimes[1] = (30 days + 3 days);

        uint128[] memory allocations = new uint128[](2);
            allocations[0] = userATokens/2 + userBTokens/2 + userCTokens/2;
            allocations[1] = userATokens/2 + userBTokens/2 + userCTokens/2;

        vm.expectRevert(abi.encodeWithSelector(ECDSADistributor.AlreadySetup.selector));

        vm.prank(owner);
        distributor.setupRounds(startTimes, allocations);
    }

    function testUserCannotClaim() public {
        
        vm.expectRevert(abi.encodeWithSelector(ECDSADistributor.RoundNotFinanced.selector));

        vm.prank(userA);        
        distributor.claim(0, userATokens/2, userARound1);
    }

    function testNonOperatorCannotDeposit() public {

        uint256[] memory rounds = new uint256[](2);
            rounds[0] = 0;
            rounds[1] = 1;

        vm.prank(userC);
        vm.expectRevert(abi.encodeWithSelector(ECDSADistributor.IncorrectCaller.selector));
        distributor.deposit(rounds);
    }

    function testOperatorCanDeposit() public {

        uint256[] memory rounds = new uint256[](2);
            rounds[0] = 0;
            rounds[1] = 1;

        // for 2 rounds
        uint256 totalAmount = totalAmountForRoundOne + totalAmountForRoundTwo;

        // check events
        vm.expectEmit(true, true, false, false);
        emit Deposited(operator, totalAmount);

        vm.prank(operator);
        distributor.deposit(rounds);

        // check tokens
        assertEq(distributor.totalDeposited(), totalAmount);
        assertEq(token.balanceOf(address(distributor)), totalAmount);
        assertEq(token.balanceOf(operator), (operatorTokens - totalAmount));

        // check mapping: first round
        (uint128 startTime_1, uint128 allocation_1, uint128 deposited_1, uint128 claimed_1) = distributor.allRounds(0);
        assertEq(deposited_1, totalAmountForRoundOne);
        assertEq(claimed_1, 0);

        // check mapping: 2nd round
        (uint128 startTime_2, uint128 allocation_2, uint128 deposited_2, uint128 claimed_2) = distributor.allRounds(0);
        assertEq(deposited_2, totalAmountForRoundTwo);
        assertEq(claimed_2, 0);
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

contract StateDepositedTest is StateDeposited {

    function testCannotDoubleDeposit() public {
        uint256[] memory rounds = new uint256[](2);
            rounds[0] = 0;
            rounds[1] = 1;

        // for all rounds
        uint256 totalAmount = userATokens + userBTokens + userCTokens;

        vm.expectRevert(abi.encodeWithSelector(ECDSADistributor.RoundAlreadyFinanced.selector));

        vm.prank(operator);
        distributor.deposit(rounds);
    }

    function testNonOperatorCannotWithdraw() public {

        vm.expectRevert(abi.encodeWithSelector(ECDSADistributor.IncorrectCaller.selector));

        vm.prank(userC);
        distributor.withdraw();
    }

    function testCannotWithdrawIfNoDeadline() public {

        vm.expectRevert(abi.encodeWithSelector(ECDSADistributor.WithdrawDisabled.selector));

        vm.prank(operator);
        distributor.withdraw();
    }

    function testCanClaim_UserA_RoundOne() public {
        // forward to first round claim time
        vm.warp(30 days + 2 days);

        // round params
        uint128 round = 0; 
        uint128 amount = userATokens/2; 

        // check events
        vm.expectEmit(true, true, true, false);
        emit Claimed(userA, round, amount);

        vm.prank(userA);
        distributor.claim(round, amount, userARound1);

        // check tokens transfers
        assertEq(token.balanceOf(userA), userATokens/2);
        assertEq(distributor.totalClaimed(), userATokens/2);
        assertEq(token.balanceOf(address(distributor)), (totalAmountForRoundOne + totalAmountForRoundTwo - userATokens/2));

        // check allRounds mapping: first round
        (uint128 startTime_1, uint128 allocation_1, uint128 deposited_1, uint128 claimed_1) = distributor.allRounds(0);
        assertEq(allocation_1, totalAmountForRoundOne);
        assertEq(deposited_1, totalAmountForRoundOne);
        assertEq(claimed_1, userATokens/2);

        // check hasClaimed mapping: first round
        assertEq(distributor.hasClaimed(userA, 0), 1);
    }
}

abstract contract StateRoundOne is StateDeposited {

    function setUp() public override virtual {
        super.setUp();

        // forward to first round claim time
        vm.warp(30 days + 2 days);

        vm.prank(userA);
        distributor.claim(0, userATokens/2, userARound1);
    }
}

contract StateRoundOneTest is StateRoundOne {

    function testCannotClaimTwice() public {

        vm.expectRevert(abi.encodeWithSelector(ECDSADistributor.UserHasClaimed.selector));

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

contract StateRoundTwoTest is StateRoundTwo {

    function testCanClaimMultiple_UserB() public {
        
        uint128[] memory rounds = new uint128[](2);
            rounds[0] = 0;
            rounds[1] = 1;

        uint128[] memory amounts = new uint128[](2);
            amounts[0] = userBTokens/2;
            amounts[1] = userBTokens/2;
        
        bytes[] memory signatures = new bytes[](2);
            signatures[0] = userBRound1;
            signatures[1] = userBRound2;

        // check events
        vm.expectEmit(true, true, true, false);
        emit ClaimedMultiple(userB, rounds, userBTokens);

        vm.prank(userB);
        distributor.claimMultiple(rounds, amounts, signatures);

        // check tokens transfers
        assertEq(token.balanceOf(userB), userBTokens);
        assertEq(distributor.totalClaimed(), userBTokens + userATokens/2);
        assertEq(token.balanceOf(address(distributor)), (totalAmountForRoundOne + totalAmountForRoundTwo - userBTokens - userATokens/2));

        // check allRounds mapping: first round
        (uint128 startTime_1, uint128 allocation_1, uint128 deposited_1, uint128 claimed_1) = distributor.allRounds(0);
        assertEq(allocation_1, totalAmountForRoundOne);
        assertEq(deposited_1, totalAmountForRoundOne);
        assertEq(claimed_1, (userBTokens/2 + userATokens/2));

        // check allRounds mapping: 2nd round
        (uint128 startTime_2, uint128 allocation_2, uint128 deposited_2, uint128 claimed_2) = distributor.allRounds(1);
        assertEq(allocation_2, totalAmountForRoundTwo);
        assertEq(deposited_2, totalAmountForRoundTwo);
        assertEq(claimed_2, userBTokens/2);

        // check hasClaimed mapping: first & second round 
        assertEq(distributor.hasClaimed(userB, 0), 1);
        assertEq(distributor.hasClaimed(userB, 1), 1);
    }

    function testCanClaim_UserA_RoundTwo() public {
        
        // round params
        uint128 round = 1; 
        uint128 amount = userATokens/2; 

        // check events
        vm.expectEmit(true, true, true, false);
        emit Claimed(userA, round, amount);

        vm.prank(userA);
        distributor.claim(round, amount, userARound2);

        // check tokens transfers
        assertEq(token.balanceOf(userA), userATokens);
        assertEq(distributor.totalClaimed(), userATokens);
        assertEq(token.balanceOf(address(distributor)), (totalAmountForRoundOne + totalAmountForRoundTwo - userATokens));

        // check allRounds mapping: first round
        (uint128 startTime_1, uint128 allocation_1, uint128 deposited_1, uint128 claimed_1) = distributor.allRounds(0);
        assertEq(allocation_1, totalAmountForRoundOne);
        assertEq(deposited_1, totalAmountForRoundOne);
        assertEq(claimed_1, userATokens/2);

        (uint128 startTime_2, uint128 allocation_2, uint128 deposited_2, uint128 claimed_2) = distributor.allRounds(1);
        assertEq(allocation_2, totalAmountForRoundTwo);
        assertEq(deposited_2, totalAmountForRoundTwo);
        assertEq(claimed_2, userATokens/2);

        // check hasClaimed mapping: first round
        assertEq(distributor.hasClaimed(userA, 0), 1);
        assertEq(distributor.hasClaimed(userA, 1), 1);

    }

}

//  t = 33 days
abstract contract StateBothRoundsClaimed is StateRoundTwo {

    function setUp() public override virtual {
        super.setUp();

        // userA claims
        vm.prank(userA);
        distributor.claim(1, userATokens/2, userARound2);

        // userB claims
        uint128[] memory rounds = new uint128[](2);
            rounds[0] = 0;
            rounds[1] = 1;

        uint128[] memory amounts = new uint128[](2);
            amounts[0] = userBTokens/2;
            amounts[1] = userBTokens/2;
        
        bytes[] memory signatures = new bytes[](2);
            signatures[0] = userBRound1;
            signatures[1] = userBRound2;

        vm.prank(userB);
        distributor.claimMultiple(rounds, amounts, signatures);
    }
}

//  t = 33 days
contract StateBothRoundsClaimedTest is StateBothRoundsClaimed {

    function testClaimForRoundOneAndTwo_UserA_UserB() public {

        // ---- user A: check for both rounds ----
        
        // check tokens transfers
        assertEq(token.balanceOf(userA), userATokens);
        assertEq(token.balanceOf(userB), userBTokens);

        assertEq(distributor.totalClaimed(), userATokens + userBTokens);
        assertEq(token.balanceOf(address(distributor)), (totalAmountForRoundOne + totalAmountForRoundTwo - userATokens - userBTokens));

        // check allRounds mapping: first round
        (uint128 startTime_1, uint128 allocation_1, uint128 deposited_1, uint128 claimed_1) = distributor.allRounds(0);
        assertEq(allocation_1, totalAmountForRoundOne);
        assertEq(deposited_1, totalAmountForRoundOne);
        assertEq(claimed_1, userATokens/2 + userBTokens/2);

        (uint128 startTime_2, uint128 allocation_2, uint128 deposited_2, uint128 claimed_2) = distributor.allRounds(1);
        assertEq(allocation_2, totalAmountForRoundTwo);
        assertEq(deposited_2, totalAmountForRoundTwo);
        assertEq(claimed_2, userATokens/2 + userBTokens/2);

        // check hasClaimed mapping: first round
        assertEq(distributor.hasClaimed(userA, 0), 1);
        assertEq(distributor.hasClaimed(userA, 1), 1);

        assertEq(distributor.hasClaimed(userB, 0), 1);
        assertEq(distributor.hasClaimed(userB, 1), 1);

    }
    
    function testCannotWithdraw_SinceNoDeadline() public {

        vm.expectRevert(abi.encodeWithSelector(ECDSADistributor.WithdrawDisabled.selector));

        vm.prank(operator);   
        distributor.withdraw();
    }

    function testCannotUpdateDeadlineUnderBuffer() public {
        assertEq(distributor.deadline(), 0);
   
        uint256 lastClaimTime = distributor.lastClaimTime();
        
        vm.expectRevert(abi.encodeWithSelector(ECDSADistributor.InvalidNewDeadline.selector));

        vm.prank(owner);
        distributor.updateDeadline(lastClaimTime + 13 days);
    }

    function testOwnerUpdateDeadline() public {  
        assertEq(distributor.deadline(), 0);
 
        uint256 lastClaimTime = distributor.lastClaimTime();
        uint256 deadline = lastClaimTime + 15 days;

        // check events
        vm.expectEmit(true, false, false, false);
        emit DeadlineUpdated(deadline);

        vm.prank(owner);
        distributor.updateDeadline(deadline);

        assertEq(distributor.deadline(), deadline);
    }

}

//  t = 33 days
abstract contract StateUpdateDeadline is StateBothRoundsClaimed {
    
    uint256 public deadline;

    function setUp() public override virtual {
        super.setUp();

        uint256 lastClaimTime = distributor.lastClaimTime();
        deadline = lastClaimTime + 15 days;

        vm.prank(owner);
        distributor.updateDeadline(deadline);
    }
}

contract StateUpdateDeadlineTest is StateUpdateDeadline {

    function testCannotClaimAfterDeadline() public {
        
        vm.warp(deadline);

        vm.expectRevert(abi.encodeWithSelector(ECDSADistributor.DeadlineExceeded.selector));

        vm.prank(userA);        
        distributor.claim(0, userATokens/2, userARound1);

        // --------------------------------------------------

        vm.warp(deadline + 1 days);

        vm.expectRevert(abi.encodeWithSelector(ECDSADistributor.DeadlineExceeded.selector));
    
        vm.prank(userC);        
        distributor.claim(0, userCTokens/2, userCRound1);
    }

    function testCanClaimBeforeDeadline() public {

        vm.warp(deadline - 1);
        
        vm.prank(userC);        
        distributor.claim(0, userCTokens/2, userCRound1);

        // check tokens transfers
        assertEq(token.balanceOf(userC), userCTokens/2);
        assertEq(distributor.totalClaimed(), userATokens + userBTokens + userCTokens/2);
        assertEq(token.balanceOf(address(distributor)), userCTokens/2);

        // check allRounds mapping: first round
        (uint128 startTime_1, uint128 allocation_1, uint128 deposited_1, uint128 claimed_1) = distributor.allRounds(0);
        assertEq(allocation_1, totalAmountForRoundOne);
        assertEq(deposited_1, totalAmountForRoundOne);
        assertEq(claimed_1, totalAmountForRoundOne);

        (uint128 startTime_2, uint128 allocation_2, uint128 deposited_2, uint128 claimed_2) = distributor.allRounds(1);
        assertEq(allocation_2, totalAmountForRoundTwo);
        assertEq(deposited_2, totalAmountForRoundTwo);
        assertEq(claimed_2, totalAmountForRoundTwo -  userCTokens/2);

        // check hasClaimed mapping: first round
        assertEq(distributor.hasClaimed(userC, 0), 1);
        assertEq(distributor.hasClaimed(userC, 1), 0);

    }

    function testCanClaimMultipleBeforeDeadline() public {

        vm.warp(deadline - 1);
        
        // userC params
        uint128[] memory rounds = new uint128[](2);
            rounds[0] = 0;
            rounds[1] = 1;

        uint128[] memory amounts = new uint128[](2);
            amounts[0] = userCTokens/2;
            amounts[1] = userCTokens/2;
        
        bytes[] memory signatures = new bytes[](2);
            signatures[0] = userCRound1;
            signatures[1] = userCRound2;

        vm.prank(userC);        
        distributor.claimMultiple(rounds, amounts, signatures);

        // check tokens transfers
        assertEq(token.balanceOf(userC), userCTokens);
        assertEq(token.balanceOf(address(distributor)), 0);
        assertEq(distributor.totalClaimed(),  userATokens + userBTokens + userCTokens);

        // check allRounds mapping: first round
        (uint128 startTime_1, uint128 allocation_1, uint128 deposited_1, uint128 claimed_1) = distributor.allRounds(0);
        assertEq(allocation_1, totalAmountForRoundOne);
        assertEq(deposited_1, totalAmountForRoundOne);
        assertEq(claimed_1, (userATokens + userBTokens + userCTokens)/2);

        // check allRounds mapping: 2nd round
        (uint128 startTime_2, uint128 allocation_2, uint128 deposited_2, uint128 claimed_2) = distributor.allRounds(1);
        assertEq(allocation_2, totalAmountForRoundTwo);
        assertEq(deposited_2, totalAmountForRoundTwo);
        assertEq(claimed_2, (userATokens + userBTokens + userCTokens)/2);

        // check hasClaimed mapping: first & second round 
        assertEq(distributor.hasClaimed(userC, 0), 1);
        assertEq(distributor.hasClaimed(userC, 1), 1);


    }

    function testCannotWithdraw_BeforeDeadline() public {
        vm.warp(deadline - 1);

        vm.expectRevert(abi.encodeWithSelector(ECDSADistributor.PrematureWithdrawal.selector));

        vm.prank(operator);   
        distributor.withdraw();
    }

    function testCanWithdraw_AfterDeadline() public {
        vm.warp(deadline + 1);

        uint256 unclaimed = distributor.totalDeposited() - distributor.totalClaimed();

        // check events
        vm.expectEmit(true, true, true, false);
        emit Withdrawn(distributor.operator(), unclaimed);
        
        vm.prank(operator);   
        distributor.withdraw();

        // user A and B have fully claimed. but not C
        uint256 remainder = (totalAmountForAllRounds - userATokens - userBTokens);

        // check tokens transfers
        assertEq(token.balanceOf(address(distributor)), 0);
        assertEq(token.balanceOf(operator), remainder);
        assertEq(token.balanceOf(operator), userCTokens);
    }

}


abstract contract StatePaused is StateUpdateDeadline {

    function setUp() public override virtual {
        super.setUp();

        vm.prank(owner);
        distributor.pause();
    }    
}

contract StatePausedTest is StatePaused {

    function testCannotClaimWhenPaused() public {
        
        vm.warp(deadline - 1);
        
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));

        vm.prank(userC);        
        distributor.claim(0, userCTokens/2, userCRound1);      
    }

    function testCannotClaimMultipleWhenPaused() public {
        
        vm.warp(deadline - 1);
        
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));

        // userC params
        uint128[] memory rounds = new uint128[](2);
            rounds[0] = 0;
            rounds[1] = 1;

        uint128[] memory amounts = new uint128[](2);
            amounts[0] = userCTokens/2;
            amounts[1] = userCTokens/2;
        
        bytes[] memory signatures = new bytes[](2);
            signatures[0] = userCRound1;
            signatures[1] = userCRound2;

        vm.prank(userC);        
        distributor.claimMultiple(rounds, amounts, signatures);    
    }

    function testFreezeContract() public {

        assertEq(distributor.isFrozen(), 0);

        // check events
        vm.expectEmit(true, false, false, false);
        emit Frozen(block.timestamp);
        

        vm.prank(owner);
        distributor.freeze();

        assertEq(distributor.isFrozen(), 1);
    }
}

abstract contract StateFrozen is StatePaused {

    function setUp() public override virtual {
        super.setUp();
        
        vm.prank(owner);
        distributor.freeze();
    }    
}

contract StateFrozenTest is StateFrozen {

    function testEmergencyExit() public {
        
        uint256 balance = token.balanceOf(address(distributor));

        // check events
        vm.expectEmit(true, false, false, false);
        emit EmergencyExit(owner, balance);

        vm.prank(owner);
        distributor.emergencyExit(owner);

        assertEq(token.balanceOf(owner), balance);
    }
}

