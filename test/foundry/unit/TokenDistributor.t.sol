// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {TokenDistributor} from "../../../contracts/TokenDistributor.sol";
import {Kwenta} from "../../../contracts/Kwenta.sol";
import {StakingRewardsV2} from "../../../contracts/StakingRewardsV2.sol";
import {RewardEscrowV2} from "../../../contracts/RewardEscrowV2.sol";
import {TestHelpers} from "../utils/TestHelpers.t.sol";
import "forge-std/Test.sol";

contract TokenDistributorTest is TestHelpers {
    event CheckpointToken(uint time, uint tokens);
    event VestingEntryCreated(
        address indexed beneficiary,
        uint256 value,
        uint256 duration,
        uint256 entryID
    );

    TokenDistributor public tokenDistributor;
    Kwenta public kwenta;
    StakingRewardsV2 public stakingRewardsV2;
    RewardEscrowV2 public rewardEscrowV2;
    address public user;
    address public user2;

    function setUp() public {
        /// @dev starts after a week so the startTime is != 0
        goForward(604801);
        user = payable(
            address(uint160(uint256(keccak256(abi.encodePacked("user")))))
        );
        user2 = payable(
            address(uint160(uint256(keccak256(abi.encodePacked("user2")))))
        );
        kwenta = new Kwenta(
            "Kwenta",
            "Kwe",
            100000,
            address(this),
            address(this)
        );
        rewardEscrowV2 = new RewardEscrowV2(address(this), address(kwenta));
        /// @dev kwenta is plugged in for all parameters except rewardEscrowV2 to control variables
        /// functions that are used by TokenDistributor shouldn't need the other dependencies
        stakingRewardsV2 = new StakingRewardsV2(
            address(kwenta),
            address(rewardEscrowV2),
            address(kwenta),
            address(kwenta)
        );
        tokenDistributor = new TokenDistributor(
            address(kwenta),
            address(stakingRewardsV2),
            address(rewardEscrowV2)
        );
    }

    /// @notice checkpointToken happy case after 1 week
    function testCheckpointToken() public {
        kwenta.transfer(address(tokenDistributor), 10);
        kwenta.transfer(address(user), 1);
        vm.startPrank(address(user));
        kwenta.approve(address(stakingRewardsV2), 1);
        stakingRewardsV2.stake(1);
        goForward(604801);

        vm.expectEmit(true, true, true, true);
        emit CheckpointToken(1209603, 10);
        tokenDistributor.checkpointToken();
    }

    /// @notice claimEpoch happy case
    function testClaimEpoch() public {
        //setup

        kwenta.transfer(address(tokenDistributor), 10);
        kwenta.transfer(address(user), 1);
        vm.startPrank(address(user));
        kwenta.approve(address(stakingRewardsV2), 1);
        stakingRewardsV2.stake(1);
        uint startTime = (block.timestamp / 1 weeks) * 1 weeks;
        console.log(startTime);
        goForward(604801);

        vm.expectEmit(true, true, true, true);
        emit CheckpointToken(1209603, 10);
        vm.expectEmit(true, true, false, true);
        //todo: figure out why the amount is 9 not 10
        emit VestingEntryCreated(address(user), 9, 31449600, 1);
        tokenDistributor.claimEpoch(address(user), 0);
    }

    /// @notice claimDistribution fail - epoch is not ready to claim
    function testClaimDistributionEpochNotReady() public {
        vm.startPrank(user);

        goForward(304801);
        vm.expectRevert(
            abi.encodeWithSelector(TokenDistributor.CannotClaimYet.selector)
        );
        tokenDistributor.claimEpoch(address(user), 0);
    }

    /// @notice claimDistribution fail - epoch is not ready to claim, not an epoch yet
    function testClaimDistributionEpochAhead() public {
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(TokenDistributor.CannotClaimYet.selector)
        );
        tokenDistributor.claimEpoch(address(user), 7);
    }

    /// @notice claimDistribution fail - no epoch to claim yet
    function testClaimDistributionNoEpochYet() public {
        vm.startPrank(user);
        vm.expectRevert();
        tokenDistributor.claimEpoch(address(user), 0);
    }
    //
    //temporarily comment out every other test for compiling
    //
    /*
    /// @notice claimDistribution fail - cant claim in same block as new distribution
    function testClaimDistributionNewDistributionBlock() public {
        kwenta.transfer(address(tokenDistributor), 10);
        kwenta.transfer(address(user), 1);
        vm.startPrank(address(user));
        kwenta.approve(address(stakingRewardsV2), 1);
        stakingRewardsV2.stake(1);
        tokenDistributor.newDistribution();
        goForward(604801);

        tokenDistributor.newDistribution();
        vm.expectRevert(
            abi.encodeWithSelector(TokenDistributor.CannotClaimInNewDistributionBlock.selector)
        );
        tokenDistributor.claimDistribution(address(user), 1);
    }
    
    /// @notice claimDistribution fail - already claimed
    function testClaimDistributionAlreadyClaimed() public {
        //setup
        kwenta.transfer(address(tokenDistributor), 10);
        kwenta.transfer(address(user), 1);
        vm.startPrank(address(user));
        kwenta.approve(address(stakingRewardsV2), 1);
        stakingRewardsV2.stake(1);
        tokenDistributor.newDistribution();
        goForward(604801);
        vm.expectEmit(true, true, true, true);
        emit NewEpochCreated(604802, 1);
        tokenDistributor.claimDistribution(address(user), 0);

        vm.expectRevert(
            abi.encodeWithSelector(TokenDistributor.CannotClaimTwice.selector)
        );
        tokenDistributor.claimDistribution(address(user), 0);
    }

    /// @notice claimDistribution fail - claim an epoch that had no staking
    function testClaimDistributionNoStaking() public {
        kwenta.transfer(address(tokenDistributor), 10);
        kwenta.transfer(address(user), 1);
        vm.prank(user);
        tokenDistributor.newDistribution();
        goForward(604801);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                TokenDistributor.NothingStakedThatEpoch.selector
            )
        );
        tokenDistributor.claimDistribution(address(user), 0);
    }

    /// @notice claimDistribution fail - nonstaker tries to claim
    /// (cannot claim 0 fees)
    function testClaimDistributionNotStaker() public {
        //setup
        kwenta.transfer(address(tokenDistributor), 10);
        kwenta.transfer(address(user), 1);
        vm.startPrank(address(user));
        kwenta.approve(address(stakingRewardsV2), 1);
        stakingRewardsV2.stake(1);
        tokenDistributor.newDistribution();
        goForward(604801);
        vm.expectEmit(true, true, true, true);
        emit NewEpochCreated(604802, 1);
        tokenDistributor.claimDistribution(address(user), 0);
        vm.stopPrank();

        vm.prank(user2);
        vm.expectRevert(
            abi.encodeWithSelector(TokenDistributor.CannotClaim0Fees.selector)
        );
        tokenDistributor.claimDistribution(address(user2), 0);
    }

    /// @notice claimDistribution happy case with a person who
    /// was previously staked but is now unstaked and trying to
    /// claim their fees
    function testClaimDistributionPreviouslyStaked() public {
        //setup
        kwenta.transfer(address(tokenDistributor), 10);
        kwenta.transfer(address(user), 1);
        vm.startPrank(address(user));
        kwenta.approve(address(stakingRewardsV2), 1);
        stakingRewardsV2.stake(1);

        tokenDistributor.newDistribution();
        goForward(604801);
        vm.expectEmit(true, true, true, true);
        emit NewEpochCreated(604802, 1);
        tokenDistributor.newDistribution();

        goForward(1209601);
        stakingRewardsV2.balanceAtBlock(user, 1);
        stakingRewardsV2.unstake(1);
        stakingRewardsV2.balanceAtBlock(user, 1);
        tokenDistributor.newDistribution();
        goForward(604801);
        tokenDistributor.newDistribution();
        tokenDistributor.claimDistribution(address(user), 0);
    }

    /// @notice claimDistribution happy case with partial claims
    /// in earlier epochs 2 complete epochs with differing fees
    /// @dev also an integration test with RewardEscrowV2
    function testClaimDistributionMultipleClaims() public {
        /// @dev user has 1/3 total staking and user2 has 2/3
        /// before epoch #0 (same as during) TokenDistributor
        /// receives 1000 in fees
        kwenta.transfer(address(tokenDistributor), 1000);
        kwenta.transfer(address(user), 1);
        kwenta.transfer(address(user2), 2);
        vm.startPrank(address(user));
        kwenta.approve(address(stakingRewardsV2), 1);
        stakingRewardsV2.stake(1);
        vm.stopPrank();
        vm.startPrank(address(user2));
        kwenta.approve(address(stakingRewardsV2), 2);
        stakingRewardsV2.stake(2);
        vm.stopPrank();
        vm.prank(user);
        tokenDistributor.newDistribution();
        goForward(604801);

        /// @dev during epoch #1, user claims their fees from #0
        /// and TokenDistributor receives 5000 in fees

        vm.expectEmit(true, true, true, true);
        emit NewEpochCreated(604802, 1);
        tokenDistributor.newDistribution();
        kwenta.transfer(address(tokenDistributor), 5000);
        vm.prank(user);
        vm.expectEmit(true, true, false, true);
        emit VestingEntryCreated(address(user), 333, 31449600, 1);
        tokenDistributor.claimDistribution(address(user), 0);

        /// @dev user claims for epoch #1 to start epoch #2
        /// user2 also claims for #1 and #0
        /// and TokenDistributor receives 300 in fees

        goForward(604801);
        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit NewEpochCreated(1209603, 2);
        vm.expectEmit(true, true, false, true);
        emit VestingEntryCreated(address(user), 1666, 31449600, 2);
        tokenDistributor.claimDistribution(address(user), 1);
        goForward(1000);
        kwenta.transfer(address(tokenDistributor), 300);
        vm.prank(user2);
        vm.expectEmit(true, true, false, true);
        emit VestingEntryCreated(address(user2), 3333, 31449600, 3);
        tokenDistributor.claimDistribution(address(user2), 1);
        vm.prank(user2);
        vm.expectEmit(true, true, false, true);
        emit VestingEntryCreated(address(user2), 666, 31449600, 4);
        tokenDistributor.claimDistribution(address(user2), 0);
    }
    */
}
