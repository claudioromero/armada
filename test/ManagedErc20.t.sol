// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {ManagedErc20} from "../src/ManagedErc20.sol";

contract ManagedErc20Test is Test {
    ManagedErc20 public token;
    address public minter;
    address public burner;
    address public deployer;
    address public investor;

    /// @notice Emitted when the token is configured with a new minter and burner.
    event TokenConfigured(address indexed minter, address indexed burner);

    /// @notice Emitted when the token is deployed with a name, symbol and decimals.
    event TokenDeployed(string name, string symbol, uint8 decimals);

    function setUp() public {
        minter = address(1234);
        burner = address(1235);
        deployer = address(1236);
        investor = address(1237);
    }

    function test01_CanDeployToken() public {
        // Deploy the token: watch it fail
        vm.expectRevert(ManagedErc20.InvalidTokenDecimals.selector);
        new ManagedErc20("Test Token", "TT", 0);

        vm.expectRevert(ManagedErc20.InvalidTokenDecimals.selector);
        new ManagedErc20("Test Token", "TT", 5);

        vm.expectRevert(ManagedErc20.InvalidTokenDecimals.selector);
        new ManagedErc20("Test Token", "TT", 7);

        vm.expectRevert(ManagedErc20.InvalidTokenDecimals.selector);
        new ManagedErc20("Test Token", "TT", 9);

        vm.expectRevert(ManagedErc20.InvalidTokenDecimals.selector);
        new ManagedErc20("Test Token", "TT", 17);

        vm.expectRevert(ManagedErc20.InvalidTokenDecimals.selector);
        new ManagedErc20("Test Token", "TT", 19);

        // Deploy the token: watch it pass
        new ManagedErc20("Test Token", "TT", 6);
        new ManagedErc20("Test Token", "TT", 8);
        new ManagedErc20("Test Token", "TT", 18);

        // Deploy the token: watch it pass and check the initial state
        vm.expectEmit();
        emit TokenDeployed("Test Token", "TT", 18);

        vm.prank(deployer);
        token = new ManagedErc20("Test Token", "TT", 18);

        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 0);
        assertEq(token.DEPLOYED_BY(), deployer);
        assert(keccak256(abi.encode(ManagedErc20(address(token)).symbol())) == keccak256(abi.encode("TT")));
        assert(keccak256(abi.encode(ManagedErc20(address(token)).name())) == keccak256(abi.encode("Test Token")));
        assertEq(token.minter(), address(0));
        assertEq(token.burner(), address(0));

        // Deploy the token: watch it pass and check the initial state
        vm.prank(deployer);
        token = new ManagedErc20("Test Token", "TT", 8);

        assertEq(token.decimals(), 8);
        assertEq(token.totalSupply(), 0);
        assertEq(token.DEPLOYED_BY(), deployer);
        assert(keccak256(abi.encode(ManagedErc20(address(token)).symbol())) == keccak256(abi.encode("TT")));
        assert(keccak256(abi.encode(ManagedErc20(address(token)).name())) == keccak256(abi.encode("Test Token")));
        assertEq(token.minter(), address(0));
        assertEq(token.burner(), address(0));

        // Deploy the token: watch it pass and check the initial state
        vm.prank(deployer);
        token = new ManagedErc20("Test Token", "TT", 6);

        assertEq(token.decimals(), 6);
        assertEq(token.totalSupply(), 0);
        assertEq(token.DEPLOYED_BY(), deployer);
        assert(keccak256(abi.encode(ManagedErc20(address(token)).symbol())) == keccak256(abi.encode("TT")));
        assert(keccak256(abi.encode(ManagedErc20(address(token)).name())) == keccak256(abi.encode("Test Token")));
        assertEq(token.minter(), address(0));
        assertEq(token.burner(), address(0));

        // Watch it fail: only the deployer can configure the token
        vm.expectRevert(ManagedErc20.InvalidDeployer.selector);
        token.configure(minter, burner);

        // Watch it fail: provide an invalid minter address
        vm.startPrank(deployer);

        vm.expectRevert(ManagedErc20.InvalidMinter.selector);
        token.configure(address(0), burner);

        vm.expectRevert(ManagedErc20.InvalidMinter.selector);
        token.configure(address(1), burner);

        vm.expectRevert(ManagedErc20.InvalidMinter.selector);
        token.configure(address(token), burner);

        // Watch it fail: provide an invalid burner address
        vm.expectRevert(ManagedErc20.InvalidBurner.selector);
        token.configure(minter, address(0));

        vm.expectRevert(ManagedErc20.InvalidBurner.selector);
        token.configure(minter, address(1));

        vm.expectRevert(ManagedErc20.InvalidBurner.selector);
        token.configure(minter, address(token));

        vm.stopPrank();
    }

    function test02_CanMintAndBurnToken() public {
        // Deploy the token: watch it pass and check the initial state
        vm.expectEmit();
        emit TokenDeployed("Test Token", "TT", 6);
        vm.prank(deployer);
        token = new ManagedErc20("Test Token", "TT", 6);

        assertEq(token.decimals(), 6);
        assertEq(token.totalSupply(), 0);
        assertEq(token.DEPLOYED_BY(), deployer);
        assert(keccak256(abi.encode(ManagedErc20(address(token)).symbol())) == keccak256(abi.encode("TT")));
        assert(keccak256(abi.encode(ManagedErc20(address(token)).name())) == keccak256(abi.encode("Test Token")));
        assertEq(token.minter(), address(0));
        assertEq(token.burner(), address(0));

        // Watch it fail: the token is not configured yet
        vm.expectRevert(ManagedErc20.TokenNotConfigured.selector);
        token.mint(investor, 1);

        // Watch it fail: the token is not configured yet
        vm.expectRevert(ManagedErc20.TokenNotConfigured.selector);
        token.burn(investor, 1);

        // Watch it pass
        vm.expectEmit();
        emit TokenConfigured(minter, burner);

        vm.prank(deployer);
        token.configure(minter, burner);
        assertEq(token.minter(), minter);
        assertEq(token.burner(), burner);

        // Watch it fail: tokens can be issued by the minter only
        vm.prank(deployer);
        vm.expectRevert(ManagedErc20.InvalidMinter.selector);
        token.mint(investor, 1);

        vm.prank(burner);
        vm.expectRevert(ManagedErc20.InvalidMinter.selector);
        token.mint(investor, 1);

        // Watch it fail: tokens can be issued to a valid address only
        vm.prank(minter);
        vm.expectRevert(ManagedErc20.InvalidTargetAddress.selector);
        token.mint(address(0), 1);

        vm.prank(minter);
        vm.expectRevert(ManagedErc20.InvalidTargetAddress.selector);
        token.mint(address(1), 1);

        vm.prank(minter);
        vm.expectRevert(ManagedErc20.InvalidTargetAddress.selector);
        token.mint(address(token), 1);

        // Watch it fail: tokens can be burned by the burner only
        vm.prank(deployer);
        vm.expectRevert(ManagedErc20.InvalidBurner.selector);
        token.burn(investor, 1);

        vm.prank(minter);
        vm.expectRevert(ManagedErc20.InvalidBurner.selector);
        token.burn(investor, 1);

        // Watch it fail: tokens can be burned to a valid address only
        vm.startPrank(burner);

        vm.expectRevert(ManagedErc20.InvalidTargetAddress.selector);
        token.burn(address(0), 1);

        vm.expectRevert(ManagedErc20.InvalidTargetAddress.selector);
        token.burn(address(1), 1);

        vm.expectRevert(ManagedErc20.InvalidTargetAddress.selector);
        token.burn(address(token), 1);

        vm.stopPrank();

        assertEq(token.totalSupply(), 0);

        // Watch it fail: the minter is not allowed to burn tokens
        vm.expectRevert(ManagedErc20.InvalidBurner.selector);
        vm.prank(minter);
        token.burn(investor, 600);

        // Watch it fail: the burner is not allowed to mint tokens
        vm.expectRevert(ManagedErc20.InvalidMinter.selector);
        vm.prank(burner);
        token.mint(investor, 100);

        // Watch it pass: mint some tokens to the investor
        vm.prank(minter);
        token.mint(investor, 1000);
        assertEq(token.totalSupply(), 1000);
        assertEq(token.balanceOf(investor), 1000);

        // Watch it pass: burn some tokens from the investor
        vm.prank(burner);
        token.burn(investor, 600);
        assertEq(token.totalSupply(), 400);
        assertEq(token.balanceOf(investor), 400);

        // Watch it fail: the investor cannot burn more tokens than the total supply
        vm.expectRevert();
        vm.prank(burner);
        token.burn(investor, 401);

        // Watch it pass: burn all of the remaining tokens from the investor
        vm.prank(burner);
        token.burn(investor, 400);
        assertEq(token.totalSupply(), 0);
        assertEq(token.balanceOf(investor), 0);
    }

    function test03_CanTransferToken() public {
        vm.startPrank(deployer);
        token = new ManagedErc20("Test Token", "TT", 6);
        token.configure(minter, burner);
        vm.stopPrank();

        vm.prank(minter);
        token.mint(investor, 1000);
        assertEq(token.totalSupply(), 1000);
        assertEq(token.balanceOf(investor), 1000);
        assertEq(token.balanceOf(minter), 0);

        vm.prank(investor);
        assertEq(token.transfer(minter, 100), true);
        assertEq(token.balanceOf(minter), 100);
        assertEq(token.balanceOf(investor), 900);

        assertEq(token.allowance(investor, minter), 0);
        vm.prank(investor);
        token.approve(minter, 200);
        assertEq(token.allowance(investor, minter), 200);

        vm.prank(minter);
        assertEq(token.transferFrom(investor, minter, 200), true);

        assertEq(token.balanceOf(minter), 300);
        assertEq(token.balanceOf(investor), 700);
        assertEq(token.allowance(investor, minter), 0);
    }
}
