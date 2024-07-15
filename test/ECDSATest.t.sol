// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import "../src/ECDSADistributor.sol";

import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";

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
    uint128 totalAmountForRoundThree;

    uint256 public deadline;

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
    event DeadlineUpdated(uint256 newDeadline);
    event Deposited(uint256 indexed totalAmount);
    event Frozen(uint256 indexed timestamp);

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
        operatorTokens = (userATokens + userBTokens + userCTokens) * 3;
        
        // rounds
        totalAmountForAllRounds = operatorTokens;
        totalAmountForRoundOne = totalAmountForRoundTwo = totalAmountForRoundThree = totalAmountForAllRounds/3;

        deadline = 10;

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
        assertEq(distributor.firstClaimTime(), startTimes[0]);
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
        assertEq(startTime_2, startTimes[0]);
        assertEq(allocation_2, allocations[0]);
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

        vm.expectRevert("Setup: cannot update");

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
        vm.expectRevert("Incorrect caller");
        distributor.deposit(rounds);
    }

    function testOperatorCanDeposit() public {

        uint256[] memory rounds = new uint256[](2);
            rounds[0] = 0;
            rounds[1] = 1;

        // for 2 rounds
        uint256 totalAmount = totalAmountForRoundOne + totalAmountForRoundTwo;

        // check events
        vm.expectEmit(true, true, true, false);
        emit Deposited(totalAmount);

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

        vm.expectRevert("Already financed");

        vm.prank(operator);
        distributor.deposit(rounds);
    }

    function testNonOperatorCannotWithdraw() public {

        vm.expectRevert("Incorrect caller"); 

        vm.prank(userC);
        distributor.withdraw();
    }

    function testCannotWithdrawIfNoDeadline() public {

        vm.expectRevert("Withdraw disabled"); 

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

    function testAddRounds() public {

        // old data
        uint256 oldNumOfRounds = distributor.numberOfRounds();
        uint256 oldLastClaimTime = distributor.lastClaimTime();

        uint128[] memory startTimes = new uint128[](1);
            startTimes[0] = (30 days + 4 days);

        uint128[] memory allocations = new uint128[](1);
            allocations[0] = totalAmountForRoundThree;

        // check events
        vm.expectEmit(true, true, true, false);
        emit AddedRounds(startTimes.length, totalAmountForRoundThree, startTimes[0]);

        vm.prank(owner);
        distributor.addRounds(startTimes, allocations);

        // check allRounds mapping: 3rd round
        (uint128 startTime_3, uint128 allocation_3, uint128 deposited_3, uint128 claimed_3) = distributor.allRounds(2);
        assertEq(startTime_3, startTimes[0]);
        assertEq(allocation_3, totalAmountForRoundThree);
        assertEq(deposited_3, 0);
        assertEq(claimed_3, 0);

        // check global vars
        assertEq(distributor.numberOfRounds(), oldNumOfRounds + startTimes.length);
        assertEq(distributor.lastClaimTime(), startTimes[0]);
    }
}

abstract contract StateAddRounds is StateBothRoundsClaimed {
    function setUp() public override virtual {
        super.setUp();
    }
}

contract StateAddRoundsTest is StateAddRounds {

}


/**

after daeling is defined
    function testCannotWithdrawPrematurely() public {

        vm.expectRevert("Premature withdraw"); 

        vm.prank(operator);
        distributor.withdraw();
    }

 */