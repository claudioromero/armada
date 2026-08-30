# TokenizedVault
[Git Source](https://github.com/claudioromero/armada/blob/dd050a63c94e349c67999e4f35c193d86623b09e/src/tokens/TokenizedVault.sol)

**Inherits:**
ERC20Upgradeable, Ownable2StepUpgradeable, PausableUpgradeable

**Title:**
Represents a tokenized vault that issues ERC-20 shares backed by a single underlying ERC-20 asset.

Depositors exchange the underlying asset for shares, and redeem shares for the underlying asset.

Ownable in 2 steps. The underlying asset is set in the constructor and cannot be changed.

The vault can be paused by the owner. Fees are optional and set by the owner.


## State Variables
### UNDERLYING_ASSET
The underlying ERC-20 asset backing the vault shares. Set in the constructor and cannot be changed.


```solidity
IERC20 public immutable UNDERLYING_ASSET
```


### MAX_FEE
The maximum allowed deposit and withdrawal fee, expressed in basis points. 10_000 equals 100%.


```solidity
uint256 public constant MAX_FEE = 10_000
```


### depositFee
The fee applied on deposits, expressed in basis points.


```solidity
uint256 public depositFee
```


### withdrawalFee
The fee applied on withdrawals, expressed in basis points.


```solidity
uint256 public withdrawalFee
```


### _FEE_DENOMINATOR
The denominator used to compute fee amounts.


```solidity
uint256 private constant _FEE_DENOMINATOR = 10_000
```


## Functions
### constructor

Initializes the vault with its underlying asset and share token parameters.

The underlying asset cannot be changed afterwards. The deployer becomes the owner.


```solidity
constructor(address newUnderlyingAsset, string memory sharesName, string memory sharesSymbol) initializer;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newUnderlyingAsset`|`address`|The ERC-20 token that backs the vault shares.|
|`sharesName`|`string`|The descriptive name of the vault share token.|
|`sharesSymbol`|`string`|The symbol of the vault share token.|


### deposit

Deposits underlying assets and mints an equivalent amount of shares to the caller.

The caller must approve this vault to spend the assets beforehand. A deposit fee may be applied.


```solidity
function deposit(uint256 assets) external whenNotPaused returns (uint256 shares);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assets`|`uint256`|The amount of underlying assets to deposit.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`shares`|`uint256`|The amount of shares minted to the caller.|


### redeem

Redeems shares in exchange for underlying assets.

A withdrawal fee may be applied. The caller must own the shares being redeemed.


```solidity
function redeem(uint256 shares) external whenNotPaused returns (uint256 assets);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`shares`|`uint256`|The amount of shares to redeem.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`assets`|`uint256`|The amount of underlying assets transferred to the caller.|


### setDepositFee

Updates the fee applied on deposits.


```solidity
function setDepositFee(uint256 newFee) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newFee`|`uint256`|The new deposit fee in basis points. Must be within [0, MAX_FEE].|


### setWithdrawalFee

Updates the fee applied on withdrawals.


```solidity
function setWithdrawalFee(uint256 newFee) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newFee`|`uint256`|The new withdrawal fee in basis points. Must be within [0, MAX_FEE].|


### pause

Pauses deposits and withdrawals. Only the owner can pause.


```solidity
function pause() external onlyOwner;
```

### unpause

Unpauses deposits and withdrawals. Only the owner can unpause.


```solidity
function unpause() external onlyOwner;
```

### sweepUnderlying

Emergency withdrawal that transfers all of the vault's underlying holdings to the owner.

Intended as a safety measure for the trusted owner. Transfers the entire underlying balance.


```solidity
function sweepUnderlying() external onlyOwner;
```

### totalAssets

Gets the total amount of underlying assets held by the vault.


```solidity
function totalAssets() public view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|uint256 The total amount of underlying assets.|


### decimals

Gets the number of decimals of the vault share token.


```solidity
function decimals() public pure override returns (uint8);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint8`|uint8 The number of decimals.|


### _calculateShares

Computes the number of shares to mint for a given amount of underlying assets.


```solidity
function _calculateShares(uint256 assets) internal view returns (uint256 shares);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assets`|`uint256`|The amount of underlying assets deposited.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`shares`|`uint256`|The number of shares to mint.|


### _calculateAssets

Computes the amount of underlying assets for a given amount of shares.


```solidity
function _calculateAssets(uint256 shares) internal view returns (uint256 assets);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`shares`|`uint256`|The amount of shares to redeem.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`assets`|`uint256`|The amount of underlying assets to transfer.|


### _applyFee

Computes the net amount after deducting a fee in basis points.


```solidity
function _applyFee(uint256 amount, uint256 fee) internal pure returns (uint256 netAmount);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint256`|The gross amount.|
|`fee`|`uint256`|The fee in basis points.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`netAmount`|`uint256`|The net amount after deducting the fee.|


## Events
### Deposited
Emitted when an account deposits underlying assets and receives shares.


```solidity
event Deposited(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
```

### Redeemed
Emitted when an account redeems shares and receives underlying assets.


```solidity
event Redeemed(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
```

### DepositFeeSet
Emitted when the owner updates the deposit fee.


```solidity
event DepositFeeSet(uint256 fee);
```

### WithdrawalFeeSet
Emitted when the owner updates the withdrawal fee.


```solidity
event WithdrawalFeeSet(uint256 fee);
```

### UnderlyingSwept
Emitted when the owner sweeps untracked underlying assets to the owner.


```solidity
event UnderlyingSwept(address indexed recipient, uint256 amount);
```

## Errors
### InvalidUnderlyingAsset
Triggers if the underlying asset is not a valid ERC-20 token.


```solidity
error InvalidUnderlyingAsset();
```

### ZeroAmount
Triggers if the provided amount is zero.


```solidity
error ZeroAmount();
```

### InsufficientBalance
Triggers if the caller does not own enough shares to redeem.


```solidity
error InsufficientBalance();
```

### InsufficientLiquidity
Triggers if the vault does not hold enough underlying assets to honour a withdrawal.


```solidity
error InsufficientLiquidity();
```

### InvalidFee
Triggers if the provided fee is greater than the maximum allowed value.


```solidity
error InvalidFee();
```

### VaultNotFunded
Triggers if the vault has not been funded with the initial underlying assets.


```solidity
error VaultNotFunded();
```

