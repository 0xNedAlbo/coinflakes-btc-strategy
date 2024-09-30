// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "forge-std/src/console2.sol";
import { ExtendedTest } from "./ExtendedTest.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { CoinflakesBtcStrategy } from "../../CoinflakesBtcStrategy.sol";
import { IStrategyInterface } from "../../interfaces/IStrategyInterface.sol";

import { UniswapV3Helper } from "swap-helpers/src/UniswapV3Helper.sol";

import { IAggregator } from "swap-helpers/src/interfaces/chainlink/IAggregator.sol";

import { MockSwapHelper } from "./MockSwapHelper.sol";
import { MockPriceFeed } from "./MockPriceFeed.sol";

// Inherit the events so they can be checked if desired.
import { IEvents } from "@tokenized-strategy/interfaces/IEvents.sol";

interface IFactory {
    function governance() external view returns (address);

    function set_protocol_fee_bps(uint16) external;

    function set_protocol_fee_recipient(address) external;
}

contract Setup is ExtendedTest, IEvents {
    // Contract instances that we will use repeatedly.
    ERC20 public asset;
    IStrategyInterface public strategy;

    address public constant CHAINLINK_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c; // BTC/USD
    MockSwapHelper public swap;
    MockPriceFeed public priceFeed;

    mapping(string => address) public tokenAddrs;

    // Addresses for different roles we will use repeatedly.
    address public user = address(10);
    address public keeper = address(4);
    address public management = address(1);
    address public performanceFeeRecipient = address(3);

    // Address of the real deployed Factory
    address public factory;

    // Integer variables that will be used repeatedly.
    uint256 public decimals;
    uint256 public MAX_BPS = 10_000;

    // Fuzz from $0.01 of 1e6 stable coins up to 1 trillion of a 1e18 coin
    uint256 public maxFuzzAmount = 1e24;
    uint256 public minFuzzAmount = 1e17;

    // Default profit max unlock time is set for 10 days
    uint256 public profitMaxUnlockTime = 10 days;

    function setUp() public virtual {
        setUp_fork();
        _setTokenAddrs();

        // Set asset
        asset = ERC20(tokenAddrs["DAI"]);

        // Set decimals
        decimals = asset.decimals();

        // Deploy strategy and set variables
        strategy = IStrategyInterface(setUpStrategy());

        factory = strategy.FACTORY();

        // label all the used addresses for traces
        vm.label(keeper, "keeper");
        vm.label(factory, "factory");
        vm.label(address(asset), "asset");
        vm.label(management, "management");
        vm.label(address(strategy), "strategy");
        vm.label(performanceFeeRecipient, "performanceFeeRecipient");
    }

    function setUp_fork() public {
        string memory url = vm.rpcUrl("mainnet");
        uint256 blockNumber = vm.envUint("BLOCK");
        assertGt(blockNumber, 0, "Please set BLOCK env variable");
        vm.createSelectFork(url, blockNumber);
    }

    function setUp_priceFeed() public virtual {
        // DAI/ETH price feed on Chainlink
        priceFeed = new MockPriceFeed(CHAINLINK_FEED);
        require(priceFeed.latestAnswer() > 0, "oracle price negative or zero");
    }

    function setUp_swapHelper() public virtual {
        require(address(priceFeed) != address(0x0), "price feed not setup");
        swap = new MockSwapHelper();
        swap.setPrice(uint256(priceFeed.latestAnswer()));
        swap.setPriceDecimals(priceFeed.decimals());
    }

    function setUpStrategy() public returns (address) {
        setUp_priceFeed();
        setUp_swapHelper();
        // we save the strategy as a IStrategyInterface to give it the needed interface
        IStrategyInterface _strategy =
            IStrategyInterface(address(new CoinflakesBtcStrategy(address(swap), address(priceFeed))));

        // set keeper
        _strategy.setKeeper(keeper);
        // set treasury
        _strategy.setPerformanceFeeRecipient(performanceFeeRecipient);
        // set management of the strategy
        _strategy.setPendingManagement(management);
        // set depositor
        CoinflakesBtcStrategy(address(_strategy)).allowDepositor(user);

        vm.prank(management);
        _strategy.acceptManagement();

        return address(_strategy);
    }

    function depositIntoStrategy(IStrategyInterface _strategy, address _user, uint256 _amount) public {
        vm.prank(_user);
        asset.approve(address(_strategy), _amount);

        vm.prank(_user);
        _strategy.deposit(_amount, _user);
    }

    function mintAndDepositIntoStrategy(IStrategyInterface _strategy, address _user, uint256 _amount) public {
        airdrop(asset, _user, _amount);
        depositIntoStrategy(_strategy, _user, _amount);
    }

    // For checking the amounts in the strategy
    function checkStrategyTotals(
        IStrategyInterface _strategy,
        uint256 _totalAssets,
        uint256 _totalDebt,
        uint256 _totalIdle
    )
        public
        view
    {
        uint256 _assets = _strategy.totalAssets();
        uint256 _balance = ERC20(_strategy.asset()).balanceOf(address(_strategy));
        uint256 _idle = _balance > _assets ? _assets : _balance;
        uint256 _debt = _assets - _idle;
        assertEq(_assets, _totalAssets, "!totalAssets");
        assertEq(_debt, _totalDebt, "!totalDebt");
        assertEq(_idle, _totalIdle, "!totalIdle");
        assertEq(_totalAssets, _totalDebt + _totalIdle, "!Added");
    }

    function airdrop(ERC20 _asset, address _to, uint256 _amount) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount);
    }

    function setFees(uint16 _protocolFee, uint16 _performanceFee) public {
        address gov = IFactory(factory).governance();

        // Need to make sure there is a protocol fee recipient to set the fee.
        vm.prank(gov);
        IFactory(factory).set_protocol_fee_recipient(gov);

        vm.prank(gov);
        IFactory(factory).set_protocol_fee_bps(_protocolFee);

        vm.prank(management);
        strategy.setPerformanceFee(_performanceFee);
    }

    function _setTokenAddrs() internal {
        tokenAddrs["WETH"] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        tokenAddrs["USDT"] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        tokenAddrs["DAI"] = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        tokenAddrs["USDC"] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    }

    function simulatePriceChange(int24 bps) public {
        if (bps < -10_000) revert("negative bps more than negative max");
        int256 currentPrice = int256(swap.price());
        currentPrice += currentPrice * 10_000 / bps;
        swap.setPrice(uint256(currentPrice));
        priceFeed.update(int256(currentPrice));
    }
}
