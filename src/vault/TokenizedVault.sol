// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {Ownable2StepUpgradeable} from "@openzeppelin-contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from "@openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20Metadata} from "@openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ERC4626Upgradeable} from "@openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {SafeERC20} from "@openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin-contracts/utils/math/Math.sol";
import {IPriceFeed} from "./IPriceFeed.sol";

/// @title TokenizedVault
/// @notice An upgradeable ERC-4626 tokenized vault that accepts a set of enabled tokens,
///         values them against an underlying asset using Chainlink price feeds, and issues
///         non-transferable receipt (share) tokens.
/// @dev Inherits from OpenZeppelin's `Ownable2StepUpgradeable`, `ERC20Upgradeable`,
///      `PausableUpgradeable` and `ReentrancyGuard`. Deployed behind a transparent upgradeable
///      proxy. All critical mutating functions are protected against reentrancy.
/// @dev Implements the standard ERC-4626 entry points, which operate on the underlying
///      asset: `deposit(uint256,address)`, `mint(uint256,address)`,
///      `withdraw(uint256,address,address)` and `redeem(uint256,address,address)`. Shares
///      are always minted to `receiver` and burned from `owner`, and the withdrawal timelock
///      is keyed on the share owner. An additional token-based `deposit(address,uint256)`
///      accepts any enabled token at its Chainlink-valued price. Receipt shares are
///      non-transferable; a third party may only withdraw or redeem a holder's shares with an
///      ERC-20 allowance.
/// @dev The vault can be paused by its owner; while paused, deposits, mints, withdrawals and
///      redemptions revert (`EnforcedPause`), and no receipt shares can be minted or burned
///      because the ERC-20 `_update` hook also enforces the pause. Admin configuration functions
///      remain available so the owner can manage the vault during an emergency.
/// @dev The project uses OpenZeppelin v5, in which the plain `ReentrancyGuard` is
///      stateless (its guard state lives at a fixed keccak256 slot rather than a
///      sequential storage variable) and is therefore upgradeable-proxy-safe. Because of this,
///      the separate `ReentrancyGuardUpgradeable` variant was removed in v5; the v5
///      `ReentrancyGuard` is the intended and correct choice for upgradeable contracts here.
///      Likewise `PausableUpgradeable` stores its state in an ERC-7201 slot, so pause state is
///      stable across upgrades.
contract TokenizedVault is
    Initializable,
    PausableUpgradeable,
    Ownable2StepUpgradeable,
    ERC4626Upgradeable,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @notice The maximum age of a price feed update before it is considered stale.
    uint256 public constant PRICE_FEED_HEARTBEAT = 1 days;

    /// @notice The denominator of the withdrawal fee, expressed in basis points (10_000 = 100%).
    uint256 public constant FEE_DENOMINATOR = 10_000;

    /// @notice Notional shares added to the share supply for share-price calculations.
    /// @dev The vault never mints these shares; they permanently floor the value of a single share
    ///      low enough that a direct token donation cannot push the share price above the value of
    ///      a small deposit (first-depositor inflation), and they guarantee an empty vault turns a
    ///      non-zero deposit into a non-zero number of shares. The offset keeps the conversion
    ///      curve exactly 1:1 in underlying terms, so `decimals()` is unchanged and share prices
    ///      stay readable.
    uint256 private constant VIRTUAL_SHARES = 10 ** 6;

    /// @notice Thrown when a token has a number of decimals other than 6, 8 or 18.
    /// @param decimals The unsupported number of decimals.
    error VaultUnsupportedDecimals(uint8 decimals);

    /// @notice Thrown when an operation references a token that is not enabled.
    /// @param token The address of the token that is not enabled.
    error VaultNotEnabled(address token);

    /// @notice Thrown when trying to enable a token that is already enabled.
    /// @param token The address of the token that is already enabled.
    error VaultAlreadyEnabled(address token);

    /// @notice Thrown when trying to enable the underlying asset as a deposit token.
    /// @dev The underlying is the vault's accounting and payout unit; it is not a depositable input.
    /// @param token The address of the underlying asset.
    error VaultCannotEnableUnderlying(address token);

    /// @notice Thrown when trying to disable the underlying asset.
    /// @dev The underlying is never an enabled token, so it cannot be disabled.
    /// @param token The address of the underlying asset.
    error VaultCannotDisableUnderlying(address token);

    /// @notice Thrown when a token is not a valid ERC-20 contract.
    /// @param token The address of the invalid token.
    error VaultInvalidERC20(address token);

    /// @notice Thrown when a price feed is invalid (zero address or non-positive answer).
    /// @param feed The address of the invalid price feed.
    error VaultInvalidPriceFeed(address feed);

    /// @notice Thrown when a price feed's data is stale.
    /// @param feed The address of the stale price feed.
    error VaultStalePriceFeed(address feed);

    /// @notice Thrown when a price feed's answer was not answered in its latest round.
    /// @param feed The address of the price feed with a round mismatch.
    error VaultInvalidPriceFeedRound(address feed);

    /// @notice Thrown when a deposit amount is zero.
    error VaultZeroAmount();

    /// @notice Thrown when a deposit amount is below the minimum deposit amount.
    /// @param minimumDepositAmount The minimum deposit amount in underlying-decimal units.
    error VaultBelowMinimumDeposit(uint256 minimumDepositAmount);

    /// @notice Thrown when a deposit would mint zero shares.
    /// @dev Prevents silent fund loss when rounding mints no shares.
    error VaultZeroShares();

    /// @notice Thrown when a withdrawal fee above the 100% denominator is set.
    error VaultInvalidFee();

    /// @notice Thrown when the withdrawal fee consumes the entire withdrawn amount.
    error VaultFeeExceedsAssets();

    /// @notice Thrown when the vault does not hold enough total assets to pay out.
    error VaultInsufficientUnderlying();

    /// @notice Thrown when trying to disable a token the vault still holds a balance of.
    /// @dev The vault prices and pays out redemptions pro-rata across every held asset, so a
    ///      token must be fully paid out before it can be dropped from the enabled set.
    /// @param token The address of the held token.
    error VaultNotSwept(address token);

    /// @notice Thrown when attempting to withdraw before the withdrawal timelock has expired.
    /// @param unlockTime The timestamp at which the withdrawal becomes available.
    error VaultTimelockNotExpired(uint256 unlockTime);

    /// @notice Thrown when attempting to transfer receipt (share) tokens, which are non-transferable.
    error VaultReceiptTokenNonTransferable();

    /// @notice Thrown when the vault receives Ether.
    error VaultEtherNotAccepted();

    /// @notice Thrown when a required address argument is the zero address.
    /// @param addr The zero address passed to the function.
    error VaultZeroAddress(address addr);

    /// @notice Stores the Chainlink price feed and token decimals for an enabled token.
    struct PriceFeed {
        /// @notice The address of the Chainlink price feed.
        address feed;
        /// @notice The number of decimals of the enabled token.
        uint8 decimals;
    }

    /// @notice Stores the deposit details of a depositor.
    struct DepositInfo {
        /// @notice The total value deposited by the user, denominated in the underlying asset.
        uint256 amount;
        /// @notice The timestamp of the user's most recent deposit.
        uint256 timestamp;
    }

    /// @notice Emitted when the vault is initialized.
    /// @param underlyingAsset The address of the underlying asset.
    event vaultInitialized(address indexed underlyingAsset);

    /// @notice Emitted when a token is enabled or disabled.
    /// @param token The address of the affected token.
    /// @param enabled Whether the token was enabled (true) or disabled (false).
    event TokenStatusChanged(address indexed token, bool enabled);

    /// @notice Emitted when the price feed of a token is updated.
    /// @param token The address of the token whose price feed was updated.
    /// @param newPriceFeed The address of the new Chainlink price feed.
    event PriceFeedUpdated(address indexed token, address indexed newPriceFeed);

    /// @notice Emitted when the withdrawal timelock is changed.
    /// @param newWithdrawalTimelock The new withdrawal timelock in seconds.
    event WithdrawalTimelockChanged(uint256 newWithdrawalTimelock);

    /// @notice Emitted when the minimum deposit amount is changed.
    /// @param newMinimumDepositAmount The new minimum deposit amount in underlying-decimal units.
    event MinimumDepositAmountChanged(uint256 newMinimumDepositAmount);

    /// @notice Emitted when the withdrawal fee is changed.
    /// @param newWithdrawalFee The new withdrawal fee in basis points.
    event WithdrawalFeeChanged(uint256 newWithdrawalFee);

    /// @notice Emitted when the fee collector is changed.
    /// @param newFeeCollector The address that receives withdrawal fees.
    event FeeCollectorChanged(address newFeeCollector);

    /// @notice The address of the underlying asset of the vault.
    address public underlyingAsset;

    /// @notice The number of decimals of the underlying asset.
    uint8 public underlyingDecimals;

    /// @notice The Chainlink price feed used to value the underlying asset in USD.
    address public underlyingPriceFeed;

    /// @notice The minimum time in seconds a user must wait before withdrawing after depositing.
    uint256 public withdrawalTimelock;

    /// @notice The minimum amount of underlying assets a user must deposit, in underlying-decimal units.
    uint256 public minimumDepositAmount;

    /// @notice The withdrawal fee charged on withdrawals, in basis points (e.g. 100 = 1%).
    uint256 public withdrawalFee;

    /// @notice The address that receives the withdrawal fee.
    address public feeCollector;

    /// @notice The list of enabled token addresses.
    address[] private _enabledTokens;

    /// @notice Whether a token is enabled (true) or disabled (false).
    /// @dev Returns true if the token is enabled and false otherwise.
    mapping(address => bool) public isTokenEnabled;

    /// @notice The price feed and decimals configuration for each enabled token.
    mapping(address => PriceFeed) public tokenPriceFeeds;

    /// @notice The deposit details (value and timestamp) for each share owner.
    /// @dev Keyed by the address that owns the receipt shares; the withdrawal timelock is
    ///      evaluated against this owner, so deposits for a third-party receiver are attributed
    ///      to the receiver.
    mapping(address => DepositInfo) public deposits;

    /// @notice Locks the implementation contract so it cannot be initialized directly.
    /// @dev The vault is designed to be deployed behind a transparent upgradeable proxy, so the
    ///      implementation contract itself must never be initialized or used in isolation. Calling
    ///      `_disableInitializers()` in the constructor prevents any future `initialize` call on a
    ///      stored (non-proxied) implementation. This is the standard OpenZeppelin upgradeable pattern.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the vault.
    /// @dev Sets the underlying asset, validates it is a valid ERC-20 with supported decimals,
    ///      configures the underlying price feed, sets the withdrawal timelock, minimum deposit
    ///      and withdrawal fee, defaults the fee collector to `initialOwner`, then transfers
    ///      ownership to `initialOwner`. Can only be called once due to the `initializer` guard.
    /// @param initialOwner The address that will own the vault.
    /// @param underlyingAsset_ The address of the underlying ERC-20 asset.
    /// @param sharesName The name of the receipt (share) token.
    /// @param sharesSymbol The symbol of the receipt (share) token.
    /// @param underlyingPriceFeed_ The Chainlink price feed for the underlying asset in USD.
    /// @param withdrawalTimelock_ The withdrawal timelock in seconds.
    /// @param minimumDepositAmount_ The minimum deposit amount in underlying-decimal units.
    /// @param withdrawalFee_ The withdrawal fee in basis points.
    /// @custom:reverts VaultZeroAddress If `initialOwner`, the underlying asset, or the price feed is the zero address.
    /// @custom:reverts VaultInvalidERC20 If the underlying asset is not a valid ERC-20.
    /// @custom:reverts VaultUnsupportedDecimals If the underlying asset does not have 6, 8 or 18 decimals.
    /// @custom:reverts VaultInvalidFee If `withdrawalFee_` exceeds the 100% denominator.
    function initialize(
        address initialOwner,
        address underlyingAsset_,
        string calldata sharesName,
        string calldata sharesSymbol,
        address underlyingPriceFeed_,
        uint256 withdrawalTimelock_,
        uint256 minimumDepositAmount_,
        uint256 withdrawalFee_
    ) external initializer {
        _requireNonZeroAddress(initialOwner);
        __Ownable_init(initialOwner);
        __Ownable2Step_init();
        __ERC20_init(sharesName, sharesSymbol);
        __Pausable_init();
        __ERC4626_init(IERC20(underlyingAsset_));
        _requireNonZeroAddress(underlyingAsset_);
        _requireNonZeroAddress(underlyingPriceFeed_);
        underlyingAsset = underlyingAsset_;
        _requireValidErc20(underlyingAsset_);
        underlyingDecimals = IERC20Metadata(underlyingAsset_).decimals();
        _validateDecimals(underlyingDecimals);
        underlyingPriceFeed = underlyingPriceFeed_;
        withdrawalTimelock = withdrawalTimelock_;
        minimumDepositAmount = minimumDepositAmount_;
        if (withdrawalFee_ > FEE_DENOMINATOR) {
            revert VaultInvalidFee();
        }
        withdrawalFee = withdrawalFee_;
        feeCollector = initialOwner;

        emit vaultInitialized(underlyingAsset_);
    }

    /// @notice Prevents the vault from receiving Ether with no calldata.
    /// @custom:reverts VaultEtherNotAccepted Always reverts.
    receive() external payable {
        revert VaultEtherNotAccepted();
    }

    /// @notice Prevents the vault from receiving Ether with unknown calldata.
    /// @custom:reverts VaultEtherNotAccepted Always reverts.
    fallback() external payable {
        revert VaultEtherNotAccepted();
    }

    /// @notice Validates that a token is a valid ERC-20 by calling its `totalSupply` function.
    /// @dev Catches any revert from the call and rethrows `VaultInvalidERC20`.
    /// @param token The address of the token to validate.
    /// @custom:reverts VaultInvalidERC20 If the `totalSupply` call fails.
    function _requireValidErc20(address token) internal view {
        try IERC20(token).totalSupply() returns (uint256) {}
        catch {
            revert VaultInvalidERC20(token);
        }
    }

    /// @notice Validates that a number of decimals is supported.
    /// @param decimals_ The number of decimals to validate.
    /// @custom:reverts VaultUnsupportedDecimals If the decimals are not 6, 8 or 18.
    function _validateDecimals(uint8 decimals_) internal pure {
        if (decimals_ != 6 && decimals_ != 8 && decimals_ != 18) {
            revert VaultUnsupportedDecimals(decimals_);
        }
    }

    /// @notice Reverts if the provided address is the zero address.
    /// @param addr The address to validate.
    /// @custom:reverts VaultZeroAddress If `addr` is the zero address.
    function _requireNonZeroAddress(address addr) internal pure {
        if (addr == address(0)) {
            revert VaultZeroAddress(addr);
        }
    }

    /// @notice Returns the number of decimals of the receipt token.
    /// @dev Matches the decimals of the underlying asset.
    /// @return The number of decimals.
    function decimals() public view virtual override(ERC4626Upgradeable) returns (uint8) {
        return underlyingDecimals;
    }

    /// @notice Returns the address of the underlying asset.
    /// @return The underlying asset address.
    function asset() public view override returns (address) {
        return underlyingAsset;
    }

    /// @notice Returns the total value of assets held by the vault, denominated in the underlying asset.
    /// @dev Summarises the vault's balance of the underlying asset plus the value of every
    ///      enabled token it holds, converted using the Chainlink price feeds.
    /// @return The total assets in underlying-decimal units.
    /// @custom:reverts VaultNotEnabled If an enabled token was disabled while still held.
    function totalAssets() public view virtual override returns (uint256) {
        uint256 total = IERC20(underlyingAsset).balanceOf(address(this));
        uint256 len = _enabledTokens.length;
        if (len > 0) {
            uint256 pu = _priceUsd(underlyingPriceFeed);
            for (uint256 i = 0; i < len; i++) {
                address token = _enabledTokens[i];
                if (token != underlyingAsset) {
                    total += _tokenToUnderlying(IERC20(token).balanceOf(address(this)), token, pu);
                }
            }
        }
        return total;
    }

    /// @notice Returns the maximum amount of underlying assets that `owner` can withdraw.
    /// @dev Returns zero if the withdrawal timelock of `owner` has not elapsed or if the
    ///      withdrawal fee would consume the entire balance. Otherwise the value of the owner's
    ///      shares converted to underlying assets. Depends only on `owner`, never on the caller.
    /// @param owner The address of the share owner.
    /// @return The maximum amount of assets.
    function maxWithdraw(address owner) public view virtual override returns (uint256) {
        if (_withdrawalLocked(owner)) {
            return 0;
        }
        uint256 gross = convertToAssets(balanceOf(owner));
        if (_computeWithdrawalFee(gross) >= gross) {
            return 0;
        }
        return gross;
    }

    /// @notice Returns the maximum amount of shares that `owner` can redeem.
    /// @dev Returns zero if the withdrawal timelock has not elapsed or if the withdrawal fee
    ///      would consume the owner's entire balance, otherwise the owner's balance.
    /// @param owner The address of the share owner.
    /// @return The maximum amount of shares.
    function maxRedeem(address owner) public view virtual override returns (uint256) {
        if (_withdrawalLocked(owner)) {
            return 0;
        }
        uint256 gross = convertToAssets(balanceOf(owner));
        if (_computeWithdrawalFee(gross) >= gross) {
            return 0;
        }
        return balanceOf(owner);
    }

    /// @notice Returns the amount of shares that would be burned for a given withdrawal of assets.
    /// @dev Returns zero if the withdrawal timelock of `msg.sender` has not elapsed. Reverts if
    ///      the withdrawal fee would consume the entire requested `assets` amount, mirroring
    ///      `withdraw`.
    /// @param assets The gross amount of assets requested in underlying-decimal units.
    /// @return The amount of shares.
    /// @custom:reverts VaultFeeExceedsAssets If the withdrawal fee consumes the entire amount.
    function previewWithdraw(uint256 assets) public view virtual override returns (uint256) {
        if (_withdrawalLocked(msg.sender)) {
            return 0;
        }
        if (_computeWithdrawalFee(assets) >= assets) {
            revert VaultFeeExceedsAssets();
        }
        return _convertToShares(assets, Math.Rounding.Ceil);
    }

    /// @notice Returns the net amount of assets a given amount of shares would redeem.
    /// @dev Returns zero if the withdrawal timelock of `msg.sender` has not elapsed. Returns the
    ///      payout after deducting the withdrawal fee, mirroring `redeem`. Reverts if the fee
    ///      would consume the shares' entire value.
    /// @param shares The amount of shares.
    /// @return The net assets in underlying-decimal units.
    /// @custom:reverts VaultFeeExceedsAssets If the withdrawal fee consumes the entire value.
    function previewRedeem(uint256 shares) public view virtual override returns (uint256) {
        if (_withdrawalLocked(msg.sender)) {
            return 0;
        }
        uint256 gross = _convertToAssets(shares, Math.Rounding.Floor);
        uint256 fee = _computeWithdrawalFee(gross);
        if (fee >= gross) {
            revert VaultFeeExceedsAssets();
        }
        return gross - fee;
    }

    /// @notice Deposits the underlying asset or an enabled token and mints receipt shares to `receiver`.
    /// @dev The deposited token is transferred to the vault and valued in underlying assets. The
    ///      underlying asset is accepted at identity value (1 = 1, no price feed) and never needs
    ///      to be enabled; any other token must be enabled and is valued through its price feed.
    ///      This is a convenience variant of the standard `deposit(uint256,address)` that accepts
    ///      any enabled token rather than only the underlying asset. Reentrancy protected.
    /// @param token The address of the token to deposit (the underlying or an enabled token).
    /// @param amount The amount of the token to deposit.
    /// @param receiver The address that receives the minted shares.
    /// @return shares The amount of shares minted to `receiver`.
    /// @custom:reverts VaultZeroAddress If `token` or `receiver` is the zero address.
    /// @custom:reverts VaultNotEnabled If the token is neither the underlying nor enabled.
    /// @custom:reverts VaultZeroAmount If `amount` is zero.
    /// @custom:reverts VaultZeroShares If the deposit would mint zero shares.
    /// @custom:reverts VaultBelowMinimumDeposit If the deposit value is below the minimum deposit amount.
    /// @custom:reverts VaultInvalidPriceFeed If a price feed is invalid.
    /// @custom:reverts VaultStalePriceFeed If a price feed is stale.
    function deposit(address token, uint256 amount, address receiver) external nonReentrant returns (uint256 shares) {
        _requireNonZeroAddress(token);
        _requireNonZeroAddress(receiver);
        return _depositToken(token, amount, receiver);
    }

    /// @notice Standard ERC-4626 deposit of the underlying asset for `receiver`.
    /// @dev Overrides `ERC4626Upgradeable` to enforce the reentrancy guard, the pause, the
    ///      zero-value guards and the withdrawal timelock recording on `receiver`.
    /// @param assets The amount of the underlying asset to deposit.
    /// @param receiver The address that receives the minted shares.
    /// @return shares The amount of shares minted to `receiver`.
    /// @custom:reverts VaultZeroAddress If `receiver` is the zero address.
    /// @custom:reverts VaultZeroAmount If `assets` is zero.
    /// @custom:reverts VaultZeroShares If the deposit would mint zero shares.
    /// @custom:reverts VaultBelowMinimumDeposit If the deposit value is below the minimum deposit amount.
    function deposit(uint256 assets, address receiver) public override nonReentrant returns (uint256 shares) {
        _requireNonZeroAddress(receiver);
        return _depositToken(underlyingAsset, assets, receiver);
    }

    /// @notice Shared deposit helper for the token-based and standard ERC-4626 entry points.
    /// @param token The address of the token to deposit (the underlying or an enabled token).
    /// @param amount The amount of the token to deposit.
    /// @param receiver The address that receives the minted shares.
    /// @return shares The amount of shares minted to `receiver`.
    /// @custom:reverts VaultNotEnabled If the token is neither the underlying nor enabled.
    /// @custom:reverts VaultZeroAmount If `amount` is zero.
    /// @custom:reverts VaultZeroShares If the deposit would mint zero shares.
    /// @custom:reverts VaultInvalidPriceFeed If a price feed is invalid.
    /// @custom:reverts VaultStalePriceFeed If a price feed is stale.
    function _depositToken(address token, uint256 amount, address receiver) internal returns (uint256 shares) {
        _requireNotPaused();
        bool isUnderlying = token == underlyingAsset;
        if (!isUnderlying && !isTokenEnabled[token]) {
            revert VaultNotEnabled(token);
        }
        if (amount == 0) {
            revert VaultZeroAmount();
        }
        uint256 assets = isUnderlying ? amount : _tokenToUnderlying(amount, token, _priceUsd(underlyingPriceFeed));
        if (assets < minimumDepositAmount) {
            revert VaultBelowMinimumDeposit(minimumDepositAmount);
        }
        shares = previewDeposit(assets);
        if (shares == 0) {
            revert VaultZeroShares();
        }

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        _mint(receiver, shares);
        _recordDeposit(receiver, assets);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /// @notice Records deposit value and timestamp for a share owner.
    /// @dev Starts the withdrawal timelock on the receiver's first-ever funded deposit. A later
    ///      deposit restarts the lock only when `msg.sender` is the receiver themself and the
    ///      current lock has already expired, so the account's own growth is always protected by a
    ///      fresh cooling period. Third-party donations never start, extend or restart the
    ///      receiver's lock, preventing a griefer from indefinitely re-locking a victim's balance
    ///      with dust deposits.
    /// @param receiver The address of the share owner.
    /// @param assets The value of the deposit in underlying-decimal units.
    function _recordDeposit(address receiver, uint256 assets) internal {
        uint256 currentAmount = deposits[receiver].amount;
        deposits[receiver].amount = currentAmount + assets;
        if (currentAmount == 0 || (msg.sender == receiver && !_withdrawalLocked(receiver))) {
            deposits[receiver].timestamp = block.timestamp;
        }
    }

    /// @notice Standard ERC-4626 mint of `shares` for `receiver`.
    /// @dev Overrides `ERC4626Upgradeable` to enforce the reentrancy guard, the pause, the
    ///      zero-shares guard and the withdrawal timelock recording on `receiver`.
    /// @param shares The amount of shares to mint.
    /// @param receiver The address that receives the minted shares.
    /// @return assets The amount of the underlying asset transferred from `msg.sender`.
    /// @custom:reverts VaultZeroAddress If `receiver` is the zero address.
    /// @custom:reverts VaultZeroShares If `shares` is zero.
    /// @custom:reverts VaultBelowMinimumDeposit If the deposit value is below the minimum deposit amount.
    function mint(uint256 shares, address receiver) public override nonReentrant returns (uint256 assets) {
        _requireNonZeroAddress(receiver);
        _requireNotPaused();
        // Minting zero shares would only set the receiver's deposit timestamp, allowing griefing
        // of the withdrawal timelock without adding value, so it is rejected.
        if (shares == 0) {
            revert VaultZeroShares();
        }
        assets = previewMint(shares);
        if (assets < minimumDepositAmount) {
            revert VaultBelowMinimumDeposit(minimumDepositAmount);
        }

        IERC20(underlyingAsset).safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);
        _recordDeposit(receiver, assets);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /// @notice Standard ERC-4626 redeem of `owner`'s shares for a pro-rata slice of held assets.
    /// @dev Burns `shares` from `owner` and pays out a pro-rata basket of the underlying and
    ///      enabled-token holdings to `receiver`, so a vault that holds mostly enabled tokens
    ///      stays liquid. The withdrawal timelock is checked against `owner`. If
    ///      `msg.sender != owner`, an ERC-20 allowance from `owner` is required and spent.
    ///      Reentrancy protected.
    /// @param shares The amount of shares to redeem.
    /// @param receiver The address that receives the paid-out assets.
    /// @param owner The address whose shares are burned.
    /// @return assets The value of the assets paid out, in underlying-decimal units.
    /// @custom:reverts VaultZeroAddress If `receiver` is the zero address.
    /// @custom:reverts VaultTimelockNotExpired If the withdrawal timelock has not elapsed.
    /// @custom:reverts VaultInsufficientUnderlying If the vault does not hold enough total assets.
    /// @custom:reverts VaultFeeExceedsAssets If the withdrawal fee consumes the entire withdrawn amount.
    /// @custom:reverts ERC20InsufficientAllowance If `msg.sender != owner` and lacks allowance.
    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256 assets)
    {
        return _redeem(shares, receiver, owner);
    }

    /// @notice Shared redeem helper for the wrapper and standard ERC-4626 entry points.
    /// @dev Burns `shares` for their full underlying value; the withdrawal fee is deducted
    ///      from the basket paid to `receiver` and the retained remainder is forwarded to the
    ///      `feeCollector` as the same pro-rata basket.
    /// @param shares The amount of shares to burn.
    /// @param receiver The address that receives the paid-out assets.
    /// @param owner The address whose shares are burned.
    /// @return amountOut The value of the assets paid out after the withdrawal fee, in
    ///      underlying-decimal units.
    function _redeem(uint256 shares, address receiver, address owner) internal returns (uint256 amountOut) {
        _requireNotPaused();
        _requireNonZeroAddress(receiver);
        _checkWithdrawalTimelock(owner);
        uint256 assets = _convertToAssets(shares, Math.Rounding.Floor);
        uint256 fee = _computeWithdrawalFee(assets);
        if (fee >= assets) {
            revert VaultFeeExceedsAssets();
        }
        amountOut = assets - fee;
        _spendAllowanceIfNotOwner(owner, shares);

        _burn(owner, shares);
        _payBasket(receiver, assets, amountOut);

        emit Withdraw(msg.sender, receiver, owner, amountOut, shares);
        return amountOut;
    }

    /// @notice Standard ERC-4626 withdraw of `assets` for `receiver`, burning `owner`'s shares.
    /// @dev Overrides `ERC4626Upgradeable` to enforce the reentrancy guard, the pause, the
    ///      total-assets liquidity check and the `owner`-scoped withdrawal timelock. Pays out
    ///      a pro-rata basket of the vault's held assets.
    /// @param assets The amount of value to withdraw, in underlying-decimal units.
    /// @param receiver The address that receives the paid-out assets.
    /// @param owner The address whose shares are burned.
    /// @return shares The amount of shares burned.
    /// @custom:reverts VaultZeroAddress If `receiver` is the zero address.
    /// @custom:reverts VaultTimelockNotExpired If the withdrawal timelock has not elapsed.
    /// @custom:reverts VaultInsufficientUnderlying If the vault does not hold enough total assets.
    /// @custom:reverts VaultFeeExceedsAssets If the withdrawal fee consumes the entire withdrawn amount.
    /// @custom:reverts ERC20InsufficientAllowance If `msg.sender != owner` and lacks allowance.
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256 shares)
    {
        return _withdrawAssets(assets, receiver, owner);
    }

    /// @notice Shared withdraw helper for the wrapper and standard ERC-4626 entry points.
    /// @dev Burns `shares` for the full requested `assets` value; the withdrawal fee is deducted
    ///      from the basket paid to `receiver` and the retained remainder is forwarded to the
    ///      `feeCollector` as the same pro-rata basket.
    /// @param assets The amount of value to withdraw, in underlying-decimal units.
    /// @param receiver The address that receives the paid-out assets.
    /// @param owner The address whose shares are burned.
    /// @return shares The amount of shares burned.
    function _withdrawAssets(uint256 assets, address receiver, address owner) internal returns (uint256 shares) {
        _requireNotPaused();
        _requireNonZeroAddress(receiver);
        _checkWithdrawalTimelock(owner);
        shares = _convertToShares(assets, Math.Rounding.Ceil);
        uint256 fee = _computeWithdrawalFee(assets);
        if (fee >= assets) {
            revert VaultFeeExceedsAssets();
        }
        uint256 amountOut = assets - fee;
        _spendAllowanceIfNotOwner(owner, shares);

        _burn(owner, shares);
        _payBasket(receiver, assets, amountOut);

        emit Withdraw(msg.sender, receiver, owner, amountOut, shares);
    }

    /// @notice Spends `owner`'s ERC-20 allowance when a third party burns their shares.
    /// @param owner The address of the share owner.
    /// @param shares The amount of shares to spend.
    function _spendAllowanceIfNotOwner(address owner, uint256 shares) internal {
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
    }

    /// @notice Reverts if the caller's withdrawal timelock has not elapsed.
    /// @param owner The address of the share owner.
    /// @custom:reverts VaultTimelockNotExpired If the timelock has not elapsed.
    function _checkWithdrawalTimelock(address owner) internal view {
        if (_withdrawalLocked(owner)) {
            revert VaultTimelockNotExpired(deposits[owner].timestamp + withdrawalTimelock);
        }
    }

    /// @notice Returns whether the caller's withdrawal is still locked by the timelock.
    /// @dev If the timelock is zero, withdrawals are never locked.
    /// @param owner The address of the share owner.
    /// @return True if the withdrawal is locked, false otherwise.
    function _withdrawalLocked(address owner) internal view returns (bool) {
        if (withdrawalTimelock == 0) {
            return false;
        }
        uint256 unlockTime = deposits[owner].timestamp + withdrawalTimelock;
        return block.timestamp < unlockTime;
    }

    /// @notice Computes the withdrawal fee for a gross amount in underlying-decimal units.
    /// @dev Rounding up the fee favors the vault and prevents dust-free withdrawals.
    /// @param amount The gross amount being withdrawn in underlying-decimal units.
    /// @return The fee in underlying-decimal units.
    function _computeWithdrawalFee(uint256 amount) internal view returns (uint256) {
        return amount.mulDiv(withdrawalFee, FEE_DENOMINATOR, Math.Rounding.Ceil);
    }

    /// @notice Converts underlying assets to `shares` using the virtual-share offset.
    /// @dev Overrides `ERC4626Upgradeable` to add `VIRTUAL_SHARES` to the share supply so an
    ///      empty vault still prices shares defensively against first-depositor inflation.
    /// @param assets The amount of underlying assets to convert.
    /// @param rounding The rounding direction.
    /// @return shares The number of shares equivalent to `assets`.
    function _convertToShares(uint256 assets, Math.Rounding rounding)
        internal
        view
        virtual
        override
        returns (uint256 shares)
    {
        return assets.mulDiv(totalSupply() + VIRTUAL_SHARES, totalAssets() + 1, rounding);
    }

    /// @notice Converts `shares` to underlying assets using the virtual-share offset.
    /// @dev Overrides `ERC4626Upgradeable` to mirror `_convertToShares`.
    /// @param shares The number of shares to convert.
    /// @param rounding The rounding direction.
    /// @return assets The amount of underlying assets equivalent to `shares`.
    function _convertToAssets(uint256 shares, Math.Rounding rounding)
        internal
        view
        virtual
        override
        returns (uint256 assets)
    {
        return shares.mulDiv(totalAssets() + 1, totalSupply() + VIRTUAL_SHARES, rounding);
    }

    /// @notice Pays out a pro-rata basket of the vault's held assets for a withdrawal.
    /// @dev Each held asset (the underlying plus every enabled token) contributes its share of
    ///      `gross` proportionally to its share of `totalAssets()`. The receiver gets `amountOut`
    ///      worth of that basket, floored in the vault's favor; the remainder (the withdrawal
    ///      fee) is forwarded to the fee collector as the same basket. Reverts when the vault
    ///      values less than `gross`, which can only happen if the requested value exceeds the
    ///      total assets.
    /// @param receiver The address that receives the paid-out assets.
    /// @param gross The gross value being withdrawn, in underlying-decimal units.
    /// @param amountOut The post-fee value paid to `receiver`, in underlying-decimal units.
    /// @custom:reverts VaultInsufficientUnderlying If the vault's total assets are below `gross`.
    function _payBasket(address receiver, uint256 gross, uint256 amountOut) internal {
        uint256 total = totalAssets();
        if (gross > total) {
            revert VaultInsufficientUnderlying();
        }
        if (total == 0) {
            return;
        }

        uint256 underlyingUnitsForGross =
            IERC20(underlyingAsset).balanceOf(address(this)).mulDiv(gross, total, Math.Rounding.Floor);
        if (underlyingUnitsForGross > 0) {
            uint256 underlyingOut = underlyingUnitsForGross.mulDiv(amountOut, gross, Math.Rounding.Floor);
            if (underlyingOut > 0) {
                IERC20(underlyingAsset).safeTransfer(receiver, underlyingOut);
            }
            _tryCollectFee(underlyingAsset, underlyingUnitsForGross - underlyingOut);
        }

        uint256 len = _enabledTokens.length;
        for (uint256 i = 0; i < len; i++) {
            address token = _enabledTokens[i];
            if (token == underlyingAsset) {
                continue;
            }
            uint256 tokenUnitsForGross =
                IERC20(token).balanceOf(address(this)).mulDiv(gross, total, Math.Rounding.Floor);
            if (tokenUnitsForGross == 0) {
                continue;
            }
            uint256 tokenOut = tokenUnitsForGross.mulDiv(amountOut, gross, Math.Rounding.Floor);
            if (tokenOut > 0) {
                IERC20(token).safeTransfer(receiver, tokenOut);
            }
            _tryCollectFee(token, tokenUnitsForGross - tokenOut);
        }
    }

    /// @notice Forwards a non-zero fee share to the fee collector.
    /// @dev The fee remainder is kept in the vault if the collector cannot currently receive the
    ///      asset (for example it is blacklisted by a blocklisting token or rejects transfers);
    ///      the withdrawal still succeeds. A retained remainder stays part of `totalAssets` and
    ///      accrues to shareholders; collection resumes once a collector that can receive the
    ///      asset is set.
    /// @param token The asset whose fee remainder is being collected.
    /// @param amount The fee remainder in the asset's native decimals.
    function _tryCollectFee(address token, uint256 amount) internal {
        if (amount > 0) {
            try IERC20(token).transfer(feeCollector, amount) {} catch {}
        }
    }

    /// @notice Converts an amount of an enabled token to its value in the underlying asset.
    /// @dev Takes the pre-computed underlying price to avoid re-reading the feed per token.
    /// @param amount The amount of the token in its native decimals.
    /// @param token The address of the enabled token.
    /// @param pu The underlying asset's 18-decimal USD price.
    /// @return The value of the amount in underlying-decimal units.
    function _tokenToUnderlying(uint256 amount, address token, uint256 pu) internal view returns (uint256) {
        uint256 tokenValue = _tokenValueInUnderlying(token, pu);
        uint256 tDecimals = tokenPriceFeeds[token].decimals;
        return amount * tokenValue * (10 ** underlyingDecimals) / (10 ** tDecimals) / 1e18;
    }

    /// @notice Returns the value of one unit of an enabled token in terms of the underlying asset.
    /// @dev Computed as the ratio of the token's USD price to the underlying asset's USD price,
    ///      scaled to 18 decimals.
    /// @param token The address of the enabled token.
    /// @return The token value in 18-decimal units.
    /// @custom:reverts VaultNotEnabled If the token is not enabled.
    /// @custom:reverts VaultInvalidPriceFeed If a price feed is invalid.
    /// @custom:reverts VaultInvalidPriceFeedRound If a feed's answer was not from its latest round.
    /// @custom:reverts VaultStalePriceFeed If a price feed is stale.
    function getTokenValue(address token) public view returns (uint256) {
        if (!isTokenEnabled[token]) {
            revert VaultNotEnabled(token);
        }
        return _tokenValueInUnderlying(token, _priceUsd(underlyingPriceFeed));
    }

    /// @notice Returns the value of one unit of an enabled token in terms of the underlying asset,
    ///      using a pre-computed underlying price.
    /// @dev Computed as the ratio of the token's USD price to the underlying asset's USD price,
    ///      scaled to 18 decimals.
    /// @param token The address of the enabled token.
    /// @param pu The underlying asset's 18-decimal USD price.
    /// @return The token value in 18-decimal units.
    /// @custom:reverts VaultNotEnabled If the token is not enabled.
    /// @custom:reverts VaultInvalidPriceFeed If the token's price feed is invalid.
    /// @custom:reverts VaultInvalidPriceFeedRound If the feed's answer was not from its latest round.
    /// @custom:reverts VaultStalePriceFeed If the feed's data is stale.
    function _tokenValueInUnderlying(address token, uint256 pu) internal view returns (uint256) {
        uint256 px = _priceUsd(tokenPriceFeeds[token].feed);
        return px * (10 ** 18) / pu;
    }

    /// @notice Returns the price of a feed normalized to 18 decimals in USD.
    /// @dev Reverts if the feed is a zero address, has a non-positive answer, was not answered in
    ///      its latest round, or is stale.
    /// @param feed The address of the Chainlink price feed.
    /// @return The normalized 18-decimal USD price.
    /// @custom:reverts VaultInvalidPriceFeed If the feed is zero address or answer is non-positive.
    /// @custom:reverts VaultInvalidPriceFeedRound If the answer was not produced by the latest round.
    /// @custom:reverts VaultStalePriceFeed If the feed's data is older than the heartbeat.
    function _priceUsd(address feed) internal view returns (uint256) {
        if (feed == address(0)) {
            revert VaultInvalidPriceFeed(feed);
        }
        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) = IPriceFeed(feed).latestRoundData();
        if (answer <= 0) {
            revert VaultInvalidPriceFeed(feed);
        }
        if (answeredInRound < roundId) {
            revert VaultInvalidPriceFeedRound(feed);
        }
        if (updatedAt == 0 || block.timestamp - updatedAt > PRICE_FEED_HEARTBEAT) {
            revert VaultStalePriceFeed(feed);
        }
        uint8 feedDecimals = IPriceFeed(feed).decimals();
        // casting to 'uint256' is safe because answer is positive int256
        // forge-lint: disable-next-line(unsafe-typecast)
        return (uint256(answer) * (10 ** 18)) / (10 ** feedDecimals);
    }

    /// @notice Enables a token for deposits.
    /// @dev Only the owner may call. Validates the token is a valid ERC-20 with supported
    ///      decimals and a valid price feed, then adds it to the enabled set. Reentrancy
    ///      protected. The underlying asset itself cannot be enabled.
    /// @param tokenAddr The address of the token to enable.
    /// @param priceFeedAddr The address of the Chainlink price feed for the token in USD.
    /// @param decimals_ The number of decimals of the token.
    /// @custom:reverts VaultZeroAddress If `tokenAddr` or `priceFeedAddr` is the zero address.
    /// @custom:reverts VaultCannotEnableUnderlying If `tokenAddr` is the underlying asset.
    /// @custom:reverts VaultAlreadyEnabled If the token is already enabled.
    /// @custom:reverts VaultUnsupportedDecimals If the token decimals are not 6, 8 or 18.
    /// @custom:reverts VaultInvalidERC20 If the token is not a valid ERC-20.
    /// @custom:reverts VaultInvalidPriceFeed If the price feed address is zero.
    function enableToken(address tokenAddr, address priceFeedAddr, uint8 decimals_) external nonReentrant onlyOwner {
        _requireNonZeroAddress(tokenAddr);
        if (tokenAddr == underlyingAsset) {
            revert VaultCannotEnableUnderlying(tokenAddr);
        }
        if (isTokenEnabled[tokenAddr]) {
            revert VaultAlreadyEnabled(tokenAddr);
        }
        _validateDecimals(decimals_);
        _requireValidErc20(tokenAddr);
        if (priceFeedAddr == address(0)) {
            revert VaultInvalidPriceFeed(priceFeedAddr);
        }
        isTokenEnabled[tokenAddr] = true;
        tokenPriceFeeds[tokenAddr] = PriceFeed({feed: priceFeedAddr, decimals: decimals_});
        _enabledTokens.push(tokenAddr);

        emit TokenStatusChanged(tokenAddr, true);
    }

    /// @notice Disables a token, removing it from the enabled set.
    /// @dev Only the owner may call. The vault is disallowed from disabling a token it still
    ///      holds a balance of, because redemptions pay out pro-rata across every held asset;
    ///      the owner must first allow the balance to be paid out to withdrawers. The underlying
    ///      asset cannot be disabled since it is never an enabled token.
    /// @param tokenAddr The address of the token to disable.
    /// @custom:reverts VaultZeroAddress If `tokenAddr` is the zero address.
    /// @custom:reverts VaultCannotDisableUnderlying If `tokenAddr` is the underlying asset.
    /// @custom:reverts VaultNotEnabled If the token is not enabled.
    /// @custom:reverts VaultNotSwept If the vault still holds a balance of the token.
    function disableToken(address tokenAddr) external nonReentrant onlyOwner {
        _requireNonZeroAddress(tokenAddr);
        if (tokenAddr == underlyingAsset) {
            revert VaultCannotDisableUnderlying(tokenAddr);
        }
        if (!isTokenEnabled[tokenAddr]) {
            revert VaultNotEnabled(tokenAddr);
        }
        if (IERC20(tokenAddr).balanceOf(address(this)) > 0) {
            revert VaultNotSwept(tokenAddr);
        }
        isTokenEnabled[tokenAddr] = false;
        delete tokenPriceFeeds[tokenAddr];
        uint256 len = _enabledTokens.length;
        for (uint256 i = 0; i < len; i++) {
            if (_enabledTokens[i] == tokenAddr) {
                _enabledTokens[i] = _enabledTokens[len - 1];
                _enabledTokens.pop();
                break;
            }
        }

        emit TokenStatusChanged(tokenAddr, false);
    }

    /// @notice Updates the price feed used to value a token.
    /// @dev Only the owner may call. The token can be the underlying asset or any enabled token.
    ///      The new feed must be a live Chainlink feed; its data is validated up front so a
    ///      broken or stale feed cannot be configured. The feed-to-token association itself
    ///      cannot be verified on-chain and is the owner's responsibility.
    /// @param tokenAddr The address of the token whose price feed is updated.
    /// @param newPriceFeedAddr The address of the new Chainlink USD price feed.
    /// @custom:reverts VaultInvalidPriceFeed If the new feed is a zero address or not a contract.
    /// @custom:reverts VaultInvalidPriceFeedRound If the new feed's answer was not produced by its latest round.
    /// @custom:reverts VaultStalePriceFeed If the new feed's data is stale.
    /// @custom:reverts VaultNotEnabled If `tokenAddr` is neither the underlying asset nor an enabled token.
    function updateTokenPriceFeed(address tokenAddr, address newPriceFeedAddr) external nonReentrant onlyOwner {
        if (newPriceFeedAddr == address(0) || newPriceFeedAddr.code.length == 0) {
            revert VaultInvalidPriceFeed(newPriceFeedAddr);
        }
        // Validate the new feed before mutating state so a broken feed cannot be configured.
        _priceUsd(newPriceFeedAddr);
        if (tokenAddr == underlyingAsset) {
            underlyingPriceFeed = newPriceFeedAddr;
        } else {
            if (!isTokenEnabled[tokenAddr]) {
                revert VaultNotEnabled(tokenAddr);
            }
            tokenPriceFeeds[tokenAddr].feed = newPriceFeedAddr;
        }

        emit PriceFeedUpdated(tokenAddr, newPriceFeedAddr);
    }

    /// @notice Returns the array of all enabled token addresses.
    /// @return The enabled token addresses.
    function getEnabledTokens() public view returns (address[] memory) {
        return _enabledTokens;
    }

    /// @notice Sets the withdrawal timelock duration.
    /// @dev Only the owner may call. A value of zero allows immediate withdrawals.
    /// @param newWithdrawalTimelock The new timelock duration in seconds.
    function setWithdrawalTimelock(uint256 newWithdrawalTimelock) external onlyOwner {
        withdrawalTimelock = newWithdrawalTimelock;
        emit WithdrawalTimelockChanged(newWithdrawalTimelock);
    }

    /// @notice Sets the minimum deposit amount.
    /// @dev Only the owner may call. A value of zero imposes no minimum. The amount is denominated
    ///      in underlying-asset units.
    /// @param newMinimumDepositAmount The new minimum deposit amount in underlying-decimal units.
    function setMinimumDepositAmount(uint256 newMinimumDepositAmount) external onlyOwner {
        minimumDepositAmount = newMinimumDepositAmount;
        emit MinimumDepositAmountChanged(newMinimumDepositAmount);
    }

    /// @notice Sets the withdrawal fee.
    /// @dev Only the owner may call. The fee is expressed in basis points (e.g. 100 = 1%) and is
    ///      deducted from the amount paid to the receiver on every withdraw and redeem, then
    ///      transferred to the `feeCollector`. A value of zero charges no fee.
    /// @param newWithdrawalFee The new withdrawal fee in basis points.
    /// @custom:reverts VaultInvalidFee If the fee exceeds the 100% denominator.
    /// @custom:reverts OwnableUnauthorizedAccount If called by a non-owner.
    function setWithdrawalFee(uint256 newWithdrawalFee) external onlyOwner {
        if (newWithdrawalFee > FEE_DENOMINATOR) {
            revert VaultInvalidFee();
        }
        withdrawalFee = newWithdrawalFee;
        emit WithdrawalFeeChanged(newWithdrawalFee);
    }

    /// @notice Sets the address that receives the withdrawal fee.
    /// @dev Only the owner may call. On every withdraw and redeem, the accrued fee is sent to
    ///      this address. The collector defaults to the owner at initialization.
    /// @param newFeeCollector The address that receives the withdrawal fee.
    /// @custom:reverts VaultZeroAddress If `newFeeCollector` is the zero address.
    /// @custom:reverts OwnableUnauthorizedAccount If called by a non-owner.
    function setFeeCollector(address newFeeCollector) external onlyOwner {
        _requireNonZeroAddress(newFeeCollector);
        feeCollector = newFeeCollector;
        emit FeeCollectorChanged(newFeeCollector);
    }

    /// @notice Pauses the vault.
    /// @dev Only the owner may call. While paused, all deposits, mints, withdrawals and
    ///      redemptions revert with `EnforcedPause`. Admin configuration functions
    ///      (`enableToken`, `disableToken`, `setWithdrawalTimelock`) remain available so the
    ///      owner can manage the vault during an emergency.
    /// @custom:reverts EnforcedPause If the vault is already paused.
    /// @custom:reverts OwnableUnauthorizedAccount If called by a non-owner.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses the vault.
    /// @dev Only the owner may call. Restores deposits, mints, withdrawals and redemptions.
    /// @custom:reverts ExpectedPause If the vault is not paused.
    /// @custom:reverts OwnableUnauthorizedAccount If called by a non-owner.
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Receipt tokens are non-transferable, so this always reverts.
    /// @custom:reverts VaultReceiptTokenNonTransferable Always reverts.
    function transfer(address, uint256) public virtual override(ERC20Upgradeable, IERC20) returns (bool) {
        revert VaultReceiptTokenNonTransferable();
    }

    /// @notice Receipt tokens are non-transferable, so this always reverts.
    /// @custom:reverts VaultReceiptTokenNonTransferable Always reverts.
    function transferFrom(address, address, uint256) public virtual override(ERC20Upgradeable, IERC20) returns (bool) {
        revert VaultReceiptTokenNonTransferable();
    }

    /// @notice Enforces a pause on every receipt-token mutation.
    /// @dev Overrides OpenZeppelin's `_update` hook so no receipt shares can be minted (`from` is
    ///      the zero address) or burned (`to` is the zero address) while the vault is paused,
    ///      regardless of the call path. This mirrors OpenZeppelin's `ERC20Pausable`.
    /// @custom:reverts EnforcedPause If the vault is paused.
    function _update(address from, address to, uint256 value) internal virtual override whenNotPaused {
        super._update(from, to, value);
    }
}
