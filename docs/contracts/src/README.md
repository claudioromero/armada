## Managed ERC-20 token - sample starter

**Managed ERC-20 token that can be upgraded via ERC-1967**


## Highliths

* Fully tested. Production grade.
    * Code coverage report in place.
    * Unit tests in place.

* Code strength.
    * [Static] Code & vulnerabilities analysis handled by Slither
    * [AI] Dynamic code analysis handled by Cursor and Claude.

* Well documented code.
    * [Docs] Documentation available in the docs folder for end users.
    * [Docs] Documentation can be generated automatically by running `npm run docs`

* Code flattening in place, for further deployment. (see flat folder)

## Documentation

A managed ERC-20 token that can be upgraded via ERC-1967.
The circulating supply is controlled by a specific minter and burner, for the sake of demo.

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```


### Deploy

```shell
$ forge script script/ManagedErc20.s.sol:ManagedErc20Script --rpc-url <your_rpc_url> --private-key <your_private_key>
```

