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
        function transferFrom(address from, address to, uint256 amount) external returns (bool);
        event Transfer(address indexed from, address indexed to, uint256 value);
        event Approval(address indexed owner, address indexed spender, uint256 value);
    }

    /// @dev Optional EIP-2612 permit interface
    interface IERC20Permit {
        function permit(
            address owner,
            address spender,
            uint256 value,
            uint256 deadline,
            uint8 v,
            bytes32 r,
            bytes32 s
        ) external;
        function nonces(address owner) external view returns (uint256);
        function DOMAIN_SEPARATOR() external view returns (bytes32);
    }

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error NotOwner();
    error Paused();
    error Reentrancy();
    error ZeroAmount();
    error ZeroAddress();
    error TokenAlreadyAdded();
    error RewardTokenNotFound();
    error InvalidDuration();
    error TooEarly();
    error TransferFailed();
    error BadArrayLengths();
    error TooManyRewardTokens();
    error NothingToClaim();

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event PausedStateChanged(bool paused);

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, address indexed rewardToken, uint256 amount);

    event RewardTokenAdded(address indexed rewardToken, uint256 duration);
    event RewardsNotified(address indexed rewardToken, uint256 amount, uint256 duration, uint256 rewardRate);

    event Rescue(address indexed token, address indexed to, uint256 amount);

    // -------------------------------------------------------------------------
    // Owner / Pause / Reentrancy
    // -------------------------------------------------------------------------

    address public owner;
    bool public isPaused;

    uint256 private _locked = 1;

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier whenNotPaused() {
        if (isPaused) revert Paused();
        _;
    }

    modifier nonReentrant() {
        if (_locked != 1) revert Reentrancy();
        _locked = 2;
        _;
        _locked = 1;
    }

    // -------------------------------------------------------------------------
    // Core staking state
    // -------------------------------------------------------------------------

    IERC20 public immutable stakingToken;

    uint256 public totalStaked;
    mapping(address => uint256) public stakedBalance;

    // -------------------------------------------------------------------------
    // Multi-reward accounting
    // -------------------------------------------------------------------------

    // Typical rewards distribution math (similar to Synthetix/StakingRewards):
    // rewardPerTokenStored increases over time: (timeDelta * rewardRate * 1e18 / totalStaked)
    // userRewardPerTokenPaid tracks the user's checkpoint for each reward token
