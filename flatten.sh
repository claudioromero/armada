#!/usr/bin/env bash
forge build --extra-output-files abi
forge flatten ./src/vault/TokenizedVault.sol --output ./flat/TokenizedVault.sol
forge inspect TokenizedVault abi --json > abi/TokenizedVault.json
