// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "forge-std/Test.sol";
import {StakingTestHelpers} from "../utils/helpers/StakingTestHelpers.t.sol";
import {Migrate} from "../../../scripts/Migrate.s.sol";
import {Kwenta} from "../../../contracts/Kwenta.sol";
import {RewardEscrow} from "../../../contracts/RewardEscrow.sol";
import {VestingEntries} from "../../../contracts/interfaces/IRewardEscrow.sol";
import {IEscrowMigrator} from "../../../contracts/interfaces/IEscrowMigrator.sol";
import {SupplySchedule} from "../../../contracts/SupplySchedule.sol";
import {StakingRewards} from "../../../contracts/StakingRewards.sol";
import {EscrowMigrator} from "../../../contracts/EscrowMigrator.sol";
import "../utils/Constants.t.sol";
import {EscrowMigratorTestHelpers} from "../utils/helpers/EscrowMigratorTestHelpers.t.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract StakingV2MigrationForkTests is EscrowMigratorTestHelpers {
    /*//////////////////////////////////////////////////////////////
                              PAUSABILITY
    //////////////////////////////////////////////////////////////*/

    function test_Pause_Is_Only_Owner() public {
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        escrowMigrator.pauseEscrowMigrator();
    }

    function test_Unpause_Is_Only_Owner() public {
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        escrowMigrator.unpauseEscrowMigrator();
    }

    function test_Pause_Register() public {
        // check initial state
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        // pause
        vm.prank(owner);
        escrowMigrator.pauseEscrowMigrator();

        // attempt to register and fail
        vm.prank(user1);
        vm.expectRevert("Pausable: paused");
        escrowMigrator.registerEntries(_entryIDs);

        // unpause
        vm.prank(owner);
        escrowMigrator.unpauseEscrowMigrator();

        // register and succeed
        vm.prank(user1);
        escrowMigrator.registerEntries(_entryIDs);

        checkStateAfterStepOne(user1, _entryIDs, true);
    }

    function test_Pause_Migrate() public {
        // register, vest and approve
        (uint256[] memory _entryIDs,,) = claimRegisterVestAndApprove(user1);

        // pause
        vm.prank(owner);
        escrowMigrator.pauseEscrowMigrator();

        // attempt to migrate and fail
        vm.prank(user1);
        vm.expectRevert("Pausable: paused");
        escrowMigrator.migrateEntries(user1, _entryIDs);

        // unpause
        vm.prank(owner);
        escrowMigrator.unpauseEscrowMigrator();

        // migrate and succeed
        vm.prank(user1);
        escrowMigrator.migrateEntries(user1, _entryIDs);

        checkStateAfterStepTwo(user1, _entryIDs);
    }

    /*//////////////////////////////////////////////////////////////
                              TEST TOTALS
    //////////////////////////////////////////////////////////////*/

    function test_Total_Registered() public {
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        // check initial state
        assertEq(escrowMigrator.totalRegistered(), 0);

        uint256 totalRegistered;
        for (uint256 i = 0; i < _entryIDs.length; i++) {
            uint256 entryID = _entryIDs[i];
            (, uint256 escrowAmount,) = rewardEscrowV1.getVestingEntry(user1, entryID);
            totalRegistered += escrowAmount;
        }

        // register
        registerEntries(user1, _entryIDs);

        // check final state
        assertEq(escrowMigrator.totalRegistered(), totalRegistered);
    }

    function test_Total_Registered_Fuzz(uint8 numToRegister) public {
        (uint256[] memory allEntryIDs,) = claimAndCheckInitialState(user1);
        uint256[] memory registeredEntryIDs = new uint256[](numToRegister);
        // check initial state
        assertEq(escrowMigrator.totalRegistered(), 0);

        uint256 totalRegistered;
        for (uint256 i = 0; i < min(allEntryIDs.length, numToRegister); i++) {
            uint256 entryID = allEntryIDs[i];
            (, uint256 escrowAmount,) = rewardEscrowV1.getVestingEntry(user1, entryID);
            totalRegistered += escrowAmount;
            registeredEntryIDs[i] = entryID;
        }

        // register
        registerEntries(user1, registeredEntryIDs);

        // check final state
        assertEq(escrowMigrator.totalRegistered(), totalRegistered);
    }

    function test_Total_Migrated() public {
        // register, vest and approve
        (uint256[] memory _entryIDs,,) = claimRegisterVestAndApprove(user1);

        // check initial state
        assertEq(escrowMigrator.totalMigrated(), 0);

        uint256 totalMigrated;
        for (uint256 i = 0; i < _entryIDs.length; i++) {
            uint256 entryID = _entryIDs[i];
            (uint256 escrowAmount,,,) = escrowMigrator.registeredVestingSchedules(user1, entryID);
            totalMigrated += escrowAmount;
        }

        // migrate
        migrateEntries(user1, _entryIDs);

        // check final state
        assertEq(escrowMigrator.totalMigrated(), totalMigrated);
    }

    function test_Total_Migrated_Fuzz(uint8 numToMigrate) public {
        // register, vest and approve
        (uint256[] memory allEntryIDs,,) = claimRegisterVestAndApprove(user1);
        uint256[] memory migratedEntryIDs = new uint256[](numToMigrate);

        // check initial state
        assertEq(escrowMigrator.totalMigrated(), 0);

        uint256 totalMigrated;
        for (uint256 i = 0; i < min(allEntryIDs.length, numToMigrate); i++) {
            uint256 entryID = allEntryIDs[i];
            (uint256 escrowAmount,,,) = escrowMigrator.registeredVestingSchedules(user1, entryID);
            totalMigrated += escrowAmount;
            migratedEntryIDs[i] = entryID;
        }

        // migrate
        migrateEntries(user1, migratedEntryIDs);

        // check final state
        assertEq(escrowMigrator.totalMigrated(), totalMigrated);
    }

    /*//////////////////////////////////////////////////////////////
                              STEP 1 TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Step_1_Normal() public {
        // check initial state
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        // step 1
        registerEntries(user1, _entryIDs);

        // check final state
        checkStateAfterStepOne(user1, _entryIDs, true);
    }

    function test_Step_1_Two_Rounds() public {
        // check initial state
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        // step 1 - register some entries
        registerEntries(user1, 0, 10);
        registerEntries(user1, 10, 7);

        // check final state
        checkStateAfterStepOne(user1, _entryIDs, true);
    }

    function test_Step_1_Three_Rounds() public {
        // check initial state
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        // step 1 - register some entries
        registerEntries(user1, 0, 5);
        registerEntries(user1, 5, 5);
        registerEntries(user1, 10, 7);

        // check final state
        checkStateAfterStepOne(user1, _entryIDs, true);
    }

    function test_Step_1_N_Rounds_Fuzz(uint8 _numRounds, uint8 _numPerRound) public {
        uint256 numRounds = _numRounds;
        uint256 numPerRound = _numPerRound;

        vm.assume(numRounds < 20);
        vm.assume(numPerRound < 20);

        // check initial state
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        uint256 numRegistered;
        for (uint256 i = 0; i < numRounds; i++) {
            // register some entries
            _entryIDs = registerEntries(user1, numRegistered, numPerRound);
            numRegistered += _entryIDs.length;
        }

        // check final state
        checkStateAfterStepOne(user1, 0, numRegistered, numRounds > 0);
    }

    /*//////////////////////////////////////////////////////////////
                           STEP 1 EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_Cannot_Register_Someone_Elses_Entry() public {
        // check initial state
        getStakingRewardsV1(user2);
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        // step 1
        vm.prank(user2);
        escrowMigrator.registerEntries(_entryIDs);

        // check final state
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 0);
        checkStateAfterStepOne(user1, _entryIDs, false);
        checkStateAfterStepOne(user2, _entryIDs, true);
    }

    function test_Cannot_Register_If_No_Escrow_Balance() public {
        // check initial state
        uint256 numVestingEntries = rewardEscrowV1.numVestingEntries(user4);
        uint256[] memory _entryIDs =
            rewardEscrowV1.getAccountVestingEntryIDs(user4, 0, numVestingEntries);
        uint256 v1BalanceBefore = rewardEscrowV1.balanceOf(user4);
        assertEq(numVestingEntries, 0);
        assertEq(v1BalanceBefore, 0);

        // step 1
        vm.prank(user4);
        vm.expectRevert(IEscrowMigrator.NoEscrowBalanceToMigrate.selector);
        escrowMigrator.registerEntries(_entryIDs);
    }

    function test_Cannot_Register_Without_Claiming_First() public {
        // check initial state
        (uint256[] memory _entryIDs,) = checkStateBeforeStepOne(user1);

        // step 1
        vm.prank(user1);
        vm.expectRevert(IEscrowMigrator.MustClaimStakingRewards.selector);
        escrowMigrator.registerEntries(_entryIDs);
    }

    function test_Cannot_Register_Vested_Entries() public {
        // check initial state
        claimAndCheckInitialState(user1);

        // vest 10 entries
        vest(user1, 0, 10);

        // step 1
        registerEntries(user1, 0, 17);

        // check final state
        checkStateAfterStepOne(user1, 10, 7, true);
    }

    function test_Cannot_Register_Mature_Entries() public {
        // check initial state
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        // fast forward until all entries are mature
        vm.warp(block.timestamp + 52 weeks);

        // step 1
        registerEntries(user1, _entryIDs);

        // check final state
        checkStateAfterStepOne(user1, 0, 0, true);
    }

    function test_Cannot_Duplicate_Register_Entries() public {
        // check initial state
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        // step 1
        registerEntries(user1, _entryIDs);
        registerEntries(user1, _entryIDs);

        // check final state
        checkStateAfterStepOne(user1, _entryIDs, true);
    }

    function test_Cannot_Register_Entries_That_Do_Not_Exist() public {
        // check initial state
        claimAndCheckInitialState(user1);

        // step 1
        entryIDs.push(rewardEscrowV1.nextEntryId());
        entryIDs.push(rewardEscrowV1.nextEntryId() + 1);
        entryIDs.push(rewardEscrowV1.nextEntryId() + 2);
        entryIDs.push(rewardEscrowV1.nextEntryId() + 3);
        registerEntries(user1, entryIDs);

        // check final state
        checkStateAfterStepOne(user1, 0, 0, true);
    }

    function test_Cannot_Register_Entry_After_Migration() public {
        // check initial state
        claimAndCheckInitialState(user1);

        // step 1
        registerEntries(user1, 0, 10);
        // vest
        vest(user1, 0, 10);
        // migrate
        approveAndMigrate(user1, 0, 10);

        assertEq(escrowMigrator.numberOfRegisteredEntries(user1), 10);

        // cannot register same entries and migrate them again
        registerEntries(user1, 0, 10);
        migrateEntries(user1, 0, 10);

        checkStateAfterStepTwo(user1, 0, 10);
    }

    /*//////////////////////////////////////////////////////////////
                              STEP 2 TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Step_2_Normal() public {
        // complete step 1
        (uint256[] memory _entryIDs,,) = claimRegisterVestAndApprove(user1);

        // step 2 - migrate entries
        migrateEntries(user1, _entryIDs);

        // check final state
        checkStateAfterStepTwo(user1, _entryIDs);
    }

    function test_Step_3_Two_Rounds() public {
        // complete step 1
        claimRegisterVestAndApprove(user1);

        // step 2 - migrate entries
        migrateEntries(user1, 0, 10);
        migrateEntries(user1, 10, 7);

        // check final state
        checkStateAfterStepTwo(user1, 0, 17);
    }

    function test_Step_2_N_Rounds_Fuzz(uint8 _numRounds, uint8 _numPerRound) public {
        uint256 numRounds = _numRounds;
        uint256 numPerRound = _numPerRound;

        vm.assume(numRounds < 20);
        vm.assume(numPerRound < 20);

        (uint256[] memory _entryIDs, uint256 numVestingEntries,) =
            claimRegisterVestAndApprove(user1);

        uint256 numMigrated;
        for (uint256 i = 0; i < numRounds; i++) {
            // step 2 - migrate some entries
            if (numMigrated == numVestingEntries) {
                break;
            }
            _entryIDs = migrateEntries(user1, numMigrated, numPerRound);
            numMigrated += _entryIDs.length;
        }

        // check final state
        checkStateAfterStepTwo(user1, 0, numMigrated);
    }

    /*//////////////////////////////////////////////////////////////
                           STEP 2 EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_Payment_Cost_Takes_Account_Of_Escrow_Vested_At_Start() public {
        // give user extra funds so they could in theory overpay
        vm.prank(treasury);
        kwenta.transfer(user3, 50 ether);

        uint256 vestedBalance = rewardEscrowV1.totalVestedAccountBalance(user3);
        assertGt(vestedBalance, 0);

        // fully migrate entries
        (uint256[] memory _entryIDs,,) = claimAndFullyMigrate(user3);

        // check final state
        /// @dev skip first entry as it was vested before migration, so couldn't be migrated
        _entryIDs =
            rewardEscrowV1.getAccountVestingEntryIDs(user3, 1, _entryIDs.length);
        checkStateAfterStepTwo(user3, _entryIDs);
    }

    function test_Step_2_Must_Pay() public {
        // complete step 1
        (uint256[] memory _entryIDs,) = claimRegisterAndVestAllEntries(user1);

        // step 3.2 - migrate entries
        vm.prank(user1);
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        escrowMigrator.migrateEntries(user1, _entryIDs);
    }

    function test_Step_2_Must_Pay_Fuzz(uint256 approveAmount) public {
        // complete step 1 and 2
        (uint256[] memory _entryIDs, uint256 toPay) = claimRegisterAndVestAllEntries(user1);

        vm.prank(user1);
        kwenta.approve(address(escrowMigrator), approveAmount);

        // step 2 - migrate entries
        vm.prank(user1);
        if (toPay > approveAmount) {
            vm.expectRevert("ERC20: transfer amount exceeds allowance");
        }
        escrowMigrator.migrateEntries(user1, _entryIDs);
    }

    function test_Cannot_Migrate_Non_Vested_Entries() public {
        // give escrow migrator funds so it could be cheated
        vm.prank(treasury);
        kwenta.transfer(address(escrowMigrator), 50 ether);

        // complete step 1
        claimAndRegisterAllEntries(user1);

        vest(user1, 0, 15);
        approve(user1);

        // step 2 - migrate entries
        migrateEntries(user1, 0, 17);

        // check final state
        checkStateAfterStepTwo(user1, 0, 15);
    }

    function test_Cannot_Migrate_Non_Registered_Entries() public {
        // complete step 1
        claimRegisterVestAndApprove(user1, 0, 10);

        // step 2 - migrate extra entries
        migrateEntries(user1, 0, 17);

        // check final state
        checkStateAfterStepTwo(user1, 0, 10);
    }

    function test_Cannot_Migrate_Non_Registered_Late_Vested_Entries() public {
        // complete step 1
        claimRegisterAndVestEntries(user1, 0, 10);

        // vest extra entries and approve
        vestAndApprove(user1, 0, 17);

        // step 2 - migrate extra entries
        migrateEntries(user1, 0, 17);

        // check final state
        checkStateAfterStepTwo(user1, 0, 10);
    }

    function test_Cannot_Duplicate_Migrate_Entries() public {
        // complete step 1
        claimRegisterVestAndApprove(user1);

        // pay extra to the escrow migrator, so it would have enough money to create the extra entries
        vm.prank(treasury);
        kwenta.transfer(address(escrowMigrator), 20 ether);

        // step 2 - migrate some entries
        migrateEntries(user1, 0, 15);
        // duplicate migrate
        migrateEntries(user1, 0, 15);

        // check final state
        checkStateAfterStepTwo(user1, 0, 15);
    }

    function test_Cannot_Migrate_Non_Existing_Entries() public {
        // complete step 1
        (entryIDs,,) = claimRegisterVestAndApprove(user1);

        // step 2 - migrate entries
        entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 0);
        entryIDs.push(rewardEscrowV1.nextEntryId());
        entryIDs.push(rewardEscrowV1.nextEntryId());
        entryIDs.push(rewardEscrowV1.nextEntryId());
        entryIDs.push(rewardEscrowV1.nextEntryId());
        migrateEntries(user1, entryIDs);

        // check final state
        checkStateAfterStepTwo(user1, 0, 0);
    }

    function test_Cannot_Migrate_Someone_Elses_Entries() public {
        // complete step 1
        (uint256[] memory user1EntryIDs,,) = claimRegisterVestAndApprove(user1);
        claimRegisterVestAndApprove(user2);

        // step 2 - user2 attempts to migrate user1's entries
        migrateEntries(user2, user1EntryIDs);

        // check final state - user2 didn't manage to migrate any entries
        checkStateAfterStepTwo(user2, 0, 0);
    }

    function test_Cannot_Migrate_On_Behalf_Of_Someone() public {
        // complete step 1
        (uint256[] memory user1EntryIDs,,) = claimRegisterVestAndApprove(user1);
        claimRegisterVestAndApprove(user2);

        // step 2 - user2 attempts to migrate user1's entries
        vm.prank(user2);
        escrowMigrator.migrateEntries(user1, user1EntryIDs);

        // check final state - user2 didn't manage to migrate any entries
        checkStateAfterStepTwo(user1, 0, 0);
    }

    function test_Cannot_Bypass_Unstaking_Cooldown_Lock() public {
        // this is the malicious entry - the duration is set to 1
        createRewardEscrowEntryV1(user1, 50 ether, 1);

        (uint256[] memory _entryIDs, uint256 numVestingEntries,) = claimAndFullyMigrate(user1);
        checkStateAfterStepTwo(user1, _entryIDs);

        // specifically
        uint256[] memory migratedEntryIDs =
            rewardEscrowV2.getAccountVestingEntryIDs(user1, numVestingEntries - 2, 1);
        uint256 maliciousEntryID = migratedEntryIDs[0];
        (uint64 endTime, uint256 escrowAmount, uint256 duration, uint8 earlyVestingFee) =
            rewardEscrowV2.getVestingEntry(maliciousEntryID);
        assertEq(endTime, block.timestamp + stakingRewardsV2.cooldownPeriod());
        assertEq(escrowAmount, 50 ether);
        assertEq(duration, stakingRewardsV2.cooldownPeriod());
        assertEq(earlyVestingFee, 90);
    }

    function test_Cannot_Migrate_In_Non_Initiated_State() public {
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        // attempt in non initiated state
        assertEq(escrowMigrator.initiated(user1), false);

        // step 2 - migrate entries
        vm.prank(user1);
        vm.expectRevert(IEscrowMigrator.MustBeInitiated.selector);
        escrowMigrator.migrateEntries(user1, _entryIDs);
    }

    /*//////////////////////////////////////////////////////////////
                          STEP 3 STATE LIMITS
    //////////////////////////////////////////////////////////////*/

    function test_Cannot_Migrate_Initiated_Without_Registering_Anything() public {
        // complete step 1
        claimAndRegisterEntries(user1, 0, 0);

        // step 2 - migrate entries
        migrateEntries(user1, 0, 17);
        vm.prank(user1);

        checkStateAfterStepTwo(user1, 0, 0);
    }

    function test_Can_Migrate_In_Completed_State() public {
        // move to completed state
        moveToCompletedState(user1);

        createRewardEscrowEntryV1(user1, 10 ether);
        createRewardEscrowEntryV1(user1, 10 ether);
        createRewardEscrowEntryV1(user1, 10 ether);

        fullyMigrate(user1, 17, 3);

        checkStateAfterStepTwo(user1, 0, 20);
    }

    // // TODO: test sending entries to another `to` address

    /*//////////////////////////////////////////////////////////////
                               FULL FLOW
    //////////////////////////////////////////////////////////////*/

    function test_Migrator() public {
        getStakingRewardsV1(user1);

        uint256 v2BalanceBefore = rewardEscrowV2.escrowedBalanceOf(user1);
        uint256 v1BalanceBefore = rewardEscrowV1.balanceOf(user1);
        assertEq(v1BalanceBefore, 17.246155111414632908 ether);
        assertEq(v2BalanceBefore, 0);

        uint256 numVestingEntries = rewardEscrowV1.numVestingEntries(user1);
        assertEq(numVestingEntries, 17);

        entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, numVestingEntries);
        assertEq(entryIDs.length, 17);

        (uint256 total, uint256 totalFee) = rewardEscrowV1.getVestingQuantity(user1, entryIDs);

        assertEq(total, 3.819707122432513665 ether);
        assertEq(totalFee, 13.426447988982119243 ether);

        // step 1
        vm.prank(user1);
        escrowMigrator.registerEntries(entryIDs);

        uint256 step2UserBalance = kwenta.balanceOf(user1);
        uint256 step2MigratorBalance = kwenta.balanceOf(address(escrowMigrator));

        // step 2.1 - vest
        vm.prank(user1);
        rewardEscrowV1.vest(entryIDs);

        uint256 step2UserBalanceAfterVest = kwenta.balanceOf(user1);
        uint256 step2MigratorBalanceAfterVest = kwenta.balanceOf(address(escrowMigrator));
        assertEq(step2UserBalanceAfterVest, step2UserBalance + total);
        assertEq(step2MigratorBalanceAfterVest, step2MigratorBalance + totalFee);

        // step 2.2 - pay for migration
        vm.prank(user1);
        kwenta.approve(address(escrowMigrator), total);

        // step 2.3 - migrate entries
        vm.prank(user1);
        escrowMigrator.migrateEntries(user1, entryIDs);

        // check escrow sent to v2
        uint256 v2BalanceAfter = rewardEscrowV2.escrowedBalanceOf(user1);
        uint256 v1BalanceAfter = rewardEscrowV1.balanceOf(user1);
        assertEq(v2BalanceAfter, v2BalanceBefore + total + totalFee);
        assertEq(v1BalanceAfter, v1BalanceBefore - total - totalFee);

        // confirm entries have right composition
        entryIDs = rewardEscrowV2.getAccountVestingEntryIDs(user1, 0, numVestingEntries);
        (uint256 newTotal, uint256 newTotalFee) = rewardEscrowV2.getVestingQuantity(entryIDs);

        // check within 1% of target
        assertCloseTo(newTotal, total, total / 100);
        assertCloseTo(newTotalFee, totalFee, totalFee / 100);
    }

    /*//////////////////////////////////////////////////////////////
                        STRANGE EFFECTIVE FLOWS
    //////////////////////////////////////////////////////////////*/

    /// @dev There are numerous different ways the user could interact with the system,
    /// as opposed for the way we intend for the user to interact with the system.
    /// These tests check that users going "alterantive routes" don't break the system.
    /// In order to breifly annoate special flows, I have created an annotation system:
    /// R = register, V = vest, M = migrate, C = create new escrow entry
    /// So for example, RVC means register, vest, confirm, in that order

    function test_RVRVM() public {
        // R
        claimAndRegisterEntries(user1, 0, 5);
        // V
        vest(user1, 0, 5);
        // R
        registerEntries(user1, 5, 5);
        // V
        vest(user1, 5, 5);
        // M
        approveAndMigrate(user1, 0, 10);

        checkStateAfterStepTwo(user1, 0, 10);
    }

    function test_RVMRVM() public {
        // R
        claimAndRegisterEntries(user1, 0, 6);
        // V
        vest(user1, 0, 5);
        // M
        approveAndMigrate(user1, 0, 5);
        // R
        registerEntries(user1, 6, 4);
        // V
        vest(user1, 5, 5);
        // M
        approveAndMigrate(user1, 5, 5);

        checkStateAfterStepTwo(user1, 0, 10);
    }

    /*//////////////////////////////////////////////////////////////
                       STRANGE FLOWS UP TO STEP 1
    //////////////////////////////////////////////////////////////*/

    function test_CR() public {
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // R
        claimAndRegisterEntries(user1, 0, 6);

        checkStateAfterStepOne(user1, 0, 6, true);
    }

    function test_VR() public {
        // V
        vest(user1, 0, 3);
        // R
        claimAndRegisterEntries(user1, 0, 6);

        checkStateAfterStepOne(user1, 3, 3, true);
    }

    function test_CVR() public {
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // V
        vest(user1, 0, 3);
        // R
        claimAndRegisterEntries(user1, 0, 6);

        checkStateAfterStepOne(user1, 3, 3, true);
    }

    function test_VCR() public {
        // V
        vest(user1, 0, 3);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // R
        claimAndRegisterEntries(user1, 0, 6);

        checkStateAfterStepOne(user1, 3, 3, true);
    }

    /*//////////////////////////////////////////////////////////////
                       STRANGE FLOWS UP TO STEP 2
    //////////////////////////////////////////////////////////////*/

    function test_RCM() public {
        // R
        claimAndRegisterEntries(user1, 0, 6);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // M
        approveAndMigrate(user1, 0, 6);

        checkStateAfterStepTwo(user1, 0, 0);
    }

    function test_RCVM() public {
        // R
        claimAndRegisterEntries(user1, 0, 6);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // V
        vest(user1, 0, 3);
        // M
        approveAndMigrate(user1, 0, 6);

        checkStateAfterStepTwo(user1, 0, 3);
    }

    function test_RVCM() public {
        // R
        claimAndRegisterEntries(user1, 0, 6);
        // V
        vest(user1, 0, 3);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // M
        approveAndMigrate(user1, 0, 6);

        checkStateAfterStepTwo(user1, 0, 3);
    }

    function test_RCVRVM() public {
        // R
        claimAndRegisterEntries(user1, 0, 6);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // V
        vest(user1, 0, 3);
        // R
        registerEntries(user1, 6, 4);
        // V
        vest(user1, 3, 3);
        // M
        approveAndMigrate(user1, 0, 10);

        checkStateAfterStepTwo(user1, 0, 6);
    }

    function test_RVCRVM() public {
        // R
        claimAndRegisterEntries(user1, 0, 6);
        // V
        vest(user1, 0, 3);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // R
        registerEntries(user1, 6, 4);
        // V
        vest(user1, 3, 3);
        // M
        approveAndMigrate(user1, 0, 10);

        checkStateAfterStepTwo(user1, 0, 6);
    }

    function test_RVRCVM() public {
        // R
        claimAndRegisterEntries(user1, 0, 6);
        // V
        vest(user1, 0, 3);
        // R
        registerEntries(user1, 6, 4);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // V
        vest(user1, 3, 3);
        // M
        approveAndMigrate(user1, 0, 10);

        checkStateAfterStepTwo(user1, 0, 6);
    }

    function test_RVRVCM() public {
        // R
        claimAndRegisterEntries(user1, 0, 6);
        // V
        vest(user1, 0, 3);
        // R
        registerEntries(user1, 6, 4);
        // V
        vest(user1, 3, 7);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // M
        approveAndMigrate(user1, 0, 10);

        checkStateAfterStepTwo(user1, 0, 10);
    }

    function test_RCVMRVM() public {
        // R
        claimAndRegisterEntries(user1, 0, 6);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // V
        vest(user1, 0, 3);
        // M
        approveAndMigrate(user1, 0, 6);
        // R
        registerEntries(user1, 6, 4);
        // V
        vest(user1, 3, 7);
        // M
        approveAndMigrate(user1, 0, 10);

        checkStateAfterStepTwo(user1, 0, 10);
    }

    function test_RVCMRVM() public {
        // R
        claimAndRegisterEntries(user1, 0, 6);
        // V
        vest(user1, 0, 3);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // M
        approveAndMigrate(user1, 0, 6);
        // R
        registerEntries(user1, 6, 4);
        // V
        vest(user1, 3, 7);
        // M
        approveAndMigrate(user1, 0, 10);

        checkStateAfterStepTwo(user1, 0, 10);
    }

    function test_RVMCRVM() public {
        // R
        claimAndRegisterEntries(user1, 0, 10);
        // V
        vest(user1, 0, 3);
        // M
        approveAndMigrate(user1, 0, 6);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // R
        registerEntries(user1, 10, 4);
        // V
        vest(user1, 3, 7);
        // M
        approveAndMigrate(user1, 0, 10);

        checkStateAfterStepTwo(user1, 0, 10);
    }

    function test_RVMRCVM() public {
        // R
        claimAndRegisterEntries(user1, 0, 10);
        // V
        vest(user1, 0, 3);
        // M
        approveAndMigrate(user1, 0, 6);
        // R
        registerEntries(user1, 10, 7);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // V
        vest(user1, 3, 14);
        // M
        approveAndMigrate(user1, 3, 17);

        checkStateAfterStepTwo(user1, 0, 17);
    }

    function test_RVMRVCM() public {
        // R
        claimAndRegisterEntries(user1, 0, 10);
        // V
        vest(user1, 0, 3);
        // M
        approveAndMigrate(user1, 0, 6);
        // R
        registerEntries(user1, 10, 7);
        // V
        vest(user1, 3, 14);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // M
        approveAndMigrate(user1, 3, 17);

        checkStateAfterStepTwo(user1, 0, 17);
    }

    /*//////////////////////////////////////////////////////////////
                      STRANGE FLOWS BEYOND STEP 2
    //////////////////////////////////////////////////////////////*/

    function test_MVM() public {
        claimRegisterAndVestEntries(user1, 0, 10);

        // M
        approveAndMigrate(user1, 0, 10);
        // V
        vest(user1, 0, 17);
        // M
        approveAndMigrate(user1, 0, 10);

        checkStateAfterStepTwo(user1, 0, 10);
    }

    function test_MCM() public {
        claimRegisterAndVestEntries(user1, 0, 17);

        // M
        approveAndMigrate(user1, 0, 17);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // M
        approveAndMigrate(user1, 0, 18);

        checkStateAfterStepTwo(user1, 0, 17);
    }

    function test_MCVM() public {
        claimRegisterAndVestEntries(user1, 0, 17);

        // M
        approveAndMigrate(user1, 0, 17);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // V
        vest(user1, 0, 18);
        // M
        approveAndMigrate(user1, 0, 18);

        checkStateAfterStepTwo(user1, 0, 17);
    }

    function test_MVCM() public {
        claimRegisterAndVestEntries(user1, 0, 15);

        // M
        approveAndMigrate(user1, 0, 15);
        // V
        vest(user1, 0, 15);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // M
        approveAndMigrate(user1, 0, 18);

        checkStateAfterStepTwo(user1, 0, 15);
    }

    function test_MRVM() public {
        claimRegisterAndVestEntries(user1, 0, 15);

        // M
        approveAndMigrate(user1, 0, 15);
        // R
        registerEntries(user1, 15, 2);
        // V
        vest(user1, 0, 17);
        // M
        approveAndMigrate(user1, 0, 17);

        checkStateAfterStepTwo(user1, 0, 17);
    }

    function test_MRCM() public {
        claimRegisterAndVestEntries(user1, 0, 15);

        // M
        approveAndMigrate(user1, 0, 15);
        // R
        registerEntries(user1, 15, 2);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // M
        approveAndMigrate(user1, 0, 18);

        checkStateAfterStepTwo(user1, 0, 15);
    }

    function test_MCRM() public {
        claimRegisterAndVestEntries(user1, 0, 15);

        // M
        approveAndMigrate(user1, 0, 15);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // R
        registerEntries(user1, 15, 2);
        // M
        approveAndMigrate(user1, 0, 18);

        checkStateAfterStepTwo(user1, 0, 15);
    }

    function test_MRCVM() public {
        claimRegisterAndVestEntries(user1, 0, 15);

        // M
        approveAndMigrate(user1, 0, 15);
        // R
        registerEntries(user1, 15, 2);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // V
        vest(user1, 0, 18);
        // M
        approveAndMigrate(user1, 0, 18);

        checkStateAfterStepTwo(user1, 0, 17);
    }

    function test_MRVCM() public {
        claimRegisterAndVestEntries(user1, 0, 15);

        // M
        approveAndMigrate(user1, 0, 15);
        // R
        registerEntries(user1, 15, 2);
        // V
        vest(user1, 0, 17);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // M
        approveAndMigrate(user1, 0, 18);

        checkStateAfterStepTwo(user1, 0, 17);
    }

    function test_MVRCM() public {
        claimRegisterAndVestEntries(user1, 0, 15);

        // M
        approveAndMigrate(user1, 0, 15);
        // V
        vest(user1, 0, 17);
        // R
        registerEntries(user1, 15, 2);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // M
        approveAndMigrate(user1, 0, 18);

        checkStateAfterStepTwo(user1, 0, 15);
    }

    function test_MVCRM() public {
        claimRegisterAndVestEntries(user1, 0, 15);

        // M
        approveAndMigrate(user1, 0, 15);
        // V
        vest(user1, 0, 17);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // R
        registerEntries(user1, 15, 3);
        // M
        approveAndMigrate(user1, 0, 18);

        checkStateAfterStepTwo(user1, 0, 15);
    }

    function test_MCVRM() public {
        claimRegisterAndVestEntries(user1, 0, 15);

        // M
        approveAndMigrate(user1, 0, 15);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // V
        vest(user1, 0, 17);
        // R
        registerEntries(user1, 15, 3);
        // M
        approveAndMigrate(user1, 0, 18);

        checkStateAfterStepTwo(user1, 0, 15);
    }

    function test_MCRVM() public {
        claimRegisterAndVestEntries(user1, 0, 15);

        // M
        approveAndMigrate(user1, 0, 15);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // R
        registerEntries(user1, 15, 3);
        // V
        vest(user1, 0, 17);
        // M
        approveAndMigrate(user1, 0, 18);

        checkStateAfterStepTwo(user1, 0, 17);
    }
}

// TODO: 3. Update checkState helpers to account for expected changes in rewardEscrowV1.balanceOf
// TODO: 4. Update checkState helpers to account for expected changes in totalRegisteredEscrow and similar added new variables
// TODO: test confirming and then registering again
// TODO: test vest, confirm, vest, confirm
// TODO: test register, vest, register, vest etc.
// TODO: test confirm, register, vest, confirm
// TODO: test not migrating all entries from end-to-end
// TODO: add tests to ensure each function can only be executed in the correct state for step 1 & 3
// TODO: test sending in entryIDs in a funny order

// QUESTION: 2. Option to simplify to O(1) time, using just balanceOf & totalVestedAccountBalance
