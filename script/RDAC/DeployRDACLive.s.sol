// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";

import {ECDSADistributor} from "./../../src/ECDSADistributor.sol";


contract DeployRDACLive is Script {

    ECDSADistributor public distributor;

    function run() public {
        
        //get env: note use mocaDrop_privKey
        uint256 deployerPrivateKey = vm.envUint("mocaDrop_live_privKey");
        address deployerAddr = vm.envAddress("mocaDrop_live_pubKey");

        // 
        vm.startBroadcast(deployerPrivateKey);    

        // constructor params
        string memory name = "RDAC"; 
        string memory version = "v1";

        // note: update
        address token = 0xD3F68c6e8AeE820569D58AdF8d85d94489315192;
        address storedSigner = 0xe53a53F88E2a5731223dd206DD62F0A7Bea97193;
        address operator = 0x6F1F3322473B77838Eee6f5C4D10bb97945FAaaC; //mocadrop.eth
        address owner = deployerAddr;

        distributor = new ECDSADistributor(name, version, token, storedSigner, owner, operator);

        //-------------- setup
        uint128[] memory startTimes = new uint128[](1);
            startTimes[0] = uint128(1747131000);         

        uint128[] memory allocations = new uint128[](1);
            allocations[0] = 10_000_000 ether;  

        distributor.setupRounds(startTimes, allocations);


        //-------------- update deadline
        uint256 newDeadline = startTimes[0] + 90 days;
        distributor.updateDeadline(newDeadline);

        //-------------- handover ownership
        address ownerMulti = address(0x80aA3930722B2d941240554471106A56C8fc71f8);  // note: update
        distributor.transferOwnership(ownerMulti);

        vm.stopBroadcast();
    }
}

// forge script script/RDAC/DeployRDACLive.s.sol:DeployRDACLive --rpc-url base --broadcast --verify -vvvvv --etherscan-api-key base
