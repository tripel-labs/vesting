// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {Vesting, VestingFactory, ERC20} from "../src/VestingFactory.sol";

contract Token is ERC20("", "", 18) {
    constructor() {
        _mint(msg.sender, type(uint256).max);
    }
}

contract VestingTest is Test {
    address public alice = address(0x1337);
    address public bob = address(0xdead);
    ERC20 public vestingToken;
    VestingFactory public factory;

    function setUp() public {
        vestingToken = new Token();
        factory = new VestingFactory();
        vestingToken.approve(address(factory), type(uint256).max);
    }

    function testCreate(uint256 _startTime, uint256 _endTime, address _recipient, uint256 _amount) public {
        if (_startTime >= _endTime) {
            vm.expectRevert();
            factory.createVestingSchedule(address(vestingToken), _amount, _recipient, _startTime, _endTime);
            return;
        }
        Vesting vesting =
            factory.createVestingSchedule(address(vestingToken), _amount, _recipient, _startTime, _endTime);
        (address token, uint256 totalAmount, address recipient, uint256 startTime, uint256 endTime) =
            vesting.getVestingSchedule();
        assertEq(token, address(vestingToken), "!token");
        assertEq(startTime, _startTime, "!startTime");
        assertEq(endTime, _endTime, "!endTime");
        assertEq(recipient, _recipient, "!recipient");
        assertEq(totalAmount, _amount, "!amount");
        assertEq(vestingToken.balanceOf(address(vesting)), _amount, "!claimed");
    }

    function testCreateMultiple(uint64 _time) public {
        uint256 time = _time;
        address[] memory tokens = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        address[] memory recipients = new address[](2);
        uint256[] memory startTimes = new uint256[](2);
        uint256[] memory endTimes = new uint256[](2);
        Token tokenA = new Token();
        Token tokenB = new Token();
        tokenA.approve(address(factory), type(uint256).max);
        tokenB.approve(address(factory), type(uint256).max);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);
        amounts[0] = 1;
        amounts[1] = 2;
        recipients[0] = alice;
        recipients[1] = bob;
        startTimes[0] = time;
        startTimes[1] = time + 1;
        endTimes[0] = time + 2;
        endTimes[1] = time + 3;
        Vesting[] memory vestings = factory.createVestingSchedules(tokens, amounts, recipients, startTimes, endTimes);
        (address token, uint256 totalAmount, address recipient, uint256 startTime, uint256 endTime) =
            vestings[0].getVestingSchedule();
        assertEq(token, address(tokenA), "!token");
        assertEq(startTime, time, "!startTime");
        assertEq(endTime, time + 2, "!endTime");
        assertEq(recipient, alice, "!recipient");
        assertEq(totalAmount, 1, "!amount");
        assertEq(tokenA.balanceOf(address(vestings[0])), 1, "!balance");
        (token, totalAmount, recipient, startTime, endTime) = vestings[1].getVestingSchedule();
        assertEq(token, address(tokenB), "!token");
        assertEq(startTime, time + 1, "!startTime");
        assertEq(endTime, time + 3, "!endTime");
        assertEq(recipient, bob, "!recipient");
        assertEq(totalAmount, 2, "!amount");
        assertEq(tokenB.balanceOf(address(vestings[1])), 2, "!balance");
    }

    function testVestingStatus(uint64 _currentTime, uint64 _startTime, uint64 _endTime) public {
        (uint256 currentTime, uint256 startTime, uint256 endTime) = (_currentTime, _startTime, _endTime);
        vm.assume(startTime < endTime);
        vm.warp(currentTime);
        uint256 amount = 1e18;
        Vesting vesting = factory.createVestingSchedule(address(vestingToken), amount, alice, startTime, endTime);
        (uint256 claimed, uint256 claimable, uint256 pending) = vesting.getVestingStatus();
        assertEq(claimed, 0, "!claimed");
        if (currentTime < startTime) {
            assertEq(claimable, 0, "!claimable");
            assertEq(pending, amount, "!pending");
        } else if (currentTime < endTime) {
            assertEq(claimable, amount * (currentTime - startTime) / (endTime - startTime), "!claimable");
            assertEq(pending, 1e18 - amount * (currentTime - startTime) / (endTime - startTime), "!pending");
        } else {
            assertEq(claimable, amount, "!claimable");
            assertEq(pending, 0, "!pending");
        }
    }

    function testSingleClaim(uint64 _currentTime, uint64 _startTime, uint64 _endTime) public {
        (uint256 currentTime, uint256 startTime, uint256 endTime) = (_currentTime, _startTime, _endTime);
        vm.assume(startTime < endTime);
        vm.warp(currentTime);
        Vesting vesting = factory.createVestingSchedule(address(vestingToken), 1e18, bob, startTime, endTime);
        vm.startPrank(bob);
        (, uint256 claimable, uint256 pending) = vesting.getVestingStatus();
        uint256 claimed = vesting.claim();
        assertEq(claimed, claimable, "!claimable");
        assertEq(vestingToken.balanceOf(bob), claimable, "!claimable");
        (uint256 _claimed, uint256 _claimable, uint256 _pending) = vesting.getVestingStatus();
        assertEq(_claimed, claimed, "!claimed");
        assertEq(_claimable, 0, "!claimable");
        assertEq(pending, _pending, "!pending changed");
        _ensureAmountsMatch(vesting);
        claimed = vesting.claim();
        assertEq(claimed, 0, "!claimed");
        vm.stopPrank();
    }

    function testClaims() public {
        uint256 startTime = 2000;
        uint256 endTime = 3000;
        uint256 amount = 1e18;
        Vesting vesting = factory.createVestingSchedule(address(vestingToken), amount, bob, startTime, endTime);
        vm.startPrank(bob);
        // vest 25%
        vm.warp(startTime + (endTime - startTime) / 4);
        uint256 claimed = vesting.claim();
        assertTrue(claimed == amount / 4, "!claimed25");
        _ensureAmountsMatch(vesting);

        // vest 75%
        vm.warp(startTime + (endTime - startTime) * 3 / 4);
        claimed = vesting.claim();
        assertTrue(claimed == amount / 2, "!claimed75");
        _ensureAmountsMatch(vesting);

        // vest 100%
        vm.warp(endTime);
        claimed = vesting.claim();
        assertTrue(claimed == amount / 4, "!claimed100");
        _ensureAmountsMatch(vesting);
        vm.stopPrank();
    }

    function testOnlyRecipient() public {
        Vesting vesting = factory.createVestingSchedule(address(vestingToken), 1e18, alice, 10, 20);
        vm.expectRevert();
        vesting.changeRecipient(alice);
        vm.startPrank(alice);
        vesting.changeRecipient(bob);
        (,, address recipient,,) = vesting.getVestingSchedule();
        assertEq(recipient, bob, "!recipient");
        vm.expectRevert();
        vesting.claim();
        vm.stopPrank();
        vm.startPrank(bob);
        vesting.claim();
        vm.stopPrank();
    }

    function _ensureAmountsMatch(Vesting vesting) internal {
        (uint256 claimed, uint256 claimable, uint256 pending) = vesting.getVestingStatus();
        (, uint256 totalAmount,,,) = vesting.getVestingSchedule();
        assertEq(claimed + claimable + pending, totalAmount, "!amountsMatch");
    }
}
