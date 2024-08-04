// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { ERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MockTaxToken is ERC20("TEST", "TST") {

    function _update(address from, address to, uint256 value) internal override {
        uint256 valuePostTax = value - 1 ether;
        super._update(from, to, valuePostTax);
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }

}

