// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

import { Test } from "forge-std/src/Test.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { CoinflakesBtcStrategy, IAggregator, ISwapHelper } from "../CoinflakesBtcStrategy.sol";
import { ITokenizedStrategy } from "@tokenized-strategy/interfaces/ITokenizedStrategy.sol";

contract CoinflakesBtcStrategyTest is Test {
    address public constant CHAINLINK_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c; // BTC/USD
    address public constant SWAP = 0x4Ea53f0F9fDD145AC640597AE85a56510599Dc18; // DAI/CBBTC

    IAggregator public priceFeed;
    ISwapHelper public swap;

    address strategy;
    address user;

    IERC20Metadata vaultAsset = IERC20Metadata(0x6B175474E89094C44Da98b954EedeAC495271d0F); // DAI
    IERC20Metadata strategyAsset = IERC20Metadata(0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf); // CBBTC

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
        priceFeed = IAggregator(CHAINLINK_FEED);
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
        user = vm.addr(1);
        vm.label(user, "user");
        CoinflakesBtcStrategy(strategy).allowDepositor(user);
    }

    function test_live_operation() public virtual {
        uint256 acceptableLossBps = 300;

        uint256 assetAmount = 10_000 ether;
        deal(address(vaultAsset), user, assetAmount);
        vm.startPrank(user);
        vaultAsset.approve(strategy, assetAmount);
        ITokenizedStrategy(strategy).deposit(assetAmount, user);
        vm.stopPrank();
        assertEq(vaultAsset.balanceOf(user), 0, "not all assets deposited");
        uint256 assetsPurchased = strategyAsset.balanceOf(strategy);
        assertGt(assetsPurchased, 0, "no assets purchased");
        emit log_named_decimal_uint("assets deposited", assetAmount, vaultAsset.decimals());
        emit log_named_decimal_uint("assets purchased", assetsPurchased, strategyAsset.decimals());

        vm.startPrank(user);
        ITokenizedStrategy(strategy).withdraw(assetAmount / 2, user, user);
        vm.stopPrank();

        assetAmount -= assetAmount / 2;
        vm.startPrank(user);
        ITokenizedStrategy(strategy).withdraw(assetAmount, user, user, acceptableLossBps);
        vm.stopPrank();
    }
}
