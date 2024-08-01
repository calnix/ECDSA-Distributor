// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { ECDSADistributor } from "src/ECDSADistributor.sol";

contract MockAttackContract {

    address public distributor;


    constructor(address target){
        distributor = target;
    }

    function claim(uint128 round, uint128 amount, bytes calldata signature) public {

        ECDSADistributor(distributor).claim(round, amount, signature);
    }

    function claimMultiple(uint128[] calldata rounds, uint128[] calldata amounts, bytes[] calldata signatures) public {
        
        ECDSADistributor(distributor).claimMultiple(rounds, amounts, signatures);
    }


}



/**

user -> attack contract -> distributor -> token callback -> attack contract -> distributor,

*/ 