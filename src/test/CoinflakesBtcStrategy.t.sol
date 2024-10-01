// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

import { Test } from "forge-std/src/Test.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ITokenizedStrategy } from "@tokenized-strategy/interfaces/ITokenizedStrategy.sol";
import { Slippage } from "swap-helpers/src/utils/Slippage.sol";
import { MockPriceFeed } from "./utils/MockPriceFeed.sol";
import { CoinflakesBtcStrategy, IAggregator, ISwapHelper } from "../CoinflakesBtcStrategy.sol";

contract CoinflakesBtcStrategyTest is Test {
    using Slippage for uint256;
    using Math for uint256;

    address public constant SWAP = 0x4Ea53f0F9fDD145AC640597AE85a56510599Dc18; // DAI/CBBTC
    address public constant CHAINLINK_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c; // BTC/USD

    MockPriceFeed public priceFeed;
    ISwapHelper public swap;

    address strategy;
    address user;
    address unallowedUser;

    IERC20Metadata vaultAsset = IERC20Metadata(0x6B175474E89094C44Da98b954EedeAC495271d0F); // DAI
    IERC20Metadata strategyAsset = IERC20Metadata(0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf); // CBBTC

    uint256 minFuzz = 10 ether; // DAI
    uint256 maxFuzz = 200_000 ether;

    function setUp() public virtual {
        setUp_fork();
        setUp_priceFeed();
        setUp_swapHelper();
        setUp_strategy();
        setUp_users();
    }

    function setUp_fork() internal {
        string memory url = vm.rpcUrl("mainnet");
        uint256 blockNumber = vm.envUint("BLOCK");
        assertGt(blockNumber, 0, "Please set BLOCK env variable");
        vm.createSelectFork(url, blockNumber);
    }

    function setUp_priceFeed() internal virtual {
        // DAI/ETH price feed on Chainlink
        priceFeed = new MockPriceFeed(CHAINLINK_FEED);
        require(priceFeed.latestAnswer() > 0, "oracle price negative or zero");
    }

    function setUp_swapHelper() internal virtual {
        require(address(priceFeed) != address(0x0), "price feed not setup");
        swap = ISwapHelper(SWAP);
    }

    function setUp_strategy() internal virtual {
        require(address(priceFeed) != address(0x0), "price feed not setup");
        require(address(swap) != address(0x0), "swap helper not setup");
        strategy = address(new CoinflakesBtcStrategy(address(swap), address(priceFeed)));
    }

    function setUp_users() internal virtual {
        user = address(1);
        vm.label(user, "user");
        CoinflakesBtcStrategy(strategy).allowDepositor(user);
        unallowedUser = address(2);
        vm.label(unallowedUser, "unallowedUser");
    }

    function test_allowedDepositors_revertsWhenNotAllowed() public virtual {
        deal(address(vaultAsset), unallowedUser, minFuzz);
        vm.prank(unallowedUser);
        vaultAsset.approve(strategy, minFuzz);
        vm.expectRevert(bytes("ERC4626: deposit more than max"));
        vm.prank(unallowedUser);
        ITokenizedStrategy(strategy).deposit(minFuzz, unallowedUser);
    }

    function test_deposit(uint256 amount) public virtual {
        vm.assume(amount >= minFuzz && amount <= maxFuzz);
        deal(address(vaultAsset), user, amount);
        vm.startPrank(user);
        vaultAsset.approve(strategy, amount);
        ITokenizedStrategy(strategy).deposit(amount, user);
        vm.stopPrank();
        assertEq(vaultAsset.balanceOf(user), 0, "not all assets deposited");
        uint256 assetsPurchased = strategyAsset.balanceOf(strategy);
        assertGt(assetsPurchased, 0, "no assets purchased");
        emit log_named_decimal_uint("assets deposited", amount, vaultAsset.decimals());
        emit log_named_decimal_uint("assets purchased", assetsPurchased, strategyAsset.decimals());
    }

    function test_withdraw_partialAmount(uint256 amount) public virtual {
        // This test should withdraw half of the deposited amount
        // and should result in the exact requested sum of assets.
        vm.assume(amount >= minFuzz && amount <= maxFuzz);
        depositIntoStrategy(amount);
        vm.startPrank(user);
        ITokenizedStrategy(strategy).withdraw(amount / 2, user, user);
        vm.stopPrank();
        assertEq(vaultAsset.balanceOf(user), amount / 2, "wrong amount of assets received");
    }

    function test_withdraw_fullAmount(uint256 amount) public virtual {
        // This test should withdraw all of the deposited amount
        // and should result in an acceptable loss because of
        // slippage or fees.
        vm.assume(amount >= minFuzz && amount <= maxFuzz);
        depositIntoStrategy(amount);

        uint256 acceptableLossBps = 300;

        vm.startPrank(user);
        ITokenizedStrategy(strategy).withdraw(amount, user, user, acceptableLossBps);
        vm.stopPrank();
        uint256 userBalance = vaultAsset.balanceOf(user);
        int256 slippage = userBalance.slippage(amount);
        assertLt(slippage, int256(acceptableLossBps), "not enough funds received");
        assertEq(strategyAsset.balanceOf(strategy), 0, "strategy not empty (strategyAsset)");
        assertEq(vaultAsset.balanceOf(strategy), 0, "strategy not empty (vaultAsset)");
    }

    function test_report_withProfit(uint256 amount) public virtual {
        vm.assume(amount >= minFuzz && amount <= maxFuzz);
        depositIntoStrategy(amount);

        uint256 currentPrice = simulatePriceUp();
        updatePriceFeed(currentPrice);

        (uint256 profit, uint256 loss) = ITokenizedStrategy(strategy).report();
        assertEq(loss, 0, "unexpected loss reported");
        assertGt(profit, 0, "no profit reported");
    }

    function test_report_withLoss(uint256 amount) public virtual {
        vm.assume(amount >= minFuzz && amount <= maxFuzz);
        depositIntoStrategy(amount);

        uint256 currentPrice = simulatePriceDown();
        updatePriceFeed(currentPrice);

        (uint256 profit, uint256 loss) = ITokenizedStrategy(strategy).report();
        assertEq(profit, 0, "unexpected profit reported");
        assertGt(loss, 0, "no loss reported");
    }

    function test_emergencyWithdraw_partialAmount(uint256 amount) public virtual {
        // This test should swap strategy assets into vault assets
        // within the strategy.
        vm.assume(amount >= minFuzz && amount <= maxFuzz);
        depositIntoStrategy(amount);

        ITokenizedStrategy(strategy).shutdownStrategy();
        uint256 withdrawAmount = amount / 2;
        ITokenizedStrategy(strategy).emergencyWithdraw(withdrawAmount);
        assertEq(vaultAsset.balanceOf(strategy), withdrawAmount, "incorrect amount of funds");
    }

    function test_emergencyWithdraw_fullAmount(uint256 amount) public virtual {
        // This test should swap strategy assets into vault assets
        // within the strategy. If there are not enough assets in the startegy to cover
        // the requested amount, the strategy should sell all assets and the loss
        // should be within an acceptable margin.
        uint256 acceptableLossBps = 300;

        vm.assume(amount >= minFuzz && amount <= maxFuzz);
        depositIntoStrategy(amount);

        ITokenizedStrategy(strategy).shutdownStrategy();
        ITokenizedStrategy(strategy).emergencyWithdraw(amount);

        uint256 balance = vaultAsset.balanceOf(strategy);
        int256 slippage = balance.slippage(amount);
        assertLt(slippage, int256(acceptableLossBps), "not enough funds converted");
        assertEq(strategyAsset.balanceOf(strategy), 0, "strategy not empty (strategyAsset)");
    }

    function airdrop(uint256 amount) internal virtual {
        require(address(vaultAsset) != address(0x0), "vault asset not initialized");
        require(address(user) != address(0x0), "user not initialized");
        deal(address(vaultAsset), user, amount);
        require(vaultAsset.balanceOf(user) == amount, "funding failed");
    }

    function depositIntoStrategy(uint256 amount) internal virtual {
        airdrop(amount);
        vm.startPrank(user);
        vaultAsset.approve(strategy, amount);
        ITokenizedStrategy(strategy).deposit(amount, user);
        vm.stopPrank();
        assertEq(vaultAsset.balanceOf(user), 0, "not all funds deposited");
        assertGe(strategyAsset.balanceOf(strategy), 0, "no funds purchased by strategy");
    }

    function simulatePriceUp() internal virtual returns (uint256 currentPrice) {
        uint256 sellAmount = maxFuzz * 3;
        airdrop(sellAmount);

        uint256 priceBefore;
        vm.startPrank(user);
        vaultAsset.approve(address(swap), sellAmount);
        if (swap.token0() == address(vaultAsset)) {
            priceBefore = swap.previewBuyToken1(10 ** strategyAsset.decimals());
            swap.sellToken0(sellAmount, 0, user);
            currentPrice = swap.previewBuyToken1(10 ** strategyAsset.decimals());
        } else {
            priceBefore = swap.previewBuyToken0(10 ** strategyAsset.decimals());
            swap.sellToken1(sellAmount, 0, user);
            currentPrice = swap.previewBuyToken1(10 ** strategyAsset.decimals());
        }
        vm.stopPrank();
        assertGt(currentPrice, priceBefore, "price did not increase");
    }

    function updatePriceFeed(uint256 newPrice) internal virtual {
        newPrice = newPrice.mulDiv(10 ** priceFeed.decimals(), 10 ** vaultAsset.decimals());
        priceFeed.update(int256(newPrice));
    }

    function simulatePriceDown() internal virtual returns (uint256 currentPrice) {
        uint256 buyAmount = maxFuzz * 3;
        airdrop(buyAmount);

        uint256 quote =
            swap.token0() == address(vaultAsset) ? swap.previewBuyToken0(buyAmount) : swap.previewBuyToken1(buyAmount);
        emit log_named_decimal_uint("quote", quote, strategyAsset.decimals());
        quote = quote.applySlippage(500);
        emit log_named_decimal_uint("quote", quote, strategyAsset.decimals());

        deal(address(strategyAsset), user, quote);

        uint256 priceBefore;
        vm.startPrank(user);
        strategyAsset.approve(address(swap), quote);
        if (swap.token0() == address(vaultAsset)) {
            priceBefore = swap.previewBuyToken1(10 ** strategyAsset.decimals());
            swap.buyToken0(buyAmount, quote, user);
            currentPrice = swap.previewBuyToken1(10 ** strategyAsset.decimals());
        } else {
            priceBefore = swap.previewBuyToken0(10 ** strategyAsset.decimals());
            swap.buyToken1(buyAmount, quote, user);
            currentPrice = swap.previewBuyToken1(10 ** strategyAsset.decimals());
        }
        vm.stopPrank();
        assertLt(currentPrice, priceBefore, "price did not decrease");
    }
}
