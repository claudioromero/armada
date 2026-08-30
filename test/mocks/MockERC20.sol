// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    uint8 private immutable _decimals;

    mapping(address => bool) public blacklisted;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    function blacklist(address who) external {
        blacklisted[who] = true;
    }

    function unblacklist(address who) external {
        blacklisted[who] = false;
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        require(!blacklisted[to], "MockERC20: recipient blacklisted");
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        require(!blacklisted[to], "MockERC20: recipient blacklisted");
        return super.transferFrom(from, to, amount);
    }
}
