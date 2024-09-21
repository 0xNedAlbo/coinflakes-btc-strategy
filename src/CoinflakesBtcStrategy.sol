// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { BaseStrategy } from "@tokenized-strategy/BaseStrategy.sol";

import { IAggregator } from "swap-helpers/src/interfaces/chainlink/IAggregator.sol";

import { ISwapHelper } from "swap-helpers/src/interfaces/ISwapHelper.sol";
import { Slippage } from "swap-helpers/src/utils/Slippage.sol";

contract CoinflakesBtcStrategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using SafeERC20 for ERC20;

    using Slippage for uint256;

    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public constant MAX_BPS = 10_000; // 100 Percent

    IAggregator public priceFeed;
    ISwapHelper public swap;

    IERC20 public WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    int24 public maxSlippage = 1000; // BPS
    uint256 public maxOracleDelay = 30 minutes;

    uint8 oracleDecimals;

    event SwapChange(address indexed newSwap);
    event MaxSlippageChange(int24 maxSlippage);
    event PriceFeedChange(address indexed priceFeed);
    event MaxOracleDelayChange(uint256 newDelay);

    address private token0;
    address private token1;

    EnumerableSet.AddressSet allowedDepositors;

    event AllowDepositor(address indexed depositor);
    event DisallowDepositor(address indexed depositor);

    modifier withOracleSynced() {
        require(priceFeed.latestTimestamp() > block.timestamp - maxOracleDelay, "oracle out of date");
        _;
    }

    constructor(
        address swapAddress,
        address priceFeedAddress
    )
        BaseStrategy(0x6B175474E89094C44Da98b954EedeAC495271d0F, "Coinflakes Eth Strategy")
    {
        swap = ISwapHelper(swapAddress);
        token0 = swap.token0();
        token1 = swap.token1();
        priceFeed = IAggregator(priceFeedAddress);
        oracleDecimals = priceFeed.decimals();
        emit PriceFeedChange(priceFeedAddress);
        emit MaxSlippageChange(maxSlippage);
        emit SwapChange(swapAddress);
        emit MaxOracleDelayChange(maxOracleDelay);
    }

    function _deployFunds(uint256 daiAmount) internal override withOracleSynced {
        // Get a market quote from price feed
        int256 marketPrice = priceFeed.latestAnswer();
        require(marketPrice > 0, "invalid price from oracle");
        uint256 marketQuote = daiAmount * (10 ** oracleDecimals) / uint256(marketPrice);
        // Swap tokens, apply slippage to market quote
        asset.approve(address(swap), daiAmount);
        if (token0 == address(asset)) {
            swap.sellToken0(daiAmount, marketQuote.applySlippage(-maxSlippage), address(this));
        } else {
            swap.sellToken1(daiAmount, marketQuote.applySlippage(-maxSlippage), address(this));
        }
    }

    function _freeFunds(uint256 daiAmount) internal override withOracleSynced {
        int256 marketPrice = priceFeed.latestAnswer();
        require(marketPrice > 0, "invalid price from oracle");
        uint256 marketQuote = daiAmount * (10 ** oracleDecimals) / uint256(marketPrice);
        uint256 wethBalance = WETH.balanceOf(address(this));
        uint256 wethAmountMax = marketQuote.applySlippage(maxSlippage);
        if (wethAmountMax > wethBalance) wethAmountMax = wethBalance;
        WETH.approve(address(swap), wethAmountMax);
        if (token0 == address(asset)) {
            swap.buyToken0(daiAmount, wethAmountMax, address(this));
        } else {
            swap.buyToken1(daiAmount, wethAmountMax, address(this));
        }
    }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        int256 marketPrice = priceFeed.latestAnswer();
        require(marketPrice > 0, "invalid price from oracle");
        uint256 wethBalance = WETH.balanceOf(address(this));
        uint256 marketQuote = wethBalance * uint256(marketPrice) / (10 ** oracleDecimals);
        _totalAssets = swap.previewSellToken1(wethBalance);
        int24 slippage = marketQuote.slippage(_totalAssets);
        require(slippage > -maxSlippage, "oracle deviation");
        _totalAssets += asset.balanceOf(address(this));
    }

    function availableDepositLimit(address owner) public view virtual override returns (uint256) {
        if (allowedDepositors.contains(owner)) return type(uint256).max;
        return 0;
    }

    function _emergencyWithdraw(uint256 _amount) internal virtual override {
        uint256 wethBalance = WETH.balanceOf(address(this));
        uint256 wethRequired = swap.previewBuyToken0(_amount).applySlippage(maxSlippage);
        if (wethBalance < wethRequired) wethRequired = wethBalance;
        WETH.approve(address(swap), wethRequired);
        swap.buyToken0(_amount, wethRequired, address(this));
    }

    function changeSwap(address newSwap) public onlyManagement {
        swap = ISwapHelper(newSwap);
        token0 = swap.token0();
        token1 = swap.token1();
        emit SwapChange(address(swap));
    }

    function setMaxSlippage(int24 newMaxSlippage) public onlyManagement {
        require(newMaxSlippage > 0, "negative slippage");
        maxSlippage = newMaxSlippage;
        emit MaxSlippageChange(maxSlippage);
    }

    function setPriceFeed(address newPriceFeed) public onlyManagement {
        priceFeed = IAggregator(newPriceFeed);
        oracleDecimals = priceFeed.decimals();
        emit PriceFeedChange(address(priceFeed));
    }

    function setMaxOracleDelay(uint256 newDelay) public onlyManagement {
        maxOracleDelay = newDelay;
        emit MaxOracleDelayChange(maxOracleDelay);
    }

    function allowDepositor(address depositor) public onlyManagement {
        if (allowedDepositors.add(depositor)) emit AllowDepositor(depositor);
    }

    function disallowDepositor(address depositor) public onlyManagement {
        if (allowedDepositors.remove(depositor)) emit DisallowDepositor(depositor);
    }

    function isallowedDepositor(address depositor) public view returns (bool) {
        return allowedDepositors.contains(depositor);
    }
}
