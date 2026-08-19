## Managed ERC-20 token - Example

**Managed ERC-20 token that can be upgraded via ERC-1967**


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

A managed ERC-20 token that can be upgraded via ERC-1967.
The circulating supply is controlled by a specific minter and burner, for the sake of demo.

## Usage

### Build

```shell
$ forge build
```

### Local Testing

```shell
$ forge test
```

### Generate test coverage report:

```shell
$ npm run coverage
```

### Static code analysis report:

```shell
$ npm run slither
```

or

```shell
$ slither .
```

### Testing on the Ethereum MainNet

```shell
$ npm run test-main
```

### Testing on Arbitrum

```shell
$ npm run test-arb
```

### Testing on Binance

```shell
$ npm run test-binance
```

### Testing on Avalanche

```shell
$ npm run test-avalanche
```

### Deploy

```shell
$ forge script script/ManagedErc20.s.sol:ManagedErc20Script --rpc-url <your_rpc_url> --private-key <your_private_key>
```

