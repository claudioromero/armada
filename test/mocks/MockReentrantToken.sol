// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IReentrantVault {
    function deposit(address token, uint256 amount, address receiver) external returns (uint256);
}

contract MockReentrantToken is ERC20 {
    address public vault;
    bool public reenterOn;

    constructor(address vault_) ERC20("Reentrant Token", "RENT") {
        vault = vault_;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setReenter(bool reenterOn_) external {
        reenterOn = reenterOn_;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        if (reenterOn) {
            reenterOn = false;
            IReentrantVault(vault).deposit(address(this), amount / 2, tx.origin);
        }
        return super.transferFrom(from, to, amount);
    }
}
