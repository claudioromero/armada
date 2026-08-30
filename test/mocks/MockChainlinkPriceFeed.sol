// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

contract MockChainlinkPriceFeed {
    address public immutable dataFeedId;
    string public description;
    uint8 public immutable decimals;
    int256 public answer;
    uint256 public round = 1;
    uint256 public updatedAt;
    uint80 public answeredInRound = 1;

    constructor(uint8 decimals_, int256 answer_) {
        decimals = decimals_;
        answer = answer_;
        updatedAt = block.timestamp;
    }

    function setAnswer(int256 newAnswer) external {
        answer = newAnswer;
        round += 1;
        answeredInRound = uint80(round);
        updatedAt = block.timestamp;
    }

    function setUpdatedAt(uint256 updatedAt_) external {
        updatedAt = updatedAt_;
    }

    function setAnsweredInRound(uint80 answeredInRound_) external {
        answeredInRound = answeredInRound_;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer_, uint256 startedAt, uint256 updatedAt_, uint80 answeredInRound_)
    {
        // casting to 'uint80' is safe because round counter is small
        // forge-lint: disable-next-line(unsafe-typecast)
        return (uint80(round), answer, 0, updatedAt, answeredInRound);
    }

    function getRoundData(uint80) external view returns (uint80, int256, uint256, uint256, uint80) {
        return (0, answer, 0, updatedAt, 0);
    }

    function getAnswer(uint256) external view returns (int256) {
        return answer;
    }
}
