// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {RewardEscrowV2} from "../../../../contracts/RewardEscrowV2.sol";
import {StakingRewardsV2} from "../../../../contracts/StakingRewardsV2.sol";
import {SupplySchedule} from "../../../../contracts/SupplySchedule.sol";
import {Kwenta} from "../../../../contracts/Kwenta.sol";
import {Test} from "../../../../lib/forge-std/src/Test.sol";

address constant KWENTA = 0xDA0C33402Fc1e10d18c532F0Ed9c1A6c5C9e386C;
address constant STAKING_REWARDS_V2_IMPLEMENTATION = 0xE0aD43191312D6220DE64aFA54dbdD6982991A87;
address constant STAKING_REWARDS_V2_PROXY = 0x3e5371D909Bf1996c95e9D179b0Bc91C26fb1279;
address constant REWARD_ESCROW_V2_IMPLEMENTATION = 0x0A34aee61770b3cE293Fb17CfC9d4a7F70945260;
address constant REWARD_ESCROW_V2_PROXY = 0xf211F298C6985fF4cF6f9488e065292B818163F8;
address constant SUPPLY_SCHEDULE = 0x671423b2e8a99882FD14BbD07e90Ae8B64A0E63A;
address constant DAO = 0xC2ecD777d06FFDF8B3179286BEabF52B67E9d991;
address constant EOA = 0x42f9134E9d3Bf7eEE1f8A5Ac2a4328B059E7468c;
uint256 constant TEST_AMOUNT = 10_000 ether;
uint256 constant ONE_YEAR = 52 weeks;

// BLOCK_NUMBER corresponds to Jul-12-2023 02:16:54 PM +UTC
uint256 constant BLOCK_NUMBER = 11_871_673;

contract UpgradeRewardEscrowV2Test is Test {
    // contracts
    RewardEscrowV2 public rewardEscrowV3;
    RewardEscrowV2 public rewardEscrowProxy;

    struct VestingEntry {
        // The amount of KWENTA stored in this vesting entry
        uint256 escrowAmount;
        // The length of time until the entry is fully matured
        uint256 duration;
        // The time at which the entry will be fully matured
        uint64 endTime;
        // The percentage fee for vesting immediately
        // The actual penalty decreases linearly with time until it reaches 0 at block.timestamp=endTime
        uint8 earlyVestingFee;
    }

    /*//////////////////////////////////////////////////////////////
                            SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        rewardEscrowProxy = rewardEscrowProxy;
        vm.rollFork(BLOCK_NUMBER);
        // deploy V3 implementation
        rewardEscrowV3 = new RewardEscrowV2();
    }

    /*//////////////////////////////////////////////////////////////
                            TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice make sure the factory upgraded to the new implementation
    function testUpgradedImplementationAddress() public {
        // upgrade
        vm.prank(DAO);
        RewardEscrowV2(rewardEscrowProxy).upgradeTo(address(rewardEscrowV3));
        assertEq(
            rewardEscrowProxy.implementation(),
            address(rewardEscrowV3)
        );
        assertTrue(address(rewardEscrowV3) != REWARD_ESCROW_V2_IMPLEMENTATION);
    }

    /// @notice make sure the state did not change from the upgrade
    function testUpgrade() public {
        // record state prior to upgrade
        uint maxDuration = rewardEscrowProxy.MAX_DURATION();
        uint defaultDuration = rewardEscrowProxy.DEFAULT_DURATION();
        uint defaultEarlyVestingFee = rewardEscrowProxy
            .DEFAULT_EARLY_VESTING_FEE();
        uint maximumEarlyVestingFee = rewardEscrowProxy
            .MAXIMUM_EARLY_VESTING_FEE();
        uint minimumEarlyVestingFee = rewardEscrowProxy
            .MINIMUM_EARLY_VESTING_FEE();
        StakingRewardsV2 stakingRewards = rewardEscrowProxy
            .stakingRewards();
        address treasuryDAO = rewardEscrowProxy.treasuryDAO();
        VestingEntry memory entry = rewardEscrowProxy.vestingSchedules(0);
        uint nextEntryId = rewardEscrowProxy.nextEntryId();
        uint totalEscrowedAccountBalance = rewardEscrowProxy
            .totalEscrowedAccountBalance(EOA);
        uint totalVestedAccountBalance = rewardEscrowProxy
            .totalVestedAccountBalance(EOA);
        uint totalEscrowedBalance = rewardEscrowProxy
            .totalEscrowedBalance();
        address earlyVestFeeDistributor = rewardEscrowProxy
            .earlyVestFeeDistributor();

        // upgrade
        vm.prank(DAO);
        rewardEscrowProxy.upgradeTo(address(rewardEscrowV3));
        assertEq(
            rewardEscrowProxy.implementation(),
            address(rewardEscrowV3)
        );
        assertTrue(address(rewardEscrowV3) != REWARD_ESCROW_V2_IMPLEMENTATION);

        // check state did not change
        assertEq(maxDuration, rewardEscrowProxy.MAX_DURATION());
        assertEq(defaultDuration, rewardEscrowProxy.DEFAULT_DURATION());
        assertEq(
            defaultEarlyVestingFee,
            rewardEscrowProxy.DEFAULT_EARLY_VESTING_FEE()
        );
        assertEq(
            maximumEarlyVestingFee,
            rewardEscrowProxy.MAXIMUM_EARLY_VESTING_FEE()
        );
        assertEq(
            minimumEarlyVestingFee,
            rewardEscrowProxy.MINIMUM_EARLY_VESTING_FEE()
        );
        assertEq(
            address(stakingRewards),
            rewardEscrowProxy.stakingRewards()
        );
        assertEq(treasuryDAO, rewardEscrowProxy.treasuryDAO());
        assertEq(
            entry.amount,
            rewardEscrowProxy.vestingSchedules(0).amount
        );
        assertEq(nextEntryId, rewardEscrowProxy.nextEntryId());
        assertEq(
            totalEscrowedAccountBalance,
            rewardEscrowProxy.totalEscrowedAccountBalance(EOA)
        );
        assertEq(
            totalVestedAccountBalance,
            rewardEscrowProxy.totalVestedAccountBalance(EOA)
        );
        assertEq(
            totalEscrowedBalance,
            rewardEscrowProxy.totalEscrowedBalance()
        );
        assertEq(
            earlyVestFeeDistributor,
            rewardEscrowProxy.earlyVestFeeDistributor()
        );
    }
}
