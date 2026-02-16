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
    // rewards[user][token] stores accrued rewards

    struct RewardData {
        bool exists;
        uint64 duration;            // reward distribution duration in seconds
        uint64 periodFinish;        // timestamp when current rewards period ends
        uint64 lastUpdateTime;      // last global update timestamp
        uint192 rewardRate;         // rewards per second
        uint256 rewardPerTokenStored; // scaled 1e18
    }

    uint256 public constant PRECISION = 1e18;
    uint256 public constant MAX_REWARD_TOKENS = 8;

    address[] public rewardTokens;
    mapping(address => RewardData) public rewardData;

    mapping(address => mapping(address => uint256)) public userRewardPerTokenPaid; // user => token => rptPaid
    mapping(address => mapping(address => uint256)) public rewards;                // user => token => accrued

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address _stakingToken) {
        if (_stakingToken == address(0)) revert ZeroAddress();
        owner = msg.sender;
        stakingToken = IERC20(_stakingToken);
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // -------------------------------------------------------------------------
    // View helpers
    // -------------------------------------------------------------------------

    function rewardTokenCount() external view returns (uint256) {
        return rewardTokens.length;
    }

    function rewardTokenAt(uint256 index) external view returns (address) {
        return rewardTokens[index];
    }

    function lastTimeRewardApplicable(address token) public view returns (uint256) {
        uint256 finish = rewardData[token].periodFinish;
        return block.timestamp < finish ? block.timestamp : finish;
    }

