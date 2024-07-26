// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";

import {SafeERC20, IERC20} from "./../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step, Ownable} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";

contract ECDSADistributor is EIP712, Pausable, Ownable2Step {
    using SafeERC20 for IERC20;

    IERC20 internal immutable TOKEN;
    address internal immutable STORED_SIGNER;

    address public operator;
    
    // distribution
    uint256 public deadline;                // optional: Users can claim until this timestamp
    uint256 public numberOfRounds;         // num. of rounds
    uint256 public lastClaimTime;         // startTime of last round

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

    // number of claiming rounds
    mapping(uint256 round => RoundData roundData) public allRounds;
    // 0: false, 1: true.
    mapping(address user => mapping(uint256 round => uint256 claimed)) public hasClaimed;

// --- errors
    error AlreadySetup();

    error IncorrectStartTime();
    error IncorrectAllocation();

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

    error NotSetup();
    error InvalidNewDeadline();

    error IncorrectCaller();
    error WithdrawDisabled();
    error PrematureWithdrawal();

    error IsFrozen();
    error NotFrozen();
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

    /**
     * @notice User to claim allocated tokens for a specific round
     * @dev Only callable when not paused
     * @param round Claim round number (first round: 0)
     * @param amount Tokens to be claimed for specified round
     * @param signature Signature must be signed by the declared signer on the contract
     */
    function claim(uint128 round, uint128 amount, bytes calldata signature) external whenNotPaused {

        // check that deadline as not been exceeded; if deadline has been defined
        if (deadline > 0) {
            if (block.timestamp >= deadline) {
                revert DeadlineExceeded();
            }
        }

        // check that the user has not previously claimed for round
        if (hasClaimed[msg.sender][round] == 1) revert UserHasClaimed();
       
        // sig.verification
        _claim(round, amount, signature);

        RoundData memory roundData = allRounds[round];

        // sanity checks: round financed, started, not fully claimed
        if (roundData.deposited == 0) revert RoundNotFinanced();
        if (roundData.startTime > block.timestamp) revert RoundNotStarted();

        // update round data: increment claimedTokens
        roundData.claimed += amount;

        // sanity check
        if (roundData.claimed > roundData.deposited) revert RoundFullyClaimed();    

        // update storage
        hasClaimed[msg.sender][round] = 1;
        allRounds[round] = roundData;
        totalClaimed += amount;

        emit Claimed(msg.sender, round, amount);

        TOKEN.safeTransfer(msg.sender, amount);        
    }

    /**
     * @notice User to claim allocated tokens for multiple round
     * @dev Only callable when not paused
     * @param rounds Array of claim round numbers (first round: 0)
     * @param amounts Array of tokens to be claimed for each round
     * @param signatures Array of signatures must be signed by the declared signer on the contract
     */
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

            // sanity checks: round financed, started
            if (roundData.deposited == 0) revert RoundNotFinanced();
            if (roundData.startTime > block.timestamp) revert RoundNotStarted();
            
            // sig.verification
            _claim(round, amount, signature);
        
            // update round data: increment claimedTokens
            roundData.claimed += amount;
            totalAmount += amount;       

            // sanity check
            if (roundData.claimed > roundData.deposited) revert RoundFullyClaimed();    
          
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

    /**
     * @notice Owner to create distribution schedule
     * @dev Only callable once
     * @param startTimes Array of start times of each round
     * @param allocations Array of token allocation per round
     */
    function setupRounds(uint128[] calldata startTimes, uint128[] calldata allocations) external onlyOwner {
        // can only be ran once
        if(setupComplete == 1) revert AlreadySetup();

        // input validation
        uint256 startTimesLength = startTimes.length;
        uint256 allocationsLength = allocations.length;

        if(startTimesLength == 0) revert EmptyArray(); 
        if(startTimesLength != allocationsLength) revert IncorrectLengths();

        // update rounds
        uint256 totalAmount;
        uint256 prevStartTime = block.timestamp;
        for(uint256 i = 0; i < startTimesLength; ++i) {         

            uint128 startTime = startTimes[i];
            uint128 allocation = allocations[i];
            
            // startTime check
            if(startTime <= prevStartTime) revert IncorrectStartTime();
            prevStartTime = startTime;

            // allocation check: non-zero
            if(allocation == 0) revert IncorrectAllocation();

            // update storage 
            allRounds[i] = RoundData({startTime: startTime, allocation: allocation, deposited:0, claimed:0});
            
            // increment
            totalAmount += allocation;
        }

        // update storage
        numberOfRounds = startTimesLength;
        lastClaimTime = startTimes[startTimesLength-1];
        setupComplete = 1;


        emit SetupRounds(startTimesLength, startTimes[0], startTimes[startTimesLength-1], totalAmount);
    }


    /**
     * @notice Owner to update deadline variable
     * @dev By default deadline = 0 
     * @param newDeadline must be after last claim round + 14 days
     */
    function updateDeadline(uint256 newDeadline) external onlyOwner {
        // can only be called after setupRounds 
        if(setupComplete == 0) revert NotSetup();

        // allow for 14 days buffer: prevent malicious premature ending
        if (newDeadline < lastClaimTime + 14 days) revert InvalidNewDeadline();

        deadline = newDeadline;
        emit DeadlineUpdated(newDeadline);
    }

    /**
     * @notice Owner to update operator address
     * @dev Operator role allows calling of deposit and withdraw fns
     * @param newOperator new address
     */
    function updateOperator(address newOperator) external onlyOwner {
        address oldOperator = operator;

        operator = newOperator;

        emit OperatorUpdated(oldOperator, newOperator);

    }

    /*//////////////////////////////////////////////////////////////
                                OPERATOR
    //////////////////////////////////////////////////////////////*/

    
    /**
     * @notice Operator to deposit the total tokens required for specified rounds
     * @dev Operator can fund all rounds at once or incrementally fund, 
            so to avoid having to commit a large initial sum
     * @param rounds Array of rounds which are being financed. First round index = 0.
     */
    function deposit(uint256[] calldata rounds) external {
        if(msg.sender != operator) revert IncorrectCaller(); 

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
        if (TOKEN.balanceOf(address(this)) - before != totalAmount) revert TaxTokenCheckFailed(); 
    }

    /**
     * @notice Operator to withdraw all unclaimed tokens past the specified deadline
     * @dev Only possible if deadline has been defined and exceeded
     */
    function withdraw() external {
        if(msg.sender != operator) revert IncorrectCaller(); 

        // if deadline is not defined; cannot withdraw
        if(deadline == 0) revert WithdrawDisabled();
        
        // can only withdraw after deadline
        if(block.timestamp <= deadline) revert PrematureWithdrawal();

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
     * @notice Unpause claim. Cannot unpause once frozen
     */
    function unpause() external onlyOwner whenPaused {
        if(isFrozen == 1) revert IsFrozen(); 

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
        if(isFrozen == 1) revert IsFrozen(); 
        
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
        if(isFrozen == 0) revert NotFrozen();

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