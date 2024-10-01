// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { IERC20, ERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { BaseStrategy } from "@tokenized-strategy/BaseStrategy.sol";

import { IAggregator } from "swap-helpers/src/interfaces/chainlink/IAggregator.sol";

import { ISwapHelper } from "swap-helpers/src/interfaces/ISwapHelper.sol";
import { Slippage } from "swap-helpers/src/utils/Slippage.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract CoinflakesBtcStrategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using SafeERC20 for ERC20;

    using Math for uint256;

    using Slippage for uint256;

    using EnumerableSet for EnumerableSet.AddressSet;

    IERC20 public constant CBBTC = IERC20(0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf);

    uint256 public constant MAX_BPS = 10_000; // 100 Percent

    IAggregator public oracle;
    uint8 oracleDecimals;
    uint256 public maxOracleDelay = 60 minutes;

    address public immutable vault;

    ISwapHelper public swap;
    int24 public maxSlippage = 100; // BPS

    event SwapChange(address indexed newSwap);
    event MaxSlippageChange(int24 maxSlippage);
    event PriceFeedChange(address indexed priceFeed);
    event MaxOracleDelayChange(uint256 newDelay);

    address private token0;
    address private token1;

    uint8 private token0Decimals;
    uint8 private token1Decimals;

    EnumerableSet.AddressSet allowedDepositors;

    event AllowDepositor(address indexed depositor);
    event DisallowDepositor(address indexed depositor);

    modifier withOracleSynced() {
        require(oracle.latestTimestamp() > block.timestamp - maxOracleDelay, "oracle out of date");
        _;
    }

    constructor(
        address swapAddress,
        address oracleAddress
    )
        BaseStrategy(0x6B175474E89094C44Da98b954EedeAC495271d0F, "Coinflakes BTC Strategy")
    {
        setupSwap(swapAddress);
        setupOracle(oracleAddress);
        emit MaxSlippageChange(maxSlippage);
        emit MaxOracleDelayChange(maxOracleDelay);
    }

    function setupSwap(address swapAddress) internal {
        swap = ISwapHelper(swapAddress);
        token0 = swap.token0();
        token1 = swap.token1();
        token0Decimals = IERC20Metadata(token0).decimals();
        token1Decimals = IERC20Metadata(token1).decimals();
        emit SwapChange(swapAddress);
    }

    function setupOracle(address oracleAddress) internal {
        oracle = IAggregator(oracleAddress);
        oracleDecimals = oracle.decimals();
        emit PriceFeedChange(oracleAddress);
    }

    function _deployFunds(uint256 daiAmount) internal override withOracleSynced {
        // Get a market quote from price feed
        int256 marketPrice = oracle.latestAnswer();
        require(marketPrice > 0, "invalid price from oracle");
        uint256 marketQuote = daiAmount.mulDiv(10 ** oracleDecimals, uint256(marketPrice));
        // Swap tokens, apply slippage to market quote
        asset.approve(address(swap), daiAmount);
        if (token0 == address(asset)) {
            marketQuote = marketQuote.mulDiv(10 ** token1Decimals, 10 ** token0Decimals);
            uint256 minBtcAmount = marketQuote.applySlippage(-maxSlippage);
            swap.sellToken0(daiAmount, minBtcAmount, address(this));
        } else {
            marketQuote = marketQuote.mulDiv(10 ** token0Decimals, 10 ** token1Decimals);
            uint256 minBtcAmount = marketQuote.applySlippage(-maxSlippage);
            swap.sellToken1(daiAmount, minBtcAmount, address(this));
        }
    }

    function _freeFunds(uint256 daiAmount) internal override withOracleSynced {
        int256 marketPrice = oracle.latestAnswer();
        require(marketPrice > 0, "invalid price from oracle");
        uint256 marketQuote = daiAmount * (10 ** oracleDecimals) / uint256(marketPrice);
        if (token0 == address(asset)) {
            marketQuote = marketQuote.mulDiv(10 ** token1Decimals, 10 ** token0Decimals);
        } else {
            marketQuote = marketQuote.mulDiv(10 ** token0Decimals, 10 ** token1Decimals);
        }
        uint256 cbbtcBalance = CBBTC.balanceOf(address(this));
        uint256 cbbtcAmountMax = marketQuote.applySlippage(maxSlippage);
        if (cbbtcAmountMax < cbbtcBalance) {
            // CBBBTC value is enough to pay out.
            CBBTC.approve(address(swap), cbbtcAmountMax);
            if (token0 == address(asset)) {
                swap.buyToken0(daiAmount, cbbtcAmountMax, address(this));
            } else {
                swap.buyToken1(daiAmount, cbbtcAmountMax, address(this));
            }
        } else {
            // CBBTC value is below requested amount
            // => sell everything and pay out the rest
            CBBTC.approve(address(swap), cbbtcBalance);
            if (token0 == address(asset)) {
                swap.sellToken1(cbbtcBalance, 0, address(this));
            } else {
                swap.sellToken0(cbbtcBalance, 0, address(this));
            }
        }
    }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        uint256 cbbtcBalance = CBBTC.balanceOf(address(this));
        if (cbbtcBalance > 0) {
            if (token0 == address(asset)) {
                _totalAssets = swap.previewSellToken1(cbbtcBalance);
            } else {
                _totalAssets = swap.previewSellToken0(cbbtcBalance);
            }
        }
        _totalAssets += asset.balanceOf(address(this));
    }

    function availableDepositLimit(address owner) public view virtual override returns (uint256) {
        if (allowedDepositors.contains(owner)) return type(uint256).max;
        return 0;
    }

    function _emergencyWithdraw(uint256 _amount) internal virtual override {
        uint256 cbbtcBalance = CBBTC.balanceOf(address(this));
        uint256 cbbtcRequired;
        if (token0 == address(asset)) {
            cbbtcRequired = swap.previewBuyToken0(_amount).applySlippage(maxSlippage);
        } else {
            cbbtcRequired = swap.previewBuyToken1(_amount).applySlippage(maxSlippage);
        }
        if (cbbtcRequired < cbbtcBalance) {
            CBBTC.approve(address(swap), cbbtcRequired);
            if (token0 == address(asset)) {
                swap.buyToken0(_amount, cbbtcRequired, address(this));
            } else {
                swap.buyToken1(_amount, cbbtcRequired, address(this));
            }
        } else {
            CBBTC.approve(address(swap), cbbtcBalance);
            if (token0 == address(CBBTC)) {
                swap.sellToken0(cbbtcBalance, 0, address(this));
            } else {
                swap.sellToken1(cbbtcBalance, 0, address(this));
            }
        }
    }

    function changeSwap(address newSwap) public onlyManagement {
        swap = ISwapHelper(newSwap);
        token0 = swap.token0();
        token1 = swap.token1();
        emit SwapChange(address(swap));
    }

    function setMaxSlippage(int24 newMaxSlippage) public onlyManagement {
        require(newMaxSlippage > 0, "negative slippage");
        require(newMaxSlippage <= Slippage.MAX_BPS, "invalid bps");
        maxSlippage = newMaxSlippage;
        emit MaxSlippageChange(maxSlippage);
    }

    function setPriceFeed(address newPriceFeed) public onlyManagement {
        oracle = IAggregator(newPriceFeed);
        oracleDecimals = oracle.decimals();
        emit PriceFeedChange(address(oracle));
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

    function isAllowedDepositor(address depositor) public view returns (bool) {
        return allowedDepositors.contains(depositor);
    }
}
