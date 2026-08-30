// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

/// @title IPriceFeed
/// @notice Interface for a Chainlink-compatible USD price feed.
interface IPriceFeed {
    /// @notice Returns the latest price data from the feed.
    /// @return roundId The round id of the latest round.
    /// @return answer The latest price in the feed's configured decimals.
    /// @return startedAt The timestamp when the round started.
    /// @return updatedAt The timestamp when the round was last updated.
    /// @return answeredInRound The round in which the answer was computed.
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    /// @notice Returns the number of decimals used by the feed's price.
    /// @return The number of decimals.
    function decimals() external view returns (uint8);
}
