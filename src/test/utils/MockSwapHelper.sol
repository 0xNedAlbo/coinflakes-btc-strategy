// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

import { StdCheats } from "forge-std/src/StdCheats.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ISwapHelper } from "swap-helpers/src/interfaces/ISwapHelper.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { console } from "forge-std/src/console.sol";

contract MockSwapHelper is StdCheats, ISwapHelper {
    using SafeERC20 for IERC20Metadata;
    using Math for uint256;

    IERC20Metadata public immutable DAI = IERC20Metadata(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20Metadata public immutable CBBTC = IERC20Metadata(0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf);

    uint8 token0Decimals;
    uint8 token1Decimals;

    address public token0 = address(DAI);
    address public token1 = address(CBBTC);

    uint256 public price;
    uint8 public priceDecimals;

    constructor() {
        priceDecimals = 8;
        price = 60_000 * (10 ** priceDecimals);

        token0Decimals = DAI.decimals();
        token1Decimals = CBBTC.decimals();
    }

    function previewSellToken0(uint256 amount0) public view override returns (uint256 amount1) {
        amount1 = amount0.mulDiv(10 ** (token1Decimals + priceDecimals), price * (10 ** token0Decimals));
    }

    function previewSellToken1(uint256 amount1) public view override returns (uint256 amount0) {
        amount0 = amount1.mulDiv((10 ** token0Decimals) * price, 10 ** (token1Decimals + priceDecimals));
    }

    function previewBuyToken0(uint256 amount0) public view override returns (uint256 amount1) {
        amount1 = previewSellToken0(amount0);
    }

    function previewBuyToken1(uint256 amount1) public view override returns (uint256 amount0) {
        amount0 = previewSellToken1(amount1);
    }

    function sellToken0(
        uint256 amount0,
        uint256 minAmount1,
        address receiver
    )
        public
        override
        returns (uint256 amountOut)
    {
        amountOut = previewSellToken0(amount0);
        require(amountOut >= minAmount1, "slippage");
        DAI.safeTransferFrom(msg.sender, address(this), amount0);
        deal(address(CBBTC), address(this), amountOut);
        CBBTC.transfer(receiver, amountOut);
    }

    function sellToken1(
        uint256 amount1,
        uint256 minAmount0,
        address receiver
    )
        public
        override
        returns (uint256 amountOut)
    {
        amountOut = previewSellToken1(amount1);
        require(amountOut >= minAmount0, "slippage");
        CBBTC.safeTransferFrom(msg.sender, address(this), amount1);
        deal(address(DAI), address(this), amountOut);
        DAI.transfer(receiver, amountOut);
    }

    function buyToken0(
        uint256 amount0,
        uint256 maxAmount1,
        address receiver
    )
        public
        override
        returns (uint256 amountIn)
    {
        amountIn = previewBuyToken0(amount0);
        require(amountIn <= maxAmount1, "slippage");
        CBBTC.safeTransferFrom(msg.sender, address(this), amountIn);
        deal(address(DAI), address(this), amount0);
        DAI.transfer(receiver, amount0);
    }

    function buyToken1(
        uint256 amount1,
        uint256 maxAmount0,
        address receiver
    )
        public
        override
        returns (uint256 amountIn)
    {
        amountIn = previewBuyToken1(amount1);
        require(amountIn <= maxAmount0, "slippage");
        DAI.safeTransferFrom(msg.sender, address(this), amountIn);
        deal(address(CBBTC), address(this), amount1);
        CBBTC.transfer(receiver, amount1);
    }

    function setPrice(uint256 newPrice) public {
        price = newPrice;
    }

    function setPriceDecimals(uint8 newPriceDecimals) public {
        priceDecimals = newPriceDecimals;
    }
}
