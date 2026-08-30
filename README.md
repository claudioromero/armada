# Armada — Tokenized Vault

**Upgradeable, ownable (2-step) and pausable ERC-4626 vault that issues non-transferable receipt shares backed by a single underlying ERC-20 asset.**

## Highlights

* Fully tested. Production grade.
  * Unit tests in place (`test/`).
  * Code coverage report in place (`lcov.info`).
  * GitHub workflow in place (`.github/workflows/test.yml`).

* Code strength.
  * Static analysis handled by Slither (`.github/workflows/slither.yml`, `slither.config.json`).
  * Well documented code with generated docs.

* Well documented code.
  * [Docs] Documentation is generated automatically by running `npm run docs`.
  * Flattened contract in `/flat`, ABI in `/abi`.

## What it is

An upgradeable tokenized vault implementing [ERC-4626](https://eips.ethereum.org/EIPS/eip-4626). Depositors exchange
the underlying ERC-20 asset — or any owner-enabled token valued through Chainlink price feeds — for vault shares, which
they can redeem back for the underlying asset. The underlying asset is fixed at deployment and cannot be changed.

The vault is deployed behind an ERC-1967 transparent proxy and is owned through a 2-step ownership transfer. The owner
can pause deposits/withdrawals during emergencies, set an opt-in withdrawal timelock, set a minimum deposit amount, set
a withdrawal fee and manage the set of enabled tokens.

## Features

- **ERC-4626 compliant** — standard `deposit`, `mint`, `withdraw`, `redeem` entry points (plus a token-based
  `deposit(address, uint256)` convenience), `preview*` and `max*` functions.
- **Multi-token deposits** — the underlying asset is always accepted; any other token must be enabled by the owner with
  a Chainlink USD price feed and is valued against the underlying via `getTokenValue`.
- **Price feed safety** — feeds are checked for staleness (1-day heartbeat), non-positive answers and round integrity;
  deposits and redemptions revert if a feed is not fresh.
- **Proportional basket payouts** — every withdraw/redeem is paid as a pro-rata slice of the vault's holdings: the
  underlying asset plus each enabled token currently held. A vault that holds only the underlying pays out purely in
  it; a vault holding enabled tokens stays fully liquid even with no underlying reserves. The withdrawal fee (if set)
  is collected as the same pro-rata basket.

- **Virtual-share inflation protection** — a fixed internal share offset guarantees the first depositor cannot be
  rounded to zero when a vault is seeded by a donation; shares always have at least the virtual-share value, which feeds
  into the ERC-4626 conversions and `preview*`/`max*` functions.

- **Held tokens cannot be disabled** — `disableToken` reverts while the vault still holds a balance of that token,
  preventing the vault from silently dropping coverage of an asset it has not fully paid out.
- **Non-transferable receipt tokens** — `transfer` and `transferFrom` always revert; a third party may only
  withdraw/redeem someone's shares through an ERC-20 allowance.
- **Withdrawal timelock** — per-account lock (in seconds) configurable by the owner; `0` means instant withdrawals.
- **Withdrawal fee** — configurable fee in basis points charged on every withdraw and redeem; the fee is deducted
  from the payout and forwarded to the `feeCollector` (defaults to the owner). Both are owner-settable. If the
  collector cannot receive the asset, the fee stays in the vault rather than blocking the withdrawal. `preview*`
  and `max*` are fee-aware.
- **Pausable** — the owner can pause and unpause the vault; while paused, no deposits, withdrawals or share mint/burn.
- **Reentrancy protected** — all deposit/withdraw entry points and token/fee administration are `nonReentrant`.
- **No Ether accepted** — `receive` and `fallback` revert.
- **Upgradeable** — ERC-1967 transparent proxy, deployed at a predictable CREATE2 address through a proxy factory, with
  a 2-step-ownable proxy admin.

## Contract overview

All contracts live in `src/vault/`:

| Contract | Description |
| --- | --- |
| `TokenizedVault.sol` | The vault implementation: ERC-4626 vault, enabled-token deposits, timelock, minimum deposit, withdrawal fee, pause. |
| `VaultTransparentProxy.sol` | ERC-1967 transparent proxy. Its immutable admin can only call `upgradeToAndCall`. |
| `IVaultTransparentProxy.sol` | Interface for the transparent proxy (`admin`, `implementation`, `upgradeToAndCall`). |
| `VaultProxyAdmin.sol` | 2-step ownable admin that lets its owner upgrade vault proxies. |
| `ProxyFactory.sol` | 2-step ownable factory that deploys proxies at predictable CREATE2 addresses. |
| `IPriceFeed.sol` | Chainlink-compatible price feed interface (`latestRoundData`, `decimals`). |

See the unit tests in `test/Vault.t.sol` for usage examples of every entry point.

## Usage

### Requirements

- [Foundry](https://getfoundry.sh/)
- Node.js >= 16 for the npm scripts

Install dependencies:

```shell
npm ci
```

### Build

```shell
forge build
```

### Test

```shell
forge test
```

### Test on a forked network

```shell
npm run test-main        # Ethereum
npm run test-arb         # Arbitrum
npm run test-binance     # BNB Chain
npm run test-avalanche   # Avalanche
npm run test-opti        # Optimism
```

### Code coverage

```shell
npm run coverage
```

Generates `lcov.info` and an HTML report under `docs/coverage-report`.

### Static analysis

```shell
npm run slither
```

or

```shell
slither .
```

Writes a checklist report to `docs/slither-reports/All.md`.

### Documentation

```shell
npm run docs
```

Generates contract documentation into `docs/contracts`.

### Flattened contracts and ABIs

```shell
./flatten.sh
```

Produces `flat/TokenizedVault.sol` and `abi/TokenizedVault.json`.

```shell
npm run abis
```

Builds per-contract ABIs into `out/`.

### Code style check

```shell
npm run check
```

Runs `forge fmt --check`.

## Deploying a vault

There is no deployment script; the vault is deployed and initialized in one transaction through the factory:

1. Deploy `TokenizedVault` (implementation).
2. Deploy `VaultProxyAdmin` behind a transparent proxy and transfer ownership.
3. Deploy `ProxyFactory` behind a transparent proxy, initialize it with the implementation and proxy admin addresses.
4. Call `factory.deployProxy(salt, data)` where `data` is the encoded `TokenizedVault.initialize(...)` call
   (owner, underlying asset, share name/symbol, underlying price feed, timelock, minimum deposit, withdrawal fee).

The resulting proxy address can be precomputed with `factory.predictProxyAddress(salt, data)`. Upgrades are performed
by the proxy admin owner via `VaultProxyAdmin.upgrade(proxy, newImplementation)`.

## License

BUSL-1.1