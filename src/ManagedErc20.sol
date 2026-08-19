// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.33;

import {ERC20Upgradeable} from "@openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

/// @title Represents an upgradeable ERC20 token that can be managed by a minter and a burner.
contract ManagedErc20 is ERC20Upgradeable {
    // ----------------------------------------------------------------------------
    // Errors
    // ----------------------------------------------------------------------------
    /// @notice Triggers when the number of token decimals is invalid
    error InvalidTokenDecimals();

    /// @notice Triggers if the sender is not the designed minter
    error InvalidMinter();

    /// @notice Triggers if the sender is not the designed burner
    error InvalidBurner();

    /// @notice Triggers if the smart contract is not initialized yet
    error TokenNotInitialized();

    /// @notice Triggers if the smart contract is not configured yet
    error TokenNotConfigured();

    /// @notice Triggers if a given address is not valid for the target account (minting or burning)
    error InvalidTargetAddress();

    /// @notice Triggers if the sender is not the deployer of the smart contract
    error InvalidDeployer();

    // ----------------------------------------------------------------------------
    // Storage layout
    // ----------------------------------------------------------------------------
    /// @notice The number of token decimals. Supported values are 6, 8 or 18.
    uint8 internal immutable _DECIMALS;

    /// @notice The deployer of the smart contract. This is the only account authorized to configure the token.
    address public immutable DEPLOYED_BY;

    /// @notice The minter. This is the only account authorized to mint tokens. It is usually a smart contract that implements a bridge or a vault.
    address public minter;

    /// @notice The burner. This is the only account authorized to burn tokens. It is usually a smart contract that implements a bridge or a vault.
    address public burner;


    // ----------------------------------------------------------------------------
    // Events
    // ----------------------------------------------------------------------------
    /// @notice Emitted when the token is configured with a new minter and burner.
    event TokenConfigured(address indexed minter, address indexed burner);

    /// @notice Emitted when the token is deployed with a name, symbol and decimals.
    event TokenDeployed(string name, string symbol, uint8 decimals);


    // ----------------------------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------------------------
    /**
     * @notice Initializes the token with the minimum required parameters for a cross-chain scenario.
     * @param newTokenName The descriptive name of the token.
     * @param newTokenSymbol The token symbol.
     * @param newDecimals The token decimals. Supported values are 6, 8 or 18.
     */
    constructor(
        string memory newTokenName, 
        string memory newTokenSymbol,
        uint8 newDecimals
    ) initializer {
        if (newDecimals != 6 && newDecimals != 8 && newDecimals != 18) revert InvalidTokenDecimals();

        __ERC20_init_unchained(newTokenName, newTokenSymbol);
        _DECIMALS = newDecimals;
        DEPLOYED_BY = _msgSender();

        emit TokenDeployed(newTokenName, newTokenSymbol, newDecimals);
    }

    // ----------------------------------------------------------------------------
    // Functions
    // ----------------------------------------------------------------------------
    /**
     * @notice Configures the token.
     * @dev The token can be configured after deployment, as long as you are the deployer. The minter and burner are allowed to be the same address.
     * @param newMinter The minter. This is the only account authorized to mint tokens. It is usually a smart contract that implements a bridge or a vault.
     * @param newBurner The burner. This is the only account authorized to burn tokens. It is usually a smart contract that implements a bridge or a vault.
     */
    function configure(
        address newMinter,
        address newBurner
    ) public {
        if (_DECIMALS < 1) revert TokenNotInitialized();
        if (DEPLOYED_BY != _msgSender()) revert InvalidDeployer();
        if (newMinter == address(0) || newMinter == address(1) || newMinter == address(this)) revert InvalidMinter();
        if (newBurner == address(0) || newBurner == address(1) || newBurner == address(this)) revert InvalidBurner();

        minter = newMinter;
        burner = newBurner;

        emit TokenConfigured(newMinter, newBurner);
    }

    /**
     * @notice Mints new tokens.
     * @dev Only the minter can call this function.
     * @param account The address of the account to mint tokens to.
     * @param value The amount of tokens to mint.
     */
    function mint(address account, uint256 value) external {
        _ensureTokenConfigured();
        if (minter != _msgSender()) revert InvalidMinter();
        if (account == address(0) || account == address(1) || account == address(this)) revert InvalidTargetAddress();

        _mint(account, value);
    }

    /**
     * @notice Burns existing tokens.
     * @dev Only the burner can call this function.
     * @param account The address of the account to burn tokens from.
     * @param value The amount of tokens to burn.
     */
    function burn(address account, uint256 value) external {
        _ensureTokenConfigured();
        if (burner != _msgSender()) revert InvalidBurner();
        if (account == address(0) || account == address(1) || account == address(this)) revert InvalidTargetAddress();

        _burn(account, value);
    }

    /**
     * @notice Gets the number of token decimals.
     * @return uint8 The number of token decimals.
     */
    function decimals() public view override returns (uint8) {
        return _DECIMALS;
    }

    /// @dev Ensures that the token is configured before allowing minting or burning.
    function _ensureTokenConfigured() internal view {
        if (minter == address(0)) revert TokenNotConfigured();
    }
}
