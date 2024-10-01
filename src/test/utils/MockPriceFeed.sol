// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

import { ISwapHelper } from "swap-helpers/src/interfaces/ISwapHelper.sol";
import { IAggregator } from "swap-helpers/src/interfaces/chainlink/IAggregator.sol";

contract MockPriceFeed is IAggregator {
    ISwapHelper public swap;

    IAggregator immutable origin;
    int256 private latestAnswer;
    uint256 private latestTimestamp;

    uint8 public decimals;

    constructor(address originAddress) {
        origin = IAggregator(originAddress);
        (, latestAnswer,, latestTimestamp,) = origin.latestRoundData();
        latestTimestamp = block.timestamp;
        decimals = origin.decimals();
    }

    function update() public {
        latestTimestamp = block.timestamp;
    }

    function update(int256 newPrice) public {
        latestAnswer = newPrice;
        latestTimestamp = block.timestamp;
    }

    function latestRound() public pure returns (uint256) {
        revert("not implemented");
    }

    function getAnswer(uint256) public pure returns (int256) {
        revert("not implemented");
    }

    function setLatestAnswer(int256 newAnswer) public {
        latestAnswer = newAnswer;
    }

    function setLatestTimestamp(uint256 newTimestamp) public {
        latestTimestamp = newTimestamp;
    }

    function resetOrigin() public {
        (, latestAnswer,, latestTimestamp,) = origin.latestRoundData();
    }

    function description() external pure override returns (string memory) {
        revert("not implemented");
    }

    function version() external pure override returns (uint256) {
        revert("not implemented");
    }

    function getRoundData(uint80) external pure override returns (uint80, int256, uint256, uint256, uint80) {
        revert("not implemented");
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        roundId = 0;
        answer = latestAnswer;
        startedAt = 0;
        updatedAt = latestTimestamp;
        answeredInRound = 0;
    }
}
