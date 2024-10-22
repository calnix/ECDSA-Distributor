// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";

import "./../src/ECDSADistributor.sol";
import {ERC20Mock} from "./../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

contract DeployTestnet is Script {

    ERC20Mock public mockToken;
    ECDSADistributor public distributor;

    function setUp() public {}

    function run() public {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_TEST");
        vm.startBroadcast(deployerPrivateKey);    

        mockToken = new ERC20Mock();

        string memory name = "test"; 
        string memory version = "v1";
        address token = address(mockToken);
        address storedSigner = 0xDf56A8382aDAcC45e394a5632a22ef144D37E282;
        address owner = 0x8C9C001F821c04513616fd7962B2D8c62f925fD2;
        address operator_ = 0x8C9C001F821c04513616fd7962B2D8c62f925fD2;

        distributor = new ECDSADistributor(name, version, token, storedSigner, owner, operator_);

        //setup
        uint128[] memory startTimes = new uint128[](2);
            startTimes[0] = uint128(block.timestamp + 120);
            startTimes[1] = uint128(startTimes[0] + 120);

        uint128[] memory allocations = new uint128[](2);
            allocations[0] = 10 ether;
            allocations[1] = 10 ether;

        distributor.setupRounds(startTimes, allocations);

        // deposit
        uint256[] memory rounds = new uint256[](2);
            rounds[0] = 0;
            rounds[0] = 1;
        
        mockToken.mint(operator_, 20 ether);
        mockToken.approve(address(distributor), 20 ether);

        distributor.deposit(rounds);

        vm.stopBroadcast();
    }
        
}

// forge script script/DeployTest.s.sol:DeployTestnet --rpc-url sepolia --broadcast --verify -vvvvv --etherscan-api-key sepolia
