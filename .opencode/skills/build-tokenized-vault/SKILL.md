---
name: build-tokenized-vault
description: Build a tokenized vault.
license: MIT
compatibility: opencode
metadata:
  audience: developers
---

## What I do

- Build an upgradeable smart contract that inherits from OpenZeppelin's `Ownable2StepUpgradeable`.
- The contract must be stored in the `src` directory of the project and must be named `TokenizedVault.sol`.
- The contract must have an underlying asset that is an ERC-20 token. The address of the underlying asset must be set during initialization and cannot be changed afterwards.
- The underlying token must have 6, 8 or 18 decimals. If the underlying token has a different number of decimals, an error must be thrown.
- The function `initialize` must check if the token is a valid ERC-20 token by calling the `totalSupply` function. If the call fails, an error must be thrown.
- The contract must be upgradeable using ERC-1967 (transparent proxy). 
- The contract must implement the interface `IERC4626` from OpenZeppelin. 
- The contract must inherit from OpenZeppelin's `ERC4626Upgradeable`.
- The contract must emit an event called `vaultInitialized` when the contract is initialized and must include the address of the underlying asset.
- Write the proxy and proxy admin contracts using OpenZeppelin's `TransparentUpgradeableProxy` and `ProxyAdmin` contracts. The proxy contract must be deployed by a ProxyFactory contract with the address of the implementation contract and the address of the proxy admin contract. The proxy admin contract must be ownable in 2 steps and inherit from OpenZeppelin's `Ownable2StepUpgradeable`. The proxy admin contract must have a function called `upgrade` that allows the owner to upgrade the implementation contract by providing the address of the new implementation contract.  
- The proxy factory must be ownable. It must inherit from `Ownable2StepUpgradeable`.
- The proxy must be deployed at a predictable address using the CREATE2 opcode. The salt used for the CREATE2 deployment must be passed as an argument to the ProxyFactory contract. The salt must be unique for each deployment of the proxy contract.
- The contract must not accept Ether transfers. Write a fallback function to prevent Ether transfers.
- The tokenized vault must be pausable. Only the owner can pause and unpause the vault.
- Users cannot deposit or withdraw if the vault is paused. Users cannot mint or burn tokens if the vault is paused.
- A fee applies when users withdraw funds from the vault. This fee must be called `withdrawalFee`. The withdrawal fee can be updated by the owner only.
- Define a variable called `feeCollector`. This variable represents the address of the fee collector. This address can be updated by the owner only.
- When users withdraw funds from the vault, the resulting fee must be sent to the fee collector address.

- Define a variable called `minimumDepositAmount`. This variable represents the minimum amount users can deposit in the vault. The minimum deposit amount must be expressed in underlying tokens. 
- Provide a function to update the price feed of a given token. Only the owner is authorized to call this function.

- The contract must have a set of enabled tokens. Only the owner can enable or disable tokens. The status of a token must be stored in a public mapping called `isTokenEnabled`. The mapping returns true if the token is enabled and false if it is disabled.
- The contract must have a public function called `getEnabledTokens` that returns an array of all enabled tokens.
- The contract must emit an event called `TokenStatusChanged` whenever a token is enabled or disabled. The event must include the address of the token and its new status (enabled or disabled).
- The token to enable must have 6, 8 or 18 decimals. If the token has a different number of decimals, an error must be thrown.

- The ratio between each enabled token and the underlying asset must be defined by a Chainlink price feed. The contract must have a public function called `getTokenValue` that takes the address of an enabled token and returns its value in terms of the underlying asset using the Chainlink price feed. If the token is not enabled, an error must be thrown.
- The function `enableToken` must check if the token is a valid ERC-20 token by calling the `totalSupply` function. If the call fails, the token must not be enabled and an error must be thrown.
- The function `enableToken` must revert if the token passed as an argument is the underlying asset.
- The function `enableToken` must have the following parameters: tokenAddr (address of the token to be enabled), priceFeedAddr (address of the Chainlink price feed for the token), and decimals (number of decimals for the token). The function must store the price feed address and decimals in a public mapping called `tokenPriceFeeds`. If the token is already enabled, an error must be thrown.
- The mapping `tokenPriceFeeds` must be designed in the form `mapping(address => PriceFeed) public tokenPriceFeeds;` where `PriceFeed` is a struct that contains the price feed address and the number of decimals for the token.
- Check for staleness when interacting with ChainLink oracles.
- The interface `IPriceFeed` must be stored in a separate file named `IPriceFeed.sol`

