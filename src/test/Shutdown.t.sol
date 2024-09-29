// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/src/console2.sol";

import { Setup, ERC20, IStrategyInterface } from "./utils/Setup.sol";
import { Slippage } from "swap-helpers/src/utils/Slippage.sol";

import { CoinflakesBtcStrategy, IERC20 } from "../CoinflakesBtcStrategy.sol";

contract ShutdownTest is Setup {
    using Slippage for uint256;

    function setUp() public virtual override {
        super.setUp();
    }

    function test_shutdownCanWithdraw(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);
        simulateEthUp();

        // Shutdown the strategy
        vm.prank(management);
        strategy.shutdownStrategy();

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Make sure we can still withdraw the full amount
        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        int24 slippage = (balanceBefore + _amount).slippage(asset.balanceOf(user));
        assertLe(slippage, 100, "!final balance");
    }

    function test_emergencyWithdraw(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // If eth is up, there should be more WETH
        // than before.
        skip(1 days);
        simulateEthUp();

        // Shutdown
        vm.prank(management);
        strategy.shutdownStrategy();

        IERC20 cbbtc = CoinflakesBtcStrategy(address(strategy)).CBBTC();
        uint256 cbbtcBalance = cbbtc.balanceOf(address(strategy));
        require(cbbtcBalance > 0, "!weth balance");
        uint256 assetBalance = IERC20(strategy.asset()).balanceOf(address(strategy));
        require(assetBalance == 0, "!unspent assets");
        vm.prank(management);
        strategy.emergencyWithdraw(_amount);
        assetBalance = IERC20(strategy.asset()).balanceOf(address(strategy));
        require(assetBalance > 0, "!no free assets");
    }
}
