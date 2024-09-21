// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { Setup } from "./utils/Setup.sol";
import { CoinflakesEthStrategy } from "../CoinflakesEthStrategy.sol";

contract PriceFeedTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_priceFeedIsBehind() public {
        priceFeed.update();
        skip(CoinflakesEthStrategy(address(strategy)).maxOracleDelay() + 1 minutes);
        airdrop(asset, user, 10_000 ether);

        vm.prank(user);
        asset.approve(address(strategy), 10_000 ether);

        vm.expectRevert(bytes("oracle out of date"));
        vm.prank(user);
        strategy.deposit(10_000 ether, user);
    }

    function test_priceFeedDifferenceOnDeposits() public {
        priceFeed.update();
        int256 price = priceFeed.latestAnswer();
        uint256 daiAmount = uint256(price) * 10 ** 10;

        airdrop(asset, user, daiAmount);

        vm.prank(user);
        asset.approve(address(strategy), daiAmount);

        vm.startPrank(management);
        CoinflakesEthStrategy(address(strategy)).setMaxSlippage(4999);
        priceFeed.setLatestAnswer(price / 2);
        vm.stopPrank();

        vm.expectRevert(bytes("slippage"));
        vm.prank(user);
        strategy.deposit(daiAmount, user);
    }

    function test_priceFeedDifferenceOnReports() public {
        priceFeed.update();
        uint256 daiAmount = 10_000 ether;
        mintAndDepositIntoStrategy(strategy, user, daiAmount);

        vm.startPrank(management);
        CoinflakesEthStrategy(address(strategy)).setMaxSlippage(4999);
        priceFeed.setLatestAnswer(priceFeed.latestAnswer() * 2);
        vm.stopPrank();

        vm.expectRevert(bytes("oracle deviation"));
        vm.prank(management);
        strategy.report();
    }

    function test_priceFeedDifferenceOnWithdraws() public {
        priceFeed.update();
        uint256 daiAmount = 10_000 ether;
        mintAndDepositIntoStrategy(strategy, user, daiAmount);

        vm.startPrank(management);
        CoinflakesEthStrategy(address(strategy)).setMaxSlippage(4999);
        priceFeed.setLatestAnswer(priceFeed.latestAnswer() * 2);
        vm.stopPrank();

        vm.startPrank(user);
        strategy.approve(address(strategy), type(uint256).max);
        vm.expectRevert(bytes("slippage"));
        strategy.withdraw(daiAmount, user, user, 5000);
        vm.stopPrank();
    }
}
