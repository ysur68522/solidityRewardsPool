// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MegaMultiRewardStaking
 * @notice Large example contract: stake one token, earn multiple reward tokens.
 *         - Users stake `stakingToken`
 *         - Owner can add reward tokens and fund/notify rewards for distribution
 *         - Users can withdraw + claim rewards
 *         - Includes pause, reentrancy guard, and optional permit-based staking
 *
 * NOTE: This is an educational example. Production use should rely on audited libraries.
 */
contract MegaMultiRewardStaking {
    // -------------------------------------------------------------------------
    // Interfaces
    // -------------------------------------------------------------------------

    interface IERC20 {
        function totalSupply() external view returns (uint256);
        function balanceOf(address) external view returns (uint256);
        function allowance(address owner, address spender) external view returns (uint256);
        function approve(address spender, uint256 amount) external returns (bool);
        function transfer(address to, uint256 amount) external returns (bool);
