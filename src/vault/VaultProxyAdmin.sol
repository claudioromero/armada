// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {Ownable2StepUpgradeable} from "@openzeppelin-contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {IVaultTransparentProxy} from "./IVaultTransparentProxy.sol";

/// @title VaultProxyAdmin
/// @notice Upgradeable admin contract that manages upgrades for `VaultTransparentProxy` instances.
/// @dev Inherits from OpenZeppelin's `Ownable2StepUpgradeable`, so ownership is transferred in
///      two steps. Only the owner may upgrade proxies.
contract VaultProxyAdmin is Initializable, Ownable2StepUpgradeable {
    /// @notice Thrown when a provided address is not a deployed contract.
    /// @param target The address that is not a contract.
    error ProxyAdminNotAContract(address target);

    /// @notice Emitted when a proxy is upgraded to a new implementation.
    /// @param proxy The address of the upgraded proxy.
    /// @param implementation The address of the new implementation contract.
    event Upgraded(address indexed proxy, address indexed implementation);

    /// @notice Locks the implementation contract so it cannot be initialized directly.
    /// @dev The proxy admin is designed to be deployed behind a proxy, so its standalone
    ///      implementation must never be initialized. This is the standard OZ upgradeable pattern.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the proxy admin and transfers ownership to `initialOwner`.
    /// @dev Can only be called once due to the `initializer` guard.
    /// @param initialOwner The address that will own the proxy admin.
    function initialize(address initialOwner) external initializer {
        __Ownable_init(initialOwner);
        __Ownable2Step_init();
    }

    /// @notice Upgrades the implementation of a proxy contract.
    /// @dev Only the owner may call. Both the proxy and the new implementation must be contracts.
    /// @param proxy The address of the proxy to upgrade.
    /// @param newImplementation The address of the new implementation contract.
    /// @custom:reverts ProxyAdminNotAContract If either the proxy or the new implementation is not a contract.
    function upgrade(address proxy, address newImplementation) external onlyOwner {
        if (proxy.code.length == 0 || newImplementation.code.length == 0) {
            revert ProxyAdminNotAContract(newImplementation);
        }
        IVaultTransparentProxy(proxy).upgradeToAndCall(newImplementation, "");
        emit Upgraded(proxy, newImplementation);
    }

    /// @notice Returns the implementation contract address of a proxy.
    /// @param proxy The address of the proxy.
    /// @return The implementation contract address.
    /// @custom:reverts ProxyAdminNotAContract If the proxy is not a contract.
    function getProxyImplementation(address proxy) external view returns (address) {
        if (proxy.code.length == 0) {
            revert ProxyAdminNotAContract(proxy);
        }
        return IVaultTransparentProxy(proxy).implementation();
    }

    /// @notice Returns the admin address of a proxy.
    /// @param proxy The address of the proxy.
    /// @return The admin address.
    /// @custom:reverts ProxyAdminNotAContract If the proxy is not a contract.
    function getProxyAdmin(address proxy) external view returns (address) {
        if (proxy.code.length == 0) {
            revert ProxyAdminNotAContract(proxy);
        }
        return IVaultTransparentProxy(proxy).admin();
    }
}
