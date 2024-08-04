// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

event Claimed(address indexed user, uint128 indexed round, uint128 amount);
event ClaimedMultiple(address indexed user, uint128[] rounds, uint128 totalAmount);
event SetupRounds(uint256 indexed numOfRounds, uint256 indexed firstClaimTime, uint256 indexed lastClaimTime, uint256 totalAmount);
event AddedRounds(uint256 indexed numOfRounds, uint256 indexed totalAmount, uint256 indexed lastClaimTime);
event DeadlineUpdated(uint256 indexed newDeadline);
event Deposited(address indexed operator, uint256 indexed amount);
event Withdrawn(address indexed operator, uint256 indexed amount);
event OperatorUpdated(address indexed oldOperator, address indexed newOperator);
event Frozen(uint256 indexed timestamp);
event EmergencyExit(address indexed receiver, uint256 indexed balance);