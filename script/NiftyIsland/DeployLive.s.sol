// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";

import {ECDSADistributor} from "./../../src/ECDSADistributor.sol";

contract DeployLive is Script {

    ECDSADistributor public distributor;

    function setUp() public {}

    function run() public {
        
        //get env
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_ACTUAL");
        address deployerAddr = vm.envAddress("PUBLIC_KEY_ACTUAL");
        vm.startBroadcast(deployerPrivateKey);    

        // constructor params
        string memory name = "NiftyIsland"; 
        string memory version = "v1";

        // note: update
        address token = address(0);
        address storedSigner = address(0);
        address operator = address(0);
        address owner = deployerAddr;

        distributor = new ECDSADistributor(name, version, token, storedSigner, owner, operator);

        //-------------- setup
        uint128[] memory startTimes = new uint128[](2);
            startTimes[0] = uint128(0);         // note: update

        uint128[] memory allocations = new uint128[](2);
            allocations[0] = 10_000_000 ether;  // note: update

        distributor.setupRounds(startTimes, allocations);


        //-------------- update deadline
        uint256 newDeadline = startTimes[0] + 90 days;
        distributor.updateDeadline(newDeadline);



        //-------------- handover ownership
        address ownerMulti = address(0);             // note: update
        distributor.transferOwnership(ownerMulti);

        vm.stopBroadcast();
    }
        
}

// forge script script/DeployTest.s.sol:DeployTestnet --rpc-url mainnet --broadcast --verify -vvvvv --etherscan-api-key mainnet


/**
    1. DAT team has to accept ownership
    2. call acceptOwnership fn on contract 
 */


/**
    name: ProjectName
    version: Incremented on each deployment starting from v1
            - if new distribution in the future, increment
            - if redeploy due to errors/issues, increment
 */