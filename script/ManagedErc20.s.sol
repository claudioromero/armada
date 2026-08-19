// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {ManagedErc20} from "../src/ManagedErc20.sol";

contract ManagedErc20Script is Script {
    ManagedErc20 public instance;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        instance = new ManagedErc20("Test Token", "TT", 6);

        vm.stopBroadcast();
    }
}
