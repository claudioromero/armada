// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";

/// @title IVaultTransparentProxy
/// @notice Interface exposing the admin-only and read-only functions of a transparent proxy.
interface IVaultTransparentProxy is IERC1967 {
    /// @notice Upgrades the proxy to a new implementation, optionally calling an initializer.
    /// @dev Only callable by the proxy admin.
    /// @param newImplementation The address of the new implementation contract.
    /// @param data The encoded call to make on the new implementation, if any.
    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable;

    /// @notice Returns the current implementation contract address.
    /// @return The implementation address.
    function implementation() external view returns (address);

    /// @notice Returns the current admin address.
    /// @return The admin address.
    function admin() external view returns (address);
}
