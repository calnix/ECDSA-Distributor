// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";

import {SafeERC20, IERC20} from "./../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step, Ownable} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";

//import {ReentrancyGuard} from "@looksrare/contracts-libs/contracts/ReentrancyGuard.sol";

contract ECDSADistributor is EIP712, Pausable, Ownable2Step {
    using SafeERC20 for IERC20;

    IERC20 internal immutable TOKEN;
    address internal immutable STORED_SIGNER; //note: if change, should redeploy.

    address public operator;
    
    // distribution
    uint256 public deadline;                // optional: Users can claim until this timestamp
    uint256 public numberOfRounds;         // num. of rounds

    // balances
    uint256 public totalClaimed;
    uint256 public totalDeposited;

    // emergency state: 1 is Frozed. 0 is not.
    uint256 public isFrozen;
    uint256 public setupComplete;

    struct Claim {
        address user;
        uint128 round;
        uint128 amount;
    }
    
    struct RoundData {
        uint128 startTime;
        uint128 allocation;
        uint128 deposited;
        uint128 claimed;
    }

    mapping(uint256 round => RoundData roundData) public allRounds;
    // 0: false, 1: true.
    mapping(address user => mapping(uint256 round => uint256 claimed)) public hasClaimed;

// --- errors
    error DeadlineExceeded();
    error UserHasClaimed();
    error InvalidRound();
    error TaxTokenCheckFailed();
    
    error RoundNotSetup();
    error RoundNotStarted();
    error RoundNotFinanced();
    error RoundFullyClaimed();
    error RoundAlreadyFinanced();

    error InvalidSignature();

    error EmptyArray();
    error IncorrectLengths();

    error InvalidNewDeadline();
// ------------------------------------

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

    constructor(string memory name, string memory version, address token, address storedSigner, address owner, address operator_) EIP712(name, version) Ownable(owner) {
        
        TOKEN = IERC20(token);
        STORED_SIGNER = storedSigner;

        operator = operator_;
    }   

    /*//////////////////////////////////////////////////////////////
                                 CLAIM
    //////////////////////////////////////////////////////////////*/

    function claim(uint128 round, uint128 amount, bytes calldata signature) external whenNotPaused {

        // check that deadline as not been exceeded; if deadline has been defined
        if (deadline > 0) {
            if (block.timestamp >= deadline) {
                revert DeadlineExceeded();
            }
        }

        // replay attack protection: check that signature has already been used
        if (hasClaimed[msg.sender][round] == 1) revert UserHasClaimed();
       
        // sig.verification
        _claim(round, amount, signature);

        RoundData memory roundData = allRounds[round];
        
        // check if round is legitimate  ---note: consider removing; excessive check
        //if (roundData.allocation == 0) revert InvalidRound();

        // sanity checks: round financed, started, not fully claimed
        if (roundData.deposited == 0) revert RoundNotFinanced();
        if (roundData.startTime > block.timestamp) revert RoundNotStarted();

        // update round data: increment claimedTokens
        roundData.claimed += amount;

        // sanity check
        if (roundData.deposited < roundData.claimed) revert RoundFullyClaimed(); 

        // update storage
        hasClaimed[msg.sender][round] = 1;
        allRounds[round] = roundData;
        totalClaimed += amount;

        emit Claimed(msg.sender, round, amount);

        TOKEN.safeTransfer(msg.sender, amount);        
    }

    function claimMultiple(uint128[] calldata rounds, uint128[] calldata amounts, bytes[] calldata signatures) external whenNotPaused {

        // check that deadline as not been exceeded; if deadline has been defined
        if(deadline > 0) {
            if (block.timestamp >= deadline) {
                revert DeadlineExceeded();
            }
        }
        
        uint256 roundsLength = rounds.length;
        uint256 amountsLength = amounts.length;
        uint256 signaturesLength = signatures.length;

        if(roundsLength != amountsLength && roundsLength != signaturesLength) revert IncorrectLengths(); 
        if(roundsLength == 0) revert EmptyArray(); 

        uint128 totalAmount;
        for(uint256 i = 0; i < roundsLength; ++i) {
            
            // get round no. & round data
            uint128 round = rounds[i];
            uint128 amount = amounts[i];
            bytes memory signature = signatures[i];

            RoundData memory roundData = allRounds[round];

            // replay attack protection: check that signature has already been used
            if (hasClaimed[msg.sender][round] == 1) revert UserHasClaimed();

            // check if round is legitimate
            //if (roundData.allocation == 0) revert InvalidRound();

            // sanity checks: round financed, started, not fully claimed
            if (roundData.deposited == 0) revert RoundNotFinanced();
            if (roundData.startTime > block.timestamp) revert RoundNotStarted();
            if (roundData.deposited == roundData.claimed) revert RoundFullyClaimed(); 

            // sig.verification
            _claim(round, amount, signature);
        
            // update round data: increment claimedTokens
            roundData.claimed += amount;
            totalAmount += amount;       

            // update storage: signature + roundData
            hasClaimed[msg.sender][round] = 1;
            allRounds[round] = roundData;
        
        }
        
        // update storage: claimed
        totalClaimed += totalAmount;

        emit ClaimedMultiple(msg.sender, rounds, totalAmount);

        TOKEN.safeTransfer(msg.sender, totalAmount);
    }

    function _claim(uint128 round, uint128 amount, bytes memory signature) internal view {

        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(keccak256("Claim(address user,uint128 round,uint128 amount)"), msg.sender, round, amount)));

        address signer = ECDSA.recover(digest, signature);
            if(signer != STORED_SIGNER) revert InvalidSignature(); 
    }

    // note: only callable once?
    // note: calldata on L2 
    // deadline is optional
    function setupRounds(uint128[] calldata startTimes, uint128[] calldata allocations) external onlyOwner {
        require(setupComplete == 0, "Already setup");

        // input validation
        uint256 startTimesLength = startTimes.length;
        uint256 allocationsLength = allocations.length;
        
        require(startTimesLength > 0, "Empty Array");
        require(startTimesLength == allocationsLength, "Incorrect Lengths");
        
        // update rounds
        uint256 totalAmount;
        uint256 prevStartTime = block.timestamp;
        for(uint256 i = 0; i < startTimesLength; ++i) {         

            uint128 startTime = startTimes[i];
            uint128 allocation = allocations[i];
            
            // startTime check
            require(startTime > prevStartTime, "Incorrect startTime");
            prevStartTime = startTime;

            // allocation check
            require(allocation > 0, "Incorrect Allocation");

            // update storage 
            allRounds[i] = RoundData({startTime: startTime, allocation: allocation, deposited:0, claimed:0});
            
            // increment
            totalAmount += allocation;
        }

        // update storage
        numberOfRounds = startTimesLength;
        setupComplete = 1;

        emit SetupRounds(startTimesLength, startTimes[0], startTimes[startTimesLength-1], totalAmount);
    }


    //note: deadline must be after last claim round
    function updateDeadline(uint256 newDeadline) external onlyOwner {
        //if (newDeadline < block.timestamp) revert InvalidNewDeadline(); --- not needed cos of subsequent check

        // allow for 14 days buffer: prevent malicious premature ending
        require(newDeadline > allRounds[allRounds.length - 1].startTime + 14 days, "Invalid deadline"); 

        deadline = newDeadline;
        emit DeadlineUpdated(newDeadline);
    }

    function updateOperator(address newOperator) external onlyOwner {
        address oldOperator = operator;

        operator = newOperator;

        emit OperatorUpdated(oldOperator, newOperator);

    }

    /*//////////////////////////////////////////////////////////////
                                OPERATOR
    //////////////////////////////////////////////////////////////*/

    // project can fund all rounds at once or partially
    function deposit(uint256[] calldata rounds) external {
        require(msg.sender == operator, "Incorrect caller");

        // input validation
        uint256 roundsLength = rounds.length;
        if(roundsLength == 0) revert EmptyArray(); 

        // calculate total required for all rounds
        uint256 totalAmount;
        for(uint256 i = 0; i < roundsLength; ++i) {
            
            // get round no. & round data
            uint256 round = rounds[i];
            RoundData storage roundData = allRounds[round];

            // check that round has been setup
            if (roundData.allocation == 0) revert RoundNotSetup();

            // check that round was not previously financed
            if (roundData.deposited == roundData.allocation) revert RoundAlreadyFinanced();

            // update deposit and increment
            roundData.deposited = roundData.allocation;
            totalAmount += roundData.allocation;
        }

        // update storage
        totalDeposited += totalAmount;

        emit Deposited(msg.sender, totalAmount);

        // tax token check
        uint256 before = TOKEN.balanceOf(address(this));

        TOKEN.safeTransferFrom(msg.sender, address(this), totalAmount);
        
        // tax token check
        if (TOKEN.balanceOf(address(this) - before != totalAmount)) revert TaxTokenCheckFailed(); 
    }

    function withdraw() external {
        require(msg.sender == operator, "Incorrect caller");

        // if deadline is not defined; cannot withdraw
        if(deadline == 0) {
            revert ("Withdraw disabled");
        }
        
        // if deadline is defined
        else {      
            require(block.timestamp > deadline, "Premature withdraw");
        }

        uint256 available = totalDeposited - totalClaimed;

        emit Withdrawn(msg.sender, available);

        TOKEN.safeTransfer(msg.sender, available);
    }


    /*//////////////////////////////////////////////////////////////
                                PAUSABLE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Pause claim
     */
    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    /**
     * @notice Unpause claim
     */
    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                                RECOVERY
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Freeze the contract in the event of something untoward occuring
     * @dev Only callable from a paused state, affirming that distribution should not resume
     *      Nothing to be updated. Freeze as is.
            Enables emergencyExit() to be called.
     */
    function freeze() external whenPaused onlyOwner {
        require(isFrozen == 0, "Frozen");
        
        isFrozen = 1;

        emit Frozen(block.timestamp);
    }  


    /**
     * @notice Recover assets in a black swan event. 
               Assumed that this contract will no longer be used. 
     * @dev Transfers all tokens to specified address 
     * @param receiver Address of beneficiary of transfer
     */
    function emergencyExit(address receiver) external whenPaused onlyOwner {
        require(isFrozen == 1, "Not frozen");

        uint256 balance = TOKEN.balanceOf(address(this));

        emit EmergencyExit(receiver, balance);

        TOKEN.safeTransfer(receiver, balance);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function hashTypedDataV4(bytes32 structHash) external view returns (bytes32) {
        return _hashTypedDataV4(structHash);
    }

    // note: may not need this. check eip712    
    function domainSeparatorV4() external view returns (bytes32) {
        return _domainSeparatorV4();
    }
}





/**

    Permit
    - spender presents a signature requesting funds from John's wallet
    - did John sign the signature? if he did, allow. 

    John signs message off-chain, DApp transmits the signature via txn and handles the asset flow.
    John pays no gas.

    Similarly in Airdrop,

    - claimer presents a signature: amount, address
    - did 'we' contract signer, sign said msg?

    Have a specific EOA sign to create all signatures.
    Store addr of signer on contract
    Recover signer from signature to verify against on-chain copy.

    If attacker submits spoofed signature, incorrect signer will be returned. 
    If the correct signature was supplied by the FE, the correct signer will be returned.

*/

/**
    Attacks

    1. replay attack on other chain/contract:
        other chain - check mocaToken and hashTypedDataV4
    2. 
 */