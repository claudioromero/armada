// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {IVaultTransparentProxy} from "./IVaultTransparentProxy.sol";

/// @title VaultTransparentProxy
/// @notice A transparent upgradeable proxy implementing the ERC-1967 standard.
/// @dev The admin can only call `upgradeToAndCall`, while all other callers are transparently
///      forwarded to the implementation. The admin is immutable and set at construction.
contract VaultTransparentProxy is ERC1967Proxy {
    /// @notice Thrown when the admin attempts to call a non-upgrade function through the proxy.
    error ProxyDeniedAdminAccess();

    /// @notice Thrown when the provided admin is the zero address.
    /// @param admin The invalid admin address.
    error ProxyInvalidAdmin(address admin);

    /// @notice The immutable address of the proxy admin.
    address private immutable _admin;

    /// @notice Initializes the proxy with an implementation, an admin and optional init data.
    /// @param implementation_ The address of the implementation contract.
    /// @param admin_ The address of the proxy admin.
    /// @param _data The encoded initialization call, forwarded to the implementation.
    /// @custom:reverts ProxyInvalidAdmin If `admin_` is the zero address.
    constructor(address implementation_, address admin_, bytes memory _data)
        payable
        ERC1967Proxy(implementation_, _data)
    {
        if (admin_ == address(0)) {
            revert ProxyInvalidAdmin(admin_);
        }
        _admin = admin_;
        ERC1967Utils.changeAdmin(admin_);
    }

    /// @notice Returns the immutable proxy admin address.
    /// @dev Override hook so the admin value can be read without storage.
    /// @return The proxy admin address.
    function _proxyAdmin() internal view virtual returns (address) {
        return _admin;
    }

    /// @notice Returns the current implementation contract address.
    /// @return The implementation address.
    function implementation() external view returns (address) {
        return ERC1967Utils.getImplementation();
    }

    /// @notice Returns the current proxy admin address.
    /// @return The admin address.
    function admin() external view returns (address) {
        return _proxyAdmin();
    }

    /// @notice Handles calls not resolved by the proxy's own functions.
    /// @dev The admin may only call `upgradeToAndCall`; any other call reverts. All other
    ///      callers are forwarded to the implementation.
    function _fallback() internal virtual override {
        if (msg.sender == _proxyAdmin()) {
            if (msg.sig != IVaultTransparentProxy.upgradeToAndCall.selector) {
                revert ProxyDeniedAdminAccess();
            } else {
                _dispatchUpgradeToAndCall();
            }
        } else {
            super._fallback();
        }
    }

    /// @notice Decodes and executes an upgrade request from the admin.
    /// @dev Parses the `upgradeToAndCall(address,bytes)` calldata and updates the implementation.
    function _dispatchUpgradeToAndCall() private {
        (address newImplementation, bytes memory data) = abi.decode(msg.data[4:], (address, bytes));
        ERC1967Utils.upgradeToAndCall(newImplementation, data);
    }
}
