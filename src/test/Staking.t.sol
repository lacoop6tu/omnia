// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {Staking} from "../Staking.sol";
import {ERC20} from "openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Omnia is ERC20("Omnia", "OMN") {
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract StakingTest is Test {
    Staking public staking;
    Omnia public omnia;

    address me = address(this);
    address staker1 = address(1);
    address staker2 = address(2);
    address staker3 = address(3);

    uint256 initialAmount = 1000 ether;
    uint256 epoch = 28 days;

    address[] users;
    uint256[] yields;

    function setUp() public {
        omnia = new Omnia();
        staking = new Staking(address(omnia));
        omnia.mint(me, initialAmount);
        omnia.mint(staker1, initialAmount);
        omnia.mint(staker2, initialAmount);
        omnia.mint(staker3, initialAmount);
        omnia.approve(address(staking), initialAmount);
        vm.prank(staker1);
        omnia.approve(address(staking), initialAmount);
        vm.prank(staker2);
        omnia.approve(address(staking), initialAmount);
        vm.prank(staker3);
        omnia.approve(address(staking), initialAmount);
    }

    function test_check_initialization() public {
        assertEq(staking.maxLock(), 365 days);
        assertEq(staking.minLock(), 21 days);
        assertEq(staking.epoch(), 28 days);
        assertEq(address(staking.token()), address(omnia));
        assertEq(staking.availableRewards(), 0);
        assertEq(omnia.balanceOf(me), initialAmount);
        assertEq(omnia.balanceOf(staker1), initialAmount);
    }

    function test_1_user_flow() public {
        // Adding rewards (admin)
        staking.addRewards(100 ether);

        // User stake
        uint256 stakeAmount = 100 ether;

        vm.prank(staker1);
        staking.stake(stakeAmount, 180 days);

        (uint256 amount, , , , ) = staking.deposits(staker1);
        assertEq(amount, stakeAmount);
        

        users.push(staker1);
        uint256 yield = 10 ether;
   
        yields.push(yield);
        // Update yield (admin)
        staking.updateYields(users, yields);

        vm.warp(block.timestamp + epoch);

        // Staker claims yield
        vm.prank(staker1);
        staking.claim_yield();
        (amount, , , , ) = staking.deposits(staker1);
        assertEq(amount, stakeAmount);
        assertEq(omnia.balanceOf(staker1), initialAmount - stakeAmount + yield);

        // we update twice before user collects yield
        staking.updateYields(users, yields);

        vm.warp(block.timestamp + 30 days);

        staking.updateYields(users, yields);

        vm.warp(block.timestamp + 30 days);

        vm.prank(staker1);
        staking.claim_yield();
        assertEq(
            omnia.balanceOf(staker1),
            initialAmount - stakeAmount + 3 * yield
        );

        // user add more stake
        vm.prank(staker1);
        staking.addToStake(stakeAmount);

        // we add more yield
        staking.updateYields(users, yields);

        // move after lock
        vm.warp(block.timestamp + 120 days);

        // user can now withdraw and leave some unleft yield to claim;
        vm.prank(staker1);
        staking.withdraw();
        assertEq(omnia.balanceOf(staker1), initialAmount + 3 * yield);

        // user can still claim available yield after withdrawing
        vm.warp(block.timestamp + 30 days);

        vm.prank(staker1);
        staking.claim_yield();
        assertEq(omnia.balanceOf(staker1), initialAmount + 4 * yield);
    }

    function test_3_users_flow() public {
        // Adding rewards (admin)
        staking.addRewards(100 ether);

        // Users stake
        uint256 stakeAmount1 = 100 ether;
        uint256 stakeAmount2 = 50 ether;
        uint256 stakeAmount3 = 30 ether;

        vm.prank(staker1);
        staking.stake(stakeAmount1, 90 days);
        vm.prank(staker2);
        staking.stake(stakeAmount2, 120 days);
        vm.prank(staker3);
        staking.stake(stakeAmount3, 60 days);

        (uint256 amount, , , , ) = staking.deposits(staker1);
        assertEq(amount, stakeAmount1);
        (amount, , , , ) = staking.deposits(staker2);
        assertEq(amount, stakeAmount2);
        (amount, , , , ) = staking.deposits(staker3);
        assertEq(amount, stakeAmount3);

        // Admin updates corresponding yields
        users.push(staker1);
        users.push(staker2);
        users.push(staker3);

        uint256 yield1 = 10 ether;
        uint256 yield2 = 7 ether;
        uint256 yield3 = 5 ether;

        yields.push(yield1);
        yields.push(yield2);
        yields.push(yield3);
        staking.updateYields(users, yields);
        
        vm.warp(block.timestamp + epoch);

        // User1 claims all yield available
        vm.prank(staker1);
        staking.claim_yield();
        (, , uint256 availableYield,uint256 lockedYield , ) = staking.deposits(staker1);
        assertEq(availableYield,0);
        assertEq(lockedYield,0);

        // User1 has now the initialAmount - amount stake + all yield
        assertEq(omnia.balanceOf(staker1),initialAmount - stakeAmount1 + yield1);

        staking.updateYields(users, yields);
        vm.warp(block.timestamp + 32 days);

        staking.updateYields(users, yields);
        
        // user3 exits and withdraws stake and available yield
        vm.prank(staker3);
        staking.withdraw_and_claim();
        uint256 lastTimeUpdate;
        uint256 lockedUntil;
        (amount, lockedUntil,availableYield,lockedYield, lastTimeUpdate) = staking.deposits(staker3);
        assertEq(amount,0);
        assertEq(lockedUntil,0);
        assertEq(availableYield,0); 
        assertGt(lockedYield,0); // There's some locked yield waited to be unlocked
        assertGt(lastTimeUpdate,0);

        // User3 has now the initialAmount + the available yield 
        assertEq(omnia.balanceOf(staker3),initialAmount + 2 * yield3);

        // User3 re-stake for some time
        vm.prank(staker3);
        staking.stake(stakeAmount3,30 days);

        staking.updateYields(users, yields);

        vm.warp(block.timestamp + 30 days);

        // User3 exits and withdraws stake and available yield (ALL yield is available in this case)
        vm.prank(staker3);
        staking.withdraw_and_claim();
        (amount, lockedUntil,availableYield,lockedYield, lastTimeUpdate) = staking.deposits(staker3);
        assertEq(amount,0);
        assertEq(lockedUntil,0);
        assertEq(availableYield,0); 
        assertEq(lockedYield,0); // There's no locked yield
        assertGt(lastTimeUpdate,0); 

        // User3 has now the initialAmount + all yield
        assertEq(omnia.balanceOf(staker3),initialAmount + 4 * yield3);

        // User1 withdraws only the stake
        vm.prank(staker1);
        staking.withdraw();

        (amount,lockedUntil,availableYield,lockedYield,) = staking.deposits(staker1);
        assertEq(amount,0);
        assertEq(lockedUntil,0);
        assertGt(availableYield,0); // There's available yield
        assertGt(lockedYield,0); // There's locked yield which by now is free to be withdrawn

        // User1 got back is stake and has only the intiial yield claimed before
        assertEq(omnia.balanceOf(staker1),initialAmount + yield1);

        vm.prank(staker1);
        staking.claim_yield();
        (,,availableYield,lockedYield,) = staking.deposits(staker1);
        assertEq(availableYield,0); 
        assertEq(lockedYield,0); 

        // User1 collected all available yield
        assertEq(omnia.balanceOf(staker1),initialAmount + 4 *yield1);

        vm.warp(block.timestamp + 90 days);

        vm.prank(staker2);
        staking.withdraw_and_claim();

        // User2 collected all together
        assertEq(omnia.balanceOf(staker2),initialAmount + 4 *yield2);
    }

    function test_errors() public {
        vm.startPrank(staker1);

        // Amount Zero
        vm.expectRevert(Staking.Error__Amount_zero.selector);
        staking.stake(0, 365 days);

        // No rewards available
        vm.expectRevert(Staking.Error__Nothing_to_claim.selector);
        staking.claim_yield();

        // Stake more than 365 days
        vm.expectRevert(Staking.Error__Lock_too_long.selector);
        staking.stake(10, 366 days);

        // Stake less than 21 days
        vm.expectRevert(Staking.Error__Lock_too_short.selector);
        staking.stake(10 ether, 20 days);

        // Attemp add more stake without having a live stake
        vm.expectRevert(Staking.Error__Not_staked.selector);
        staking.addToStake(10 ether);

        // Attemp withdraw without staking
        vm.expectRevert(Staking.Error__Nothing_to_withdraw.selector);
        staking.withdraw();

        // USER STAKES
        staking.stake(100 ether, 180 days);

        // Attemp to re-stake with active deposit
        vm.expectRevert(Staking.Error__Already_staked.selector);
        staking.stake(30 ether, 60 days);

        vm.stopPrank();

        // 50 OMNIA rewards for staker1
        users.push(staker1);
        yields.push(50 ether);

        // Admin set yields
        staking.updateYields(users, yields);

        vm.startPrank(staker1);
        // User has nothing to claim yet (28 days have not passed)
        vm.expectRevert(Staking.Error__Nothing_to_claim.selector);
        staking.claim_yield();

        // Cannot withdraw yet
        vm.expectRevert(Staking.Error__Cannot_withdraw_yet.selector);
        staking.withdraw();

        // Cannot use withdraw and claim yet
        vm.expectRevert(Staking.Error__Cannot_withdraw_yet.selector);
        staking.withdraw_and_claim();

        // We advanced when they are unlocked
        vm.warp(block.timestamp + 28 days);

        // User cannot get reward because there's no reward available
        vm.expectRevert(Staking.Error__No_rewards_available.selector);
        staking.claim_yield();

        vm.stopPrank();

        // we add some rewards as admin
        staking.addRewards(40 ether);

        // User cannot get reward because there's not enough reward available
        vm.expectRevert(Staking.Error__Not_enough_rewards_available.selector);
        vm.prank(staker1);
        staking.claim_yield();

        // we add enough rewards as admin
        staking.addRewards(40 ether);

        vm.startPrank(staker1);
        staking.claim_yield();

        assertEq(staking.availableRewards(), 30 ether);
        assertEq(omnia.balanceOf(staker1), 950 ether);

        // after enough time user can withdraw
        vm.warp(block.timestamp + 180 days);
        staking.withdraw();

        assertEq(omnia.balanceOf(staker1), initialAmount + 50 ether);
    }
}
