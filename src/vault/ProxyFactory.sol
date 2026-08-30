// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {Ownable2StepUpgradeable} from "@openzeppelin-contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {VaultTransparentProxy} from "./VaultTransparentProxy.sol";

/// @title ProxyFactory
/// @notice Deploys `VaultTransparentProxy` instances at predictable CREATE2 addresses.
/// @dev All proxies deployed by this factory share the same implementation and admin contracts,
///      which are set during initialization. The factory inherits from OpenZeppelin's
///      `Ownable2StepUpgradeable` so that only the owner may deploy proxies, with two-step
///      ownership transfers.
contract ProxyFactory is Initializable, Ownable2StepUpgradeable {
    /// @notice Thrown when the implementation address is not a contract.
    /// @param implementation The invalid implementation address.
    error ProxyFactoryInvalidImplementation(address implementation);

    /// @notice Thrown when the proxy admin address is not a contract.
    /// @param admin The invalid proxy admin address.
    error ProxyFactoryInvalidAdmin(address admin);

    /// @notice Thrown when a required address argument is the zero address.
    /// @param addr The zero address passed to the function.
    error ProxyFactoryZeroAddress(address addr);

    /// @notice Emitted whenever a new proxy contract is deployed.
    /// @param proxy The address of the deployed proxy contract.
    /// @param implementation The address of the implementation contract.
    /// @param proxyAdmin The address of the proxy admin contract.
    event ProxyDeployed(address indexed proxy, address indexed implementation, address indexed proxyAdmin);

    /// @notice The address of the vault implementation contract used by every deployed proxy.
    address public implementation;

    /// @notice The address of the proxy admin contract used by every deployed proxy.
    address public proxyAdmin;

    /// @notice Locks the implementation contract so it cannot be initialized directly.
    /// @dev The factory is designed to be deployed behind a proxy, so its standalone implementation
    ///      must never be initialized. This is the standard OZ upgradeable pattern.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the factory and transfers ownership to `initialOwner`.
    /// @dev Sets the shared implementation and proxy admin, and makes `initialOwner` the owner.
    /// @param initialOwner The address that will own the factory.
    /// @param implementation_ The address of the implementation contract.
    /// @param proxyAdmin_ The address of the proxy admin contract.
    /// @custom:reverts ProxyFactoryZeroAddress If `implementation_` or `proxyAdmin_` is the zero address.
    /// @custom:reverts ProxyFactoryInvalidImplementation If the implementation is not a contract.
    /// @custom:reverts ProxyFactoryInvalidAdmin If the proxy admin is not a contract.
    function initialize(address initialOwner, address implementation_, address proxyAdmin_) external initializer {
        if (implementation_ == address(0)) {
            revert ProxyFactoryZeroAddress(implementation_);
        }
        if (implementation_.code.length == 0) {
            revert ProxyFactoryInvalidImplementation(implementation_);
        }
        if (proxyAdmin_ == address(0)) {
            revert ProxyFactoryZeroAddress(proxyAdmin_);
        }
        if (proxyAdmin_.code.length == 0) {
            revert ProxyFactoryInvalidAdmin(proxyAdmin_);
        }
        __Ownable_init(initialOwner);
        __Ownable2Step_init();
        implementation = implementation_;
        proxyAdmin = proxyAdmin_;
    }

    /// @notice Deploys a new proxy contract at a predictable address derived from the salt.
    /// @dev Uses the CREATE2 opcode so the address can be precomputed. The salt must be unique
    ///      for each deployment, otherwise the deployment reverts. Only the owner may call.
    /// @param salt The CREATE2 salt, unique per deployment.
    /// @param data The encoded initialization call (e.g. the vault `initialize` calldata).
    /// @return proxy The address of the newly deployed proxy contract.
    function deployProxy(bytes32 salt, bytes calldata data) external onlyOwner returns (address proxy) {
        proxy = address(new VaultTransparentProxy{salt: salt}(implementation, proxyAdmin, data));
        emit ProxyDeployed(proxy, implementation, proxyAdmin);
    }

    /// @notice Computes the address a proxy would be deployed at for a given salt and data.
    /// @dev This must match the address produced by `deployProxy` for identical inputs.
    /// @param salt The CREATE2 salt.
    /// @param data The encoded initialization call.
    /// @return The predicted proxy address.
    function predictProxyAddress(bytes32 salt, bytes calldata data) external view returns (address) {
        bytes memory creationWithArgs =
            abi.encodePacked(type(VaultTransparentProxy).creationCode, abi.encode(implementation, proxyAdmin, data));
        // forge-lint: disable-next-line(asm-keccak256)
        bytes32 bytecodeHash = keccak256(creationWithArgs);
        return Create2.computeAddress(salt, bytecodeHash, address(this));
    }
}