- The tokens that can be deposited are defined by the `isTokenEnabled` mapping. The contract must have a public function called `deposit` that allows users to deposit enabled tokens into the vault. The function must check if the token is enabled before allowing the deposit. If the token is not enabled and the token is not the underlying asset, an error must be thrown.

- The contract must issue a receipt token to users when they deposit enabled tokens into the vault. The receipt token must be an ERC-20 token that represents the user's share of the vault. The receipt token must be minted to the user when they deposit enabled tokens and burned when they withdraw their share of the vault.

- The underlying token cannot be disabled. In the function `disableToken`, if the token passed is the underlying token then the contract must throw an error.

- The contract must be compliant with the ERC-4626 standard for tokenized vaults. The contract must implement the following functions: `totalAssets`, `convertToShares`, `convertToAssets`, `maxDeposit`, `maxMint`, `maxWithdraw`, `maxRedeem`, `previewDeposit`, `previewMint`, `previewWithdraw`, and `previewRedeem`. The contract must also implement the following events: `Deposit` and `Withdraw`.

- The contract must track the address of the depositor and the timestamp of their deposit. The contract must have a public mapping called `deposits` that maps the address of the depositor to a struct that contains the amount of enabled tokens deposited and the timestamp of the deposit.

- The receipt token minted by the vault must be non-transferable. The contract must override the `transfer` and `transferFrom` functions of the ERC-20 standard to prevent users from transferring their receipt tokens to other addresses. The contract must throw an error if a user tries to transfer their receipt tokens.

- Revert when shares == 0 in the `deposit` function.

- Do not pay out the redemption as a proportional slice of every token the vault holds. Instead, the vault must pay out the redemption in the underlying asset only. 
- The vault must pay in underlying tokens only. Do not pay in any other tokens. 
- When calling the `withdraw` function, the vault must pay out in the underlying token only. The vault must not pay out in any other tokens!

- The following functions must be non-reentrant: `enableToken`, `deposit`, `redeem` and `withdraw`. Inhertit from OpenZeppellin's `ReentracyGuardUpgrdeable`

- The contract must have a public variable called `withdrawalTimelock` that defines the time in seconds that a user must wait before they can withdraw their share of the vault after making a deposit. The variable must be set during initialization. The contract must have a public function called `setWithdrawalTimelock` that allows the owner to change the value of the `withdrawalTimelock` variable. The function must emit an event called `WithdrawalTimelockChanged` whenever the value of the `withdrawalTimelock` variable is changed. The event must include the new value of the `withdrawalTimelock` variable.
- If the `withdrawalTimelock` variable is set to 0, users can withdraw their share of the vault immediately after making a deposit. If the `withdrawalTimelock` variable is set to a value greater than 0, users must wait for the specified time before they can withdraw their share of the vault.
- The withdrawal must throw an error if the user tries to withdraw their share of the vault before the `withdrawalTimelock` has expired. 
- The functions `previewRedeem`, `previewWithdraw`, `maxRedeem` and `maxWithdraw` must return zero if the withdrawal timelock did not elapse.

- The proxy factory must emit an event called `ProxyDeployed` whenever a new proxy contract is deployed. The event must include the address of the proxy contract, the address of the implementation contract, and the address of the proxy admin contract.

- If the withdrawal fee is greater than the assets to withdraw then throw an error.

