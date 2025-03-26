// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";

import {ECDSADistributor} from "./../../src/ECDSADistributor.sol";

import {MockToken} from "./../MockERC20.sol";

contract DeployRDACTest is Script {

    MockToken public mockToken;
    ECDSADistributor public distributor;

    function run() public {
        
        //get env: note use mocaDrop_privKey
        uint256 deployerPrivateKey = vm.envUint("mocaDrop_test_privKey");
        address deployerAddr = vm.envAddress("mocaDrop_test_pubKey");

        vm.startBroadcast(deployerPrivateKey);    

        // constructor params
        string memory name = "Dummy"; 
        string memory version = "v1";

        //deploy dummy+mint
        mockToken = new MockToken("MockToken","MT");
        mockToken.mint(deployerAddr, 1_000_000 ether);


        // note: update
        address token = address(mockToken);
        address storedSigner = 0xda6cFe8ddb47C8f1129bA6D9e20209f7d9c1829A;
        address operator = deployerAddr; 
        address owner = deployerAddr;

        distributor = new ECDSADistributor(name, version, token, storedSigner, owner, operator);

        //-------------- setup
        uint128[] memory startTimes = new uint128[](1);
            startTimes[0] = uint128(block.timestamp + 100);         // note: update

        uint128[] memory allocations = new uint128[](1);
            allocations[0] = 1_000_000 ether;                     // note: update

        distributor.setupRounds(startTimes, allocations);


        //-------------- update deadline
        uint256 newDeadline = startTimes[0] + 90 days;
        distributor.updateDeadline(newDeadline);

        //-------------- handover ownership
        //address ownerMulti = address(0);             // note: update
        //distributor.transferOwnership(ownerMulti);

        vm.stopBroadcast();
    }
}

// forge script script/RDAC/DeployRDACTest.s.sol:DeployRDACTest --rpc-url base --broadcast --verify -vvvvv --etherscan-api-key base

