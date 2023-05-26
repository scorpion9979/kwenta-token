// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IStakingRewardsV2 {
    /*//////////////////////////////////////////////////////////////
                                Structs
    //////////////////////////////////////////////////////////////*/

    // TODO: store block on here also!!!
    /// @notice A checkpoint for tracking values at a given timestamp
    struct Checkpoint {
        // The timestamp when the value was generated
        uint256 ts;
        // The value of the checkpoint
        uint256 value;
    }

    /*///////////////////////////////////////////////////////////////
                                INITIALIZER
    ///////////////////////////////////////////////////////////////*/

    /// @notice configure StakingRewards state
    /// @dev owner set to address that deployed StakingRewards
    /// @param _token: token used for staking and for rewards
    /// @param _rewardEscrow: escrow contract which holds (and may stake) reward tokens
    /// @param _supplySchedule: handles reward token minting logic
    /// @param _stakingRewardsV1: previous version of staking rewards contract - used for reward calculations
    /// @param _owner: owner of this contract
    /// @dev this function should be called via proxy, not via direct contract interaction
    function initialize(
        address _token,
        address _rewardEscrow,
        address _supplySchedule,
        address _stakingRewardsV1,
        address _owner
    ) external;

    /*//////////////////////////////////////////////////////////////
                                Views
    //////////////////////////////////////////////////////////////*/
    // token state

    /// @dev returns staked tokens which will likely not be equal to total tokens
    /// in the contract since reward and staking tokens are the same
    /// @return total amount of tokens that are being staked
    function totalSupply() external view returns (uint256);

    /// @notice Getter function for the total number of v1 staked tokens
    /// @return amount of tokens staked in v1
    function v1TotalSupply() external view returns (uint256);

    // staking state

    /// @notice Returns the total number of staked tokens for a user
    /// the sum of all escrowed and non-escrowed tokens
    /// @param account: address of potential staker
    /// @return amount of tokens staked by account
    function balanceOf(address account) external view returns (uint256);

    /// @notice Getter function for the number of v1 staked tokens
    /// @param account address to check the tokens staked
    /// @return amount of tokens staked
    function v1BalanceOf(address account) external view returns (uint256);

    /// @notice Getter function for number of staked escrow tokens
    /// @param account address to check the escrowed tokens staked
    /// @return amount of escrowed tokens staked
    function escrowedBalanceOf(address account) external view returns (uint256);

    /// @notice Getter function for number of staked non-escrow tokens
    /// @param account address to check the non-escrowed tokens staked
    /// @return amount of non-escrowed tokens staked
    function nonEscrowedBalanceOf(address account) external view returns (uint256);

    // rewards

    /// @notice calculate the total rewards for one duration based on the current rate
    /// @return rewards for the duration specified by rewardsDuration
    function getRewardForDuration() external view returns (uint256);

    /// @notice calculate running sum of reward per total tokens staked
    /// at this specific time
    /// @return running sum of reward per total tokens staked
    function rewardPerToken() external view returns (uint256);

    /// @notice get the last time a reward is applicable for a given user
    /// @return timestamp of the last time rewards are applicable
    function lastTimeRewardApplicable() external view returns (uint256);

    /// @notice determine how much reward token an account has earned thus far
    /// @param account: address of account earned amount is being calculated for
    function earned(address account) external view returns (uint256);

    // checkpointing

    /// @notice get the number of balances checkpoints for an account
    /// @param account: address of account to check
    /// @return number of balances checkpoints
    function balancesLength(address account) external view returns (uint256);

    /// @notice get the number of escrowed balance checkpoints for an account
    /// @param account: address of account to check
    /// @return number of escrowed balance checkpoints
    function escrowedBalancesLength(address account) external view returns (uint256);

    /// @notice get the number of total supply checkpoints
    /// @return number of total supply checkpoints
    function totalSupplyLength() external view returns (uint256);

    /// @notice get a users balance at a given timestamp
    /// @param account: address of account to check
    /// @param _timestamp: timestamp to check
    /// @return balance at given timestamp
    function balanceAtTime(address account, uint256 _timestamp) external view returns (uint256);

    /// @notice get a users escrowed balance at a given timestamp
    /// @param account: address of account to check
    /// @param _timestamp: timestamp to check
    /// @return escrowed balance at given timestamp
    function escrowedbalanceAtTime(address account, uint256 _timestamp)
        external
        view
        returns (uint256);

    /// @notice get the total supply at a given timestamp
    /// @param _timestamp: timestamp to check
    /// @return total supply at given timestamp
    function totalSupplyAtTime(uint256 _timestamp) external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                                Mutative
    //////////////////////////////////////////////////////////////*/
    // Staking/Unstaking

    /// @notice stake token
    /// @param amount: amount to stake
    /// @dev updateReward() called prior to function logic
    function stake(uint256 amount) external;

    /// @notice unstake token
    /// @param amount: amount to unstake
    /// @dev updateReward() called prior to function logic
    function unstake(uint256 amount) external;

    /// @notice stake escrowed token
    /// @param account: address which owns token
    /// @param amount: amount to stake
    /// @dev updateReward() called prior to function logic
    /// @dev msg.sender NOT used (account is used)
    function stakeEscrow(address account, uint256 amount) external;

    /// @notice stake escrowed token on behalf of another account
    /// @param account: address which owns token
    /// @param amount: amount to stake
    function stakeEscrowOnBehalf(address account, uint256 amount) external;

    /// @notice unstake escrowed token
    /// @param account: address which owns token
    /// @param amount: amount to unstake
    /// @dev updateReward() called prior to function logic
    /// @dev msg.sender NOT used (account is used)
    function unstakeEscrow(address account, uint256 amount) external;

    /// @notice unstake escrowed token skipping the cooldown wait period
    /// @param account: address which owns token
    /// @param amount: amount to unstake
    /// @dev this function is used to allow tokens to be vested at any time by RewardEscrowV2
    function unstakeEscrowSkipCooldown(address account, uint256 amount) external;

    /// @notice unstake all available staked non-escrowed tokens and
    /// claim any rewards
    function exit() external;

    // claim rewards

    /// @notice caller claims any rewards generated from staking
    /// @dev rewards are escrowed in RewardEscrow
    /// @dev updateReward() called prior to function logic
    function getReward() external;

    /// @notice caller claims any rewards generated from staking on behalf of another account
    /// The rewards will be escrowed in RewardEscrow with the account as the beneficiary
    /// @param account: address which owns token
    function getRewardOnBehalf(address account) external;

    // settings

    /// @notice configure reward rate
    /// @param reward: amount of token to be distributed over a period
    /// @dev updateReward() called prior to function logic (with zero address)
    function notifyRewardAmount(uint256 reward) external;

    /// @notice set rewards duration
    /// @param _rewardsDuration: denoted in seconds
    function setRewardsDuration(uint256 _rewardsDuration) external;

    /// @notice set unstaking cooldown period
    /// @param _cooldownPeriod: denoted in seconds
    function setCooldownPeriod(uint256 _cooldownPeriod) external;

    // pausable

    /// @dev Triggers stopped state
    function pauseStakingRewards() external;

    /// @dev Returns to normal state.
    function unpauseStakingRewards() external;

    // misc.

    /// @notice approve an operator to collect rewards and stake escrow on behalf of the sender
    /// @param operator: address of operator to approve
    /// @param approved: whether or not to approve the operator
    function approveOperator(address operator, bool approved) external;

    /// @notice added to support recovering LP Rewards from other systems
    /// such as BAL to be distributed to holders
    /// @param tokenAddress: address of token to be recovered
    /// @param tokenAmount: amount of token to be recovered
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external;

    /*///////////////////////////////////////////////////////////////
                                EVENTS
    ///////////////////////////////////////////////////////////////*/

    /// @notice update reward rate
    /// @param reward: amount to be distributed over applicable rewards duration
    event RewardAdded(uint256 reward);

    /// @notice emitted when user stakes tokens
    /// @param user: staker address
    /// @param amount: amount staked
    event Staked(address indexed user, uint256 amount);

    /// @notice emitted when user unstakes tokens
    /// @param user: address of user unstaking
    /// @param amount: amount unstaked
    event Unstaked(address indexed user, uint256 amount);

    /// @notice emitted when escrow staked
    /// @param user: owner of escrowed tokens address
    /// @param amount: amount staked
    event EscrowStaked(address indexed user, uint256 amount);

    /// @notice emitted when staked escrow tokens are unstaked
    /// @param user: owner of escrowed tokens address
    /// @param amount: amount unstaked
    event EscrowUnstaked(address user, uint256 amount);

    /// @notice emitted when user claims rewards
    /// @param user: address of user claiming rewards
    /// @param reward: amount of reward token claimed
    event RewardPaid(address indexed user, uint256 reward);

    /// @notice emitted when rewards duration changes
    /// @param newDuration: denoted in seconds
    event RewardsDurationUpdated(uint256 newDuration);

    /// @notice emitted when tokens are recovered from this contract
    /// @param token: address of token recovered
    /// @param amount: amount of token recovered
    event Recovered(address token, uint256 amount);

    /// @notice emitted when the unstaking cooldown period is updated
    /// @param cooldownPeriod: the new unstaking cooldown period
    event CooldownPeriodUpdated(uint256 cooldownPeriod);

    /// @notice emitted when an operator is approved
    /// @param owner: owner of tokens
    /// @param operator: address of operator
    /// @param approved: whether or not operator is approved
    event OperatorApproved(address owner, address operator, bool approved);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice error someone other than reward escrow calls an onlyRewardEscrow function
    error OnlyRewardEscrow();

    /// @notice error someone other than the supply schedule calls an onlySupplySchedule function
    error OnlySupplySchedule();

    /// @notice error when user tries to stake/unstake 0 tokens
    error AmountZero();

    /// @notice the user does not have enough tokens to unstake that amount
    error InsufficientBalance();

    /// @notice previous rewards period must be complete before changing the duration for the new period
    error RewardsPeriodNotComplete();

    /// @notice recovering the staking token is not allowed
    error CannotRecoverStakingToken();

    /// @notice error when user tries unstake during the cooldown period
    /// @param canUnstakeAt timestamp when user can unstake
    error MustWaitForUnlock(uint256 canUnstakeAt);

    /// @notice error when trying to set a cooldown period below the minimum
    /// @param minCooldownPeriod minimum cooldown period
    error CooldownPeriodTooLow(uint256 minCooldownPeriod);

    /// @notice error when trying to set a cooldown period above the maximum
    /// @param maxCooldownPeriod maximum cooldown period
    error CooldownPeriodTooHigh(uint256 maxCooldownPeriod);

    /// @notice error when trying to stakeEscrow more than the unstakedEscrow available
    /// @param unstakedEscrow amount of unstaked escrow
    error InsufficientUnstakedEscrow(uint256 unstakedEscrow);

    /// @notice the caller is not approved to take this action
    error NotApproved();

    /// @notice attempted to approve self as an operator
    error CannotApproveSelf();
}
