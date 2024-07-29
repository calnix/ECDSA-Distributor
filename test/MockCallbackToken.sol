// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { ERC20Reentrant } from "openzeppelin-contracts/contracts/mocks/token/ERC20Reentrant.sol";

contract MockCallbackToken is ERC20Reentrant {

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }
}