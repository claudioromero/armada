## Tokenized vault

**Upgradeable, ownable (2-step) and pausable ERC-20 vault that issues shares backed by a single underlying ERC-20 asset.**


## Highliths

* Fully tested. Production grade.
    * Code coverage report in place.
    * Unit tests in place.
    * Github workflow in place.

* Code strength.
    * Static code vulnerabilities analysis handled by Slither.
    * Dynamic code analysis handled by Cursor.

* Well documented code.
    * [Docs] Documentation available in the docs folder for end users.
    * [Docs] Documentation can be generated automatically by running `npm run docs`

* Flattened contracts located in the "/flat" directory.
* ABIs located in the "/abi" directory.

## Documentation

An upgradeable, ownable (2-step) and pausable ERC-20 tokenized vault. Depositors exchange the underlying ERC-20 asset
for vault shares, which they can redeem back for the underlying asset at any time. The underlying asset is fixed at
deployment and cannot be changed. Deposits and withdrawals can be paused by the owner, and the owner can set opt-in
deposit and withdrawal fees, as well as sweep untracked assets.

## Usage

### Build

```shell
forge build
```

### Local Testing

```shell
forge test
```

### Generate test coverage report:

```shell
npm run coverage
```

### Static code analysis report:

```shell
npm run slither
```

or

```shell
slither .
```

### Testing on the Ethereum MainNet

```shell
npm run test-main
```

### Testing on Arbitrum

```shell
npm run test-arb
```

### Testing on Binance

```shell
npm run test-binance
```

### Testing on Avalanche

```shell
npm run test-avalanche
```

### Testing on Optimism

```shell
npm run test-opti
```

### Deploy / test the vault

The vault is defined in `src/tokens/TokenizedVault.sol` and deployed through the deployment script
(`script/TokenizedVault.s.sol`). Refer to the unit tests (`test/`) for usage examples.

