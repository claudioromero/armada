# ManagedErc20
**Inherits:**
ERC20Upgradeable

**Title:**
Represents an upgradeable ERC20 token that can be managed by a minter and a burner.


## State Variables
### _DECIMALS
The number of token decimals. Supported values are 6, 8 or 18.


```solidity
uint8 internal immutable _DECIMALS
```


### DEPLOYED_BY
The deployer of the smart contract. This is the only account authorized to configure the token.


```solidity
address public immutable DEPLOYED_BY
```


### minter
The minter. This is the only account authorized to mint tokens. It is usually a smart contract that implements a bridge or a vault.


```solidity
address public minter
```


### burner
The burner. This is the only account authorized to burn tokens. It is usually a smart contract that implements a bridge or a vault.


```solidity
address public burner
```


## Functions
### constructor

Initializes the token with the minimum required parameters for a cross-chain scenario.


```solidity
constructor(string memory newTokenName, string memory newTokenSymbol, uint8 newDecimals) initializer;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newTokenName`|`string`|The descriptive name of the token.|
|`newTokenSymbol`|`string`|The token symbol.|
|`newDecimals`|`uint8`|The token decimals. Supported values are 6, 8 or 18.|


### configure

Configures the token.

The token can be configured after deployment, as long as you are the deployer. The minter and burner are allowed to be the same address.


```solidity
function configure(address newMinter, address newBurner) public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newMinter`|`address`|The minter. This is the only account authorized to mint tokens. It is usually a smart contract that implements a bridge or a vault.|
|`newBurner`|`address`|The burner. This is the only account authorized to burn tokens. It is usually a smart contract that implements a bridge or a vault.|


### mint

Mints new tokens.

Only the minter can call this function.


```solidity
function mint(address account, uint256 value) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|The address of the account to mint tokens to.|
|`value`|`uint256`|The amount of tokens to mint.|


### burn

Burns existing tokens.

Only the burner can call this function.


```solidity
function burn(address account, uint256 value) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|The address of the account to burn tokens from.|
|`value`|`uint256`|The amount of tokens to burn.|


### decimals

Gets the number of token decimals.


```solidity
function decimals() public view override returns (uint8);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint8`|uint8 The number of token decimals.|


### _ensureTokenConfigured

Ensures that the token is configured before allowing minting or burning.


```solidity
function _ensureTokenConfigured() internal view;
```

## Events
### TokenConfigured
Emitted when the token is configured with a new minter and burner.


```solidity
event TokenConfigured(address indexed minter, address indexed burner);
```

### TokenDeployed
Emitted when the token is deployed with a name, symbol and decimals.


```solidity
event TokenDeployed(string name, string symbol, uint8 decimals);
```

## Errors
### InvalidTokenDecimals
Triggers when the number of token decimals is invalid


```solidity
error InvalidTokenDecimals();
```

### InvalidMinter
Triggers if the sender is not the designed minter


```solidity
error InvalidMinter();
```

### InvalidBurner
Triggers if the sender is not the designed burner


```solidity
error InvalidBurner();
```

### TokenNotInitialized
Triggers if the smart contract is not initialized yet


```solidity
error TokenNotInitialized();
```

### TokenNotConfigured
Triggers if the smart contract is not configured yet


```solidity
error TokenNotConfigured();
```

### InvalidTargetAddress
Triggers if a given address is not valid for the target account (minting or burning)


```solidity
error InvalidTargetAddress();
```

### InvalidDeployer
Triggers if the sender is not the deployer of the smart contract


```solidity
error InvalidDeployer();
```

