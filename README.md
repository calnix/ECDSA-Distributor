# Airdrop distributor contract

Use ECDSA if more than 127 users - gas savings. 
https://x.com/Jeyffre/status/1807008534477058435



## Deploy

Deploy ECDSA contract. Deployment requires following specification:
1. network 
2. token address
3.  storedSigner (pub-key of the keypair generating signatures - get from @Ming Shum )
4. owner (multi-sig)
5. operator 
6. deadline (optional)

(deadline must be at least after last claim round + 14 days)

::OPERATOR::
Operator can call deposit()/withdraw() to handle asset in/outflows.

After Deployment, OPERATOR to call deposit.
-  deposit(uint256[] calldata rounds)
- able to deposit for all rounds or partial deposit

Withdraw can only be called if deadline has been defined and exceeded.

::OWNER::
Owner able to pause/unpause/freeze/recover assets in emergency. 
Owner can change designated operator address.

::PROCESS::
1. deploy contract 
2. operator calls deposit()
3. any ownership transfer


This naturally is the ideal process. Details should give you enough colour to figure out how to manoeuvre in odd situations.



## Risk

From a risk perspective, it might seem that relying on DAT team to pause the contract is an issue due to delay in their response.

However, there is a soft pause switch, in that we can simply take the BE offline and not provide signatures. Users cannot claim.

So we really don’t need to be the owner of the contract, unless there has been a breach of contract security and tokens need to be exfiltrated via freeze and emergencyExit. For that very reason, the Owner role should be secured by a multi-sig. Its a press button in case of emergency, but due its permanence, done premeditatively - not rushed. 