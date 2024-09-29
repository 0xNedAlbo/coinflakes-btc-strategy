// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

import { StdCheats } from "forge-std/src/StdCheats.sol";
import { IERC20 } from "mock-tokens/src/interfaces/IWETH.sol";
import { ISwapHelper } from "swap-helpers/src/interfaces/ISwapHelper.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockSwapHelper is StdCheats, ISwapHelper {
    using SafeERC20 for IERC20;

    IERC20 public immutable DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 public immutable CBBTC = IERC20(0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf);

    address public token0 = address(DAI);
    address public token1 = address(CBBTC);

    uint256 public btcPrice = 60_000 * (10 ** 8);

    function previewSellToken0(uint256 amountA) public view override returns (uint256) {
        return (amountA * (10 ** 8)) / btcPrice;
    }

    function previewSellToken1(uint256 amountB) public view override returns (uint256) {
        return (amountB * btcPrice) / (10 ** 8);
    }

    function previewBuyToken0(uint256 amountA) public view override returns (uint256) {
        return (amountA * (10 ** 8)) / btcPrice;
    }

    function previewBuyToken1(uint256 amountB) public view override returns (uint256) {
        return (amountB * btcPrice) / (10 ** 8);
    }

    function sellToken0(
        uint256 amountA,
        uint256 minAmountB,
        address receiver
    )
        public
        override
        returns (uint256 amountOut)
    {
        amountOut = previewSellToken0(amountA);
        require(amountOut >= minAmountB, "slippage");
        DAI.safeTransferFrom(msg.sender, address(this), amountA);
        deal(address(CBBTC), address(this), amountOut);
        CBBTC.transfer(receiver, amountOut);
    }

    function sellToken1(
        uint256 amountB,
        uint256 minAmountA,
        address receiver
    )
        public
        override
        returns (uint256 amountOut)
    {
        amountOut = previewSellToken1(amountB);
        require(amountOut >= minAmountA, "slippage");
        CBBTC.safeTransferFrom(msg.sender, address(this), amountB);
        deal(address(DAI), address(this), amountOut);
        DAI.transfer(receiver, amountOut);
    }

    function buyToken0(
        uint256 amountA,
        uint256 maxAmountB,
        address receiver
    )
        public
        override
        returns (uint256 amountIn)
    {
        amountIn = previewBuyToken0(amountA);
        require(amountIn <= maxAmountB, "slippage");
        CBBTC.safeTransferFrom(msg.sender, address(this), amountIn);
        deal(address(DAI), address(this), amountA);
        DAI.transfer(receiver, amountA);
    }

    function buyToken1(
        uint256 amountB,
        uint256 maxAmountA,
        address receiver
    )
        public
        override
        returns (uint256 amountIn)
    {
        amountIn = previewBuyToken1(amountB);
        require(amountIn <= maxAmountA, "slippage");
        DAI.safeTransferFrom(msg.sender, address(this), amountIn);
        deal(address(CBBTC), address(this), amountB);
        CBBTC.transfer(receiver, amountB);
    }

    function setBtcPrice(uint256 newPrice) public {
        btcPrice = newPrice;
    }
}