- The source code must be well-structured. Put all constants, variables, events and errors at the top.
- All funcions, events, errors and variables must be documented. Make sure all functions have their Natspec.
- Do not generate a deployment script.

- Make sure all contracts build successfully before running the tests.

- Write comprehensive unit tests for the contract. The tests must cover all functions and events of the contract, including edge cases and error handling. The tests must be written in a separate file called `Vault.test.js` and must be located in the `test` directory of the project.

- When testing deposits, use USDC as the underlying asset and DAI as the enabled token. Use the Chainlink price feed for DAI/USD to get the value of DAI in terms of USDC. The price feed address for DAI/USD on Ethereum mainnet is `0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9`. The price feed address for USDC/USD on Ethereum mainnet is `0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6`.

- When testing deposits, use USDC as the underlying asset and USDT as the enabled token. Use the Chainlink price feed for USDT/USD to get the value of USDT in terms of USDC. The price feed address for USDT/USD on Ethereum mainnet is `0x3E7d1eAB13ad0104d2750B8863b489D65364e32D`. The price feed address for USDC/USD on Ethereum mainnet is `0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6`.

- When testing deposits, use USDC as the underlying asset and WBTC as the enabled token. Use the Chainlink price feed for WBTC/USD to get the value of WBTC in terms of USDC. The price feed address for WBTC/USD on Ethereum mainnet is `0xdeb288F737066589598e9214E782fa5A8eD689e8`. The price feed address for USDC/USD on Ethereum mainnet is `0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6`.

- When testing deposits, use USDC as the underlying asset and WETH as the enabled token. Use the Chainlink price feed for WETH/USD to get the value of WETH in terms of USDC. The price feed address for WETH/USD on Ethereum mainnet is `0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419`. The price feed address for USDC/USD on Ethereum mainnet is `0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6`.

- When testing deposits, create a test that has WBTC as the underlying asset and USDC as the enabled token. Use the Chainlink price feed for USDC/USD to get the value of USDC in terms of WBTC. The price feed address for USDC/USD on Ethereum mainnet is `0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6`. The price feed address for WBTC/USD on Ethereum mainnet is `0xdeb288F737066589598e9214E782fa5A8eD689e8`.

- When testing deposits, create a test that has WBTC as the underlying asset and WETH as the enabled token. Use the Chainlink price feed for WETH/USD to get the value of WETH in terms of WBTC. The price feed address for WETH/USD on Ethereum mainnet is `0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419`. The price feed address for WBTC/USD on Ethereum mainnet is `0xdeb288F737066589598e9214E782fa5A8eD689e8`.

- When testing deposits, create a test that has WETH as the underlying asset and WBTC as the enabled token. Use the Chainlink price feed for WBTC/USD to get the value of WBTC in terms of WETH. The price feed address for WBTC/USD on Ethereum mainnet is `0xdeb288F737066589598e9214E782fa5A8eD689e8`. The price feed address for WETH/USD on Ethereum mainnet is `0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419`.

- When testing deposits, create a test that has WETH as the underlying asset and USDC as the enabled token. Use the Chainlink price feed for USDC/USD to get the value of USDC in terms of WETH. The price feed address for USDC/USD on Ethereum mainnet is `0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6`. The price feed address for WETH/USD on Ethereum mainnet is `0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419`.

- When testing deposits, create a test that has WETH as the underlying asset and USDT as the enabled token. Use the Chainlink price feed for USDT/USD to get the value of USDT in terms of WETH. The price feed address for USDT/USD on Ethereum mainnet is `0x3E7d1eAB13ad0104d2750B8863b489D65364e32D`. The price feed address for WETH/USD on Ethereum mainnet is `0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419`.

- Write tests with different timelocks for withdrawals. For example, test with a 0 second timelock, a 1 hour timelock, and a 24 hour timelock. Make sure to test that users cannot withdraw their share of the vault before the timelock has expired.

- Make sure the test coverage is at least 90% for the contract.


## When to use me

Use this when you are building a tokenized vault.

