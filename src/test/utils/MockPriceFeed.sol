// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

import { ISwapHelper } from "swap-helpers/src/interfaces/ISwapHelper.sol";
import { IAggregator } from "swap-helpers/src/interfaces/chainlink/IAggregator.sol";

contract MockPriceFeed is IAggregator {
    ISwapHelper public swap;

    int256 public latestAnswer;
    uint256 public latestTimestamp;

    uint8 public decimals = 8;

    constructor(address swapAddress) {
        swap = ISwapHelper(swapAddress);
        latestAnswer = int256(swap.previewBuyToken1(1 ether) / 10 ** 10);
        latestTimestamp = block.timestamp;
    }

    function update() external {
        latestAnswer = int256(swap.previewBuyToken1(1 ether) / 10 ** 10);
        latestTimestamp = block.timestamp;
    }

    function latestRound() external pure returns (uint256) {
        revert("not implemented");
    }

    function getAnswer(uint256) external pure returns (int256) {
        revert("not implemented");
    }

    function getTimestamp(uint256) external pure returns (uint256) {
        revert("not implemented");
    }

    function setLatestAnswer(int256 newAnswer) public {
        latestAnswer = newAnswer;
    }

    function setLatestTimestamp(uint256 newTimestamp) public {
        latestTimestamp = newTimestamp;
    }
}
