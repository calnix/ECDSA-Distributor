# Airdrop distributor contract

Use ECDSA if more than 127 users - gas savings. 
https://x.com/Jeyffre/status/1807008534477058435

## Signatures

- signatures are generated per user, per round.
- therefore, if there are 3 rounds of claiming, each user would have 3 signatures.

## 1 single signature vs signature per round


### 1 single signature for all rounds

```solidity
    
    

    struct Claim {
        address user;
        uint128 totalAllocation;
    }

    mapping(address user => uint256 claimedAmount) claimed;
    
    struct RoundData {
        uint128 startTime;
        uint128 pcntReleased;
        uint128 depositedTokens;
        uint128 claimedTokens;
    }

    mapping(uint256 round => RoundData roundData) public allRounds;

    function claim(...) external {
        ...

        uint256 tokenClaimable = user.totalAllocation * pcntReleased;
        
        TOKEN.transfer(msg.sender, tokenClaimable);
    }


```