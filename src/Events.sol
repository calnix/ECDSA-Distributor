// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

event Claimed(address indexed user, uint128 indexed round, uint128 amount);
event ClaimedMultiple(address indexed user, uint128[] rounds, uint128 totalAmount);
event SetupRounds(uint256 numOfRounds, uint256 firstClaimTime, uint256 lastClaimTime, uint256 totalAmount);
event DeadlineUpdated(uint256 indexed newDeadline);
event Deposited(address indexed operator, uint256 amount);
event Withdrawn(address indexed operator, uint256 amount);
event OperatorUpdated(address oldOperator, address newOperator);
event Frozen(uint256 indexed timestamp);
event EmergencyExit(address receiver, uint256 balance);