// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {PausableUpgradeable} from "@openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TokenizedVault} from "../src/vault/TokenizedVault.sol";
import {IERC4626} from "@openzeppelin-contracts/interfaces/IERC4626.sol";
import {VaultTransparentProxy} from "../src/vault/VaultTransparentProxy.sol";
import {IVaultTransparentProxy} from "../src/vault/IVaultTransparentProxy.sol";
import {VaultProxyAdmin} from "../src/vault/VaultProxyAdmin.sol";
import {ProxyFactory} from "../src/vault/ProxyFactory.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockChainlinkPriceFeed} from "./mocks/MockChainlinkPriceFeed.sol";
import {MockReentrantToken} from "./mocks/MockReentrantToken.sol";

contract VaultTest is Test {
    MockERC20 internal usdc;
    MockERC20 internal usdt;
    MockERC20 internal dai;
    MockERC20 internal wbtc;
    MockERC20 internal weth;

    MockChainlinkPriceFeed internal feedUsdc;
    MockChainlinkPriceFeed internal feedUsdt;
    MockChainlinkPriceFeed internal feedDai;
    MockChainlinkPriceFeed internal feedWbtc;
    MockChainlinkPriceFeed internal feedWeth;

    TokenizedVault internal implementation;
    VaultProxyAdmin internal proxyAdmin;
    ProxyFactory internal factory;
    TokenizedVault internal vault;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal carol = address(0xCAF3);

    bytes32 internal constant SALT = keccak256("armada-vault-v1");

    function setUp() public virtual {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        usdt = new MockERC20("Tether USD", "USDT", 6);
        dai = new MockERC20("Dai Stablecoin", "DAI", 18);
        wbtc = new MockERC20("Wrapped BTC", "WBTC", 8);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);

        feedUsdc = new MockChainlinkPriceFeed(8, 1e8); // 1 USD
        feedUsdt = new MockChainlinkPriceFeed(8, 1e8); // 1 USD
        feedDai = new MockChainlinkPriceFeed(8, 1e8); // 1 USD
        feedWbtc = new MockChainlinkPriceFeed(8, 30_000e8); // 30,000 USD
        feedWeth = new MockChainlinkPriceFeed(8, 2_000e8); // 2,000 USD

        implementation = new TokenizedVault();
        proxyAdmin = _deployProxyAdmin();

        factory = _deployProxyFactory();
    }

    function _deployProxyFactory() internal returns (ProxyFactory f) {
        return _deployProxyFactory(address(implementation), address(proxyAdmin));
    }

    function _deployProxyFactory(address impl, address admin) internal returns (ProxyFactory f) {
        f = ProxyFactory(
            address(
                new TransparentUpgradeableProxy(
                    address(new ProxyFactory()),
                    address(this),
                    abi.encodeCall(ProxyFactory.initialize, (address(this), impl, admin))
                )
            )
        );
    }

    function _deployVault(MockERC20 underlying, MockChainlinkPriceFeed underlyingFeed, uint256 timelock)
        internal
        returns (TokenizedVault v)
    {
        bytes memory initData = abi.encodeCall(
            TokenizedVault.initialize,
            (address(this), address(underlying), "Armada Vault Shares", "AVS", address(underlyingFeed), timelock, 0, 0)
        );
        address proxy = factory.deployProxy(SALT, initData);
        v = TokenizedVault(payable(proxy));
    }

    function _enable(address token, MockChainlinkPriceFeed feed, uint8 decimals) internal {
        vault.enableToken(token, address(feed), decimals);
    }

    function _usdPrice(MockChainlinkPriceFeed feed) internal view returns (uint256) {
        uint256 answer = uint256(feed.answer());
        return (answer * 1e18) / (10 ** uint256(feed.decimals()));
    }

    function _tokenValue(uint256 px, uint256 pu) internal pure returns (uint256) {
        return (px * 1e18) / pu;
    }

    function _toUnderlying(
        uint256 amount,
        MockChainlinkPriceFeed tokenFeed,
        uint8 tDecimals,
        uint256 pu,
        uint8 uDecimals
    ) internal view returns (uint256) {
        uint256 px = _usdPrice(tokenFeed);
        uint256 value = _tokenValue(px, pu);
        return (amount * value * (10 ** uint256(uDecimals))) / (10 ** uint256(tDecimals)) / 1e18;
    }

    function _mintAndApprove(MockERC20 token, address user, uint256 amount) internal {
        token.mint(user, amount);
        vm.prank(user);
        token.approve(address(vault), amount);
    }

    function _deployProxyAdmin() internal returns (VaultProxyAdmin admin) {
        admin = VaultProxyAdmin(
            address(
                new TransparentUpgradeableProxy(
                    address(new VaultProxyAdmin()),
                    address(this),
                    abi.encodeCall(VaultProxyAdmin.initialize, (address(this)))
                )
            )
        );
    }
}

contract VaultInitTest is VaultTest {
    function test_initialize_setsUnderlyingAndEmitsEvent() public {
        MockChainlinkPriceFeed badFeed = new MockChainlinkPriceFeed(0, 1e8);
        TokenizedVault impl = new TokenizedVault();
        VaultProxyAdmin admin = _deployProxyAdmin();
        ProxyFactory f = _deployProxyFactory(address(impl), address(admin));
        bytes memory initData = abi.encodeCall(
            TokenizedVault.initialize, (address(this), address(usdc), "AV", "AV", address(feedUsdc), 3600, 0, 0)
        );
        vm.expectEmit(true, true, true, true);
        emit TokenizedVault.vaultInitialized(address(usdc));
        address proxy = f.deployProxy(SALT, initData);
        vault = TokenizedVault(payable(proxy));
        assertEq(address(vault.underlyingAsset()), address(usdc));
        assertEq(vault.underlyingDecimals(), 6);
        assertEq(vault.asset(), address(usdc));
        assertEq(vault.decimals(), 6);
        assertEq(vault.withdrawalTimelock(), 3600);
        assertEq(vault.owner(), address(this));
    }

    function test_initialize_revertsForInvalidDecimals(uint8 d) public {
        vm.assume(d != 6 && d != 8 && d != 18);
        MockERC20 token = new MockERC20("X", "X", d);
        TokenizedVault impl = new TokenizedVault();
        VaultProxyAdmin admin = _deployProxyAdmin();
        ProxyFactory f = _deployProxyFactory(address(impl), address(admin));
        bytes memory initData = abi.encodeCall(
            TokenizedVault.initialize, (address(this), address(token), "AV", "AV", address(feedUsdc), 0, 0, 0)
        );
        vm.expectRevert();
        f.deployProxy(SALT, initData);
    }

    function test_initialize_cannotBeCalledTwice() public {
        vault = _deployVault(usdc, feedUsdc, 0);
        vm.expectRevert();
        vault.initialize(address(this), address(usdc), "AV", "AV", address(feedUsdc), 0, 0, 0);
    }

    function test_initialize_revertsForInvalidErc20Underlying() public {
        TokenizedVault impl = new TokenizedVault();
        VaultProxyAdmin admin = _deployProxyAdmin();
        ProxyFactory f = _deployProxyFactory(address(impl), address(admin));
        bytes memory initData = abi.encodeCall(
            TokenizedVault.initialize, (address(this), address(feedUsdc), "AV", "AV", address(feedUsdc), 0, 0, 0)
        );
        vm.expectRevert(abi.encodeWithSelector(TokenizedVault.VaultInvalidERC20.selector, address(feedUsdc)));
        f.deployProxy(SALT, initData);
    }

    function test_initialize_revertsForZeroUnderlying() public {
        TokenizedVault impl = new TokenizedVault();
        VaultProxyAdmin admin = _deployProxyAdmin();
        ProxyFactory f = _deployProxyFactory(address(impl), address(admin));
        bytes memory initData =
            abi.encodeCall(TokenizedVault.initialize, (address(this), address(0), "AV", "AV", address(feedUsdc), 0, 0, 0));
        vm.expectRevert(abi.encodeWithSelector(TokenizedVault.VaultZeroAddress.selector, address(0)));
        f.deployProxy(SALT, initData);
    }

    function test_initialize_revertsForZeroPriceFeed() public {
        TokenizedVault impl = new TokenizedVault();
        VaultProxyAdmin admin = _deployProxyAdmin();
        ProxyFactory f = _deployProxyFactory(address(impl), address(admin));
        bytes memory initData =
            abi.encodeCall(TokenizedVault.initialize, (address(this), address(usdc), "AV", "AV", address(0), 0, 0, 0));
        vm.expectRevert(abi.encodeWithSelector(TokenizedVault.VaultZeroAddress.selector, address(0)));
        f.deployProxy(SALT, initData);
    }

    function test_initialize_setsMinimumDepositAmount() public {
        TokenizedVault impl = new TokenizedVault();
        VaultProxyAdmin admin = _deployProxyAdmin();
        ProxyFactory f = _deployProxyFactory(address(impl), address(admin));
        bytes memory initData = abi.encodeCall(
            TokenizedVault.initialize, (address(this), address(usdc), "AV", "AV", address(feedUsdc), 0, 100e6, 0)
        );
        address proxy = f.deployProxy(SALT, initData);
        vault = TokenizedVault(payable(proxy));
        assertEq(vault.minimumDepositAmount(), 100e6);
    }
}

contract VaultEnableDisableTest is VaultTest {
    function setUp() public override {
        super.setUp();
        vault = _deployVault(usdc, feedUsdc, 0);
    }

    function test_enableToken_success() public {
        vm.expectEmit(true, true, true, true);
        emit TokenizedVault.TokenStatusChanged(address(dai), true);
        vault.enableToken(address(dai), address(feedDai), 18);

        assertTrue(vault.isTokenEnabled(address(dai)));
        (address feed, uint8 decimals) = vault.tokenPriceFeeds(address(dai));
        assertEq(feed, address(feedDai));
        assertEq(decimals, 18);
        assertEq(vault.getEnabledTokens().length, 1);
        assertEq(vault.getEnabledTokens()[0], address(dai));
        assertEq(vault.getTokenValue(address(dai)), 1e18);
    }

    function test_enableToken_revertsWhenAlreadyEnabled() public {
        _enable(address(dai), feedDai, 18);
        vm.expectRevert(abi.encodeWithSelector(TokenizedVault.VaultAlreadyEnabled.selector, address(dai)));
        vault.enableToken(address(dai), address(feedDai), 18);
    }

    function test_enableToken_revertsForUnderlying() public {
        vm.expectRevert(abi.encodeWithSelector(TokenizedVault.VaultCannotEnableUnderlying.selector, address(usdc)));
        vault.enableToken(address(usdc), address(feedUsdc), 6);
    }

    function test_enableToken_revertsForInvalidDecimals(uint8 d) public {
        vm.assume(d != 6 && d != 8 && d != 18);
        vm.expectRevert(abi.encodeWithSelector(TokenizedVault.VaultUnsupportedDecimals.selector, d));
        vault.enableToken(address(dai), address(feedDai), d);
    }

    function test_enableToken_revertsForInvalidErc20() public {
        vm.expectRevert(abi.encodeWithSelector(TokenizedVault.VaultInvalidERC20.selector, address(feedDai)));
        vault.enableToken(address(feedDai), address(feedDai), 18);
    }

    function test_enableToken_revertsForZeroPriceFeed() public {
        vm.expectRevert(abi.encodeWithSelector(TokenizedVault.VaultInvalidPriceFeed.selector, address(0)));
        vault.enableToken(address(dai), address(0), 18);
    }

    function test_enableToken_revertsForZeroToken() public {
        vm.expectRevert(abi.encodeWithSelector(TokenizedVault.VaultZeroAddress.selector, address(0)));
        vault.enableToken(address(0), address(feedDai), 18);
    }

    function test_disableToken_revertsForZeroToken() public {
        vm.expectRevert(abi.encodeWithSelector(TokenizedVault.VaultZeroAddress.selector, address(0)));
        vault.disableToken(address(0));
    }

    function test_enableToken_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.enableToken(address(dai), address(feedDai), 18);
    }

    function test_disableToken_success() public {
        _enable(address(dai), feedDai, 18);
        _enable(address(usdt), feedUsdt, 6);

        vm.expectEmit(true, true, true, true);
        emit TokenizedVault.TokenStatusChanged(address(dai), false);
        vault.disableToken(address(dai));

        assertFalse(vault.isTokenEnabled(address(dai)));
        assertTrue(vault.isTokenEnabled(address(usdt)));
        (address feed, uint8 decimals) = vault.tokenPriceFeeds(address(dai));
        assertEq(feed, address(0));
        assertEq(decimals, 0);
        address[] memory tokens = vault.getEnabledTokens();
        assertEq(tokens.length, 1);
        assertEq(tokens[0], address(usdt));
    }

    function test_disableToken_revertsWhenNotEnabled() public {
        vm.expectRevert(abi.encodeWithSelector(TokenizedVault.VaultNotEnabled.selector, address(dai)));
        vault.disableToken(address(dai));
    }

    function test_disableToken_revertsForUnderlying() public {
        vm.expectRevert(abi.encodeWithSelector(TokenizedVault.VaultCannotDisableUnderlying.selector, address(usdc)));
        vault.disableToken(address(usdc));
    }

    function test_disableToken_onlyOwner() public {
        _enable(address(dai), feedDai, 18);
        vm.prank(alice);
        vm.expectRevert();
        vault.disableToken(address(dai));
    }

    function test_getTokenValue_revertsWhenNotEnabled() public {
        vm.expectRevert(abi.encodeWithSelector(TokenizedVault.VaultNotEnabled.selector, address(dai)));
        vault.getTokenValue(address(dai));
    }

    function test_getTokenValue_revertsForNonPositiveAnswer() public {
        vault.enableToken(address(dai), address(feedDai), 18);
        feedDai.setAnswer(0);
        vm.expectRevert(abi.encodeWithSelector(TokenizedVault.VaultInvalidPriceFeed.selector, address(feedDai)));
        vault.getTokenValue(address(dai));
    }

    function test_getTokenValue_revertsForStaleTokenFeed() public {
        vault.enableToken(address(dai), address(feedDai), 18);
        feedDai.setUpdatedAt(0);
        vm.expectRevert(abi.encodeWithSelector(TokenizedVault.VaultStalePriceFeed.selector, address(feedDai)));
        vault.getTokenValue(address(dai));
    }

    function test_getTokenValue_revertsForStaleUnderlyingFeed() public {
        vault.enableToken(address(dai), address(feedDai), 18);
        feedUsdc.setUpdatedAt(0);
        vm.expectRevert(abi.encodeWithSelector(TokenizedVault.VaultStalePriceFeed.selector, address(feedUsdc)));
        vault.getTokenValue(address(dai));
    }

    function test_getTokenValue_revertsForTokenFeedRoundMismatch() public {
        vault.enableToken(address(dai), address(feedDai), 18);
        feedDai.setAnsweredInRound(0);
        vm.expectRevert(abi.encodeWithSelector(TokenizedVault.VaultInvalidPriceFeedRound.selector, address(feedDai)));
        vault.getTokenValue(address(dai));
    }

    function test_getTokenValue_revertsForUnderlyingFeedRoundMismatch() public {
        vault.enableToken(address(dai), address(feedDai), 18);
        feedUsdc.setAnsweredInRound(0);
        vm.expectRevert(abi.encodeWithSelector(TokenizedVault.VaultInvalidPriceFeedRound.selector, address(feedUsdc)));
        vault.getTokenValue(address(dai));
    }

    function test_deposit_revertsWhenUnderlyingFeedStale() public {
        vault.enableToken(address(dai), address(feedDai), 18);
        _mintAndApprove(dai, alice, 1000e18);
        feedUsdc.setUpdatedAt(0);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(TokenizedVault.VaultStalePriceFeed.selector, address(feedUsdc)));
        vault.deposit(address(dai), 100e18, alice);
    }

    function test_getTokenValue_passesWhenFreshWithinHeartbeat() public {
        vault.enableToken(address(dai), address(feedDai), 18);
        assertEq(vault.getTokenValue(address(dai)), 1e18);
    }
}

contract VaultReentrancyTest is VaultTest {
    function setUp() public override {
        super.setUp();
        vault = _deployVault(usdc, feedUsdc, 0);
    }

    function test_deposit_revertsOnReentrantCall() public {
        MockReentrantToken reentrant = new MockReentrantToken(address(vault));
        vault.enableToken(address(reentrant), address(feedUsdc), 18);
        reentrant.mint(alice, 1000e18);
        vm.prank(alice);
        reentrant.approve(address(vault), 1000e18);
        reentrant.setReenter(true);
        vm.prank(alice);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        vault.deposit(address(reentrant), 1000e18, alice);
    }
}

contract VaultErc4626Test is VaultTest {
    function setUp() public override {
        super.setUp();
        vault = _deployVault(usdc, feedUsdc, 0);
        _enable(address(dai), feedDai, 18);
        _mintAndApprove(dai, alice, 1000e18);
    }

    function test_math_emptyVault() public view {
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.convertToShares(100e6), 100e6);
        assertEq(vault.convertToAssets(100e6), 100e6);
        assertEq(vault.previewDeposit(100e6), 100e6);
        assertEq(vault.previewMint(100e6), 100e6);
        assertEq(vault.previewWithdraw(100e6), 100e6);
        assertEq(vault.previewRedeem(100e6), 100e6);
        assertEq(vault.maxDeposit(alice), type(uint256).max);
        assertEq(vault.maxMint(alice), type(uint256).max);
        assertEq(vault.maxRedeem(alice), 0);
        assertEq(vault.maxWithdraw(alice), 0);
    }

    function test_deposit_singleDepositMintsOneToOne() public {
        uint256 assets = _toUnderlying(100e18, feedDai, 18, _usdPrice(feedUsdc), 6);
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IERC4626.Deposit(alice, alice, assets, assets);
        uint256 shares = vault.deposit(address(dai), 100e18, alice);

        assertEq(shares, assets);
        assertEq(vault.balanceOf(alice), shares);
        assertEq(vault.totalSupply(), shares);
        assertEq(vault.totalAssets(), assets);
        assertEq(dai.balanceOf(address(vault)), 100e18);
        assertEq(usdc.balanceOf(address(vault)), 0);
        (uint256 amount, uint256 timestamp) = vault.deposits(alice);
        assertEq(amount, assets);
        assertEq(timestamp, block.timestamp);
    }

    function test_deposit_multipleUsersMaintainRate() public {
        _mintAndApprove(usdc, bob, 1000e6);

        vm.prank(alice);
        uint256 aShares = vault.deposit(address(dai), 100e18, alice);
        uint256 aAssets = _toUnderlying(100e18, feedDai, 18, _usdPrice(feedUsdc), 6);
        vm.prank(bob);
        uint256 bShares = vault.deposit(address(usdc), 50e6, bob);

        assertEq(aShares, aAssets);
        assertEq(bShares, 50e6);
        assertEq(aShares + bShares, vault.totalSupply());
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), aAssets);
        assertEq(vault.convertToAssets(vault.balanceOf(bob)), 50e6);
    }

    function test_deposit_revertsWhenTokenNotEnabled() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(TokenizedVault.VaultNotEnabled.selector, address(usdt)));
        vault.deposit(address(usdt), 100e6, alice);
    }

    function test_deposit_revertsForZeroToken() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(TokenizedVault.VaultZeroAddress.selector, address(0)));
        vault.deposit(address(0), 100e6, alice);
    }

    function test_deposit_revertsWhenZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(TokenizedVault.VaultZeroAmount.selector);
        vault.deposit(address(dai), 0, alice);
    }

    function test_deposit_revertsWhenMintsZeroShares() public {
        _mintAndApprove(dai, alice, 1000e18);
        vm.prank(alice);
        vm.expectRevert(TokenizedVault.VaultZeroShares.selector);
        vault.deposit(address(dai), 1, alice); // 1 wei DAI rounds to 0 underlying assets -> 0 shares
    }

    function test_deposit_revertsWithoutAllowance() public {
        dai.mint(bob, 1000e18);
        vm.prank(bob);
        vm.expectRevert();
        vault.deposit(address(dai), 1e18, bob);
    }

    function test_burnNotPossibleWithoutDeposit() public {
        vm.prank(alice);
        vm.expectRevert(); // insufficient shares
        vault.redeem(1, alice, alice);
    }

    function test_conversionFunctionsStable() public {
        _mintAndApprove(usdc, bob, 1000e6);
        vm.prank(alice);
        vault.deposit(address(dai), 100e18, alice);

        vm.prank(bob);
        vault.deposit(address(usdc), 50e6, bob);

        uint256 shares = vault.convertToShares(25e6);
        uint256 assets = vault.convertToAssets(shares);
        assertApproxEqAbs(assets, 25e6, 1);
        assertEq(vault.previewRedeem(shares), assets);
        assertEq(vault.previewWithdraw(assets), vault.convertToShares(assets));
        assertEq(vault.previewDeposit(25e6), vault.convertToShares(25e6));
        assertEq(vault.previewMint(shares), vault.convertToAssets(shares));
    }
}

contract VaultDepositPairingsTest is VaultTest {
    function _depositAndCheck(
        MockERC20 underlying,
        MockChainlinkPriceFeed underlyingFeed,
        uint8 uDecimals,
        MockERC20 enabled,
        MockChainlinkPriceFeed enabledFeed,
        uint8 tDecimals,
        uint256 depositAmount,
        uint256 expectedSharesOffset
    ) internal {
        vault = _deployVault(underlying, underlyingFeed, 0);
        _enable(address(enabled), enabledFeed, tDecimals);
        _mintAndApprove(enabled, alice, depositAmount * 2);

        uint256 pu = _usdPrice(underlyingFeed);
        uint256 assets = _toUnderlying(depositAmount, enabledFeed, tDecimals, pu, uDecimals);
        vm.prank(alice);
        uint256 shares = vault.deposit(address(enabled), depositAmount, alice);
        assertEq(shares, assets + expectedSharesOffset, "shares");
        assertEq(vault.balanceOf(alice), shares);
        assertTrue(assets > 0);
        assertEq(vault.getTokenValue(address(enabled)) > 0, true);
    }

    function test_usdcUnderlyingDaiEnabled() public {
        _depositAndCheck(usdc, feedUsdc, 6, dai, feedDai, 18, 100e18, 0);
    }

    function test_usdcUnderlyingUsdtEnabled() public {
        _depositAndCheck(usdc, feedUsdc, 6, usdt, feedUsdt, 6, 100e6, 0);
    }

    function test_usdcUnderlyingWbtcEnabled() public {
        _depositAndCheck(usdc, feedUsdc, 6, wbtc, feedWbtc, 8, 1e8, 0);
    }

    function test_usdcUnderlyingWethEnabled() public {
        _depositAndCheck(usdc, feedUsdc, 6, weth, feedWeth, 18, 1e18, 0);
    }

    function test_wbtcUnderlyingUsdcEnabled() public {
        _depositAndCheck(wbtc, feedWbtc, 8, usdc, feedUsdc, 6, 100e6, 0);
    }

    function test_wbtcUnderlyingWethEnabled() public {
        _depositAndCheck(wbtc, feedWbtc, 8, weth, feedWeth, 18, 1e18, 0);
    }

    function test_wethUnderlyingWbtcEnabled() public {
        _depositAndCheck(weth, feedWeth, 18, wbtc, feedWbtc, 8, 1e8, 0);
    }

    function test_wethUnderlyingUsdcEnabled() public {
        _depositAndCheck(weth, feedWeth, 18, usdc, feedUsdc, 6, 100e6, 0);
    }

    function test_wethUnderlyingUsdtEnabled() public {
        _depositAndCheck(weth, feedWeth, 18, usdt, feedUsdt, 6, 100e6, 0);
    }

    function test_getTokenValueMatchesPriceRatio() public {
        vault = _deployVault(usdc, feedUsdc, 0);
        _enable(address(dai), feedDai, 18);
        _enable(address(wbtc), feedWbtc, 8);
        assertEq(vault.getTokenValue(address(dai)), 1e18);
        // 30,000 USD per WBTC
        assertEq(vault.getTokenValue(address(wbtc)), 30_000e18);
        vault = _deployVault(weth, feedWeth, 0);
        _enable(address(wbtc), feedWbtc, 8);
        // 30,000/2,000 = 15 WBTC per WETH
        assertEq(vault.getTokenValue(address(wbtc)), 15e18);
    }

    function test_feedChangeUpdatesValuation() public {
        vault = _deployVault(usdc, feedUsdc, 0);
        _enable(address(dai), feedDai, 18);
        feedDai.setAnswer(2e8);
        assertEq(vault.getTokenValue(address(dai)), 2e18);
    }

    function test_totalAssetsIncludesEnabledTokenBalances() public {
        vault = _deployVault(usdc, feedUsdc, 0);
        _enable(address(dai), feedDai, 18);
        _mintAndApprove(dai, alice, 100e18);
        vm.prank(alice);
        vault.deposit(address(dai), 100e18, alice);
        // send extra DAI directly to the vault to inflate holdings
        dai.mint(address(vault), 50e18);
        assertEq(vault.totalAssets(), _toUnderlying(150e18, feedDai, 18, _usdPrice(feedUsdc), 6));
    }
}

contract VaultWithdrawalTest is VaultTest {
    function setUp() public override {
        super.setUp();
        vault = _deployVault(usdc, feedUsdc, 0);
        _enable(address(dai), feedDai, 18);
        // Seed the vault with underlying reserves (carol deposits the underlying directly, at
        // identity value; the underlying is never registered as an enabled token).
        _mintAndApprove(usdc, carol, 10_000e6);
        vm.prank(carol);
        vault.deposit(address(usdc), 10_000e6, carol);
        _mintAndApprove(dai, alice, 1000e18);
    }

    function _depositAlice(uint256 daiAmount) internal returns (uint256 shares) {
        vm.prank(alice);
        shares = vault.deposit(address(dai), daiAmount, alice);
    }

    function test_redeem_paysInUnderlyingOnly() public {
        uint256 assets = _toUnderlying(100e18, feedDai, 18, _usdPrice(feedUsdc), 6);
        uint256 shares = _depositAlice(100e18);
        uint256 vaultDaiBefore = dai.balanceOf(address(vault));
        uint256 vaultUsdcBefore = usdc.balanceOf(address(vault));

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IERC4626.Withdraw(alice, alice, alice, assets, shares);
        uint256 received = vault.redeem(shares, alice, alice);

        assertEq(received, assets);
        assertEq(usdc.balanceOf(alice), assets, "paid in underlying");
        assertEq(vault.balanceOf(alice), 0);
        assertEq(dai.balanceOf(address(vault)), vaultDaiBefore, "enabled token holdings unchanged");
        assertEq(usdc.balanceOf(address(vault)), vaultUsdcBefore - assets, "underlying paid out");
    }

    function test_withdraw_paysInUnderlyingOnly() public {
        uint256 assets = _toUnderlying(100e18, feedDai, 18, _usdPrice(feedUsdc), 6);
        _depositAlice(100e18);

        vm.prank(alice);
        uint256 shares = vault.withdraw(assets, alice, alice);

        assertEq(shares, assets);
        assertEq(usdc.balanceOf(alice), assets);
        assertEq(dai.balanceOf(address(vault)), 100e18, "enabled token holdings unchanged");
        assertEq(vault.balanceOf(alice), 0);
    }

    function test_redeem_partial() public {
        _depositAlice(100e18);
        uint256 totalShares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.redeem(totalShares / 2, alice, alice);
        assertEq(vault.balanceOf(alice), totalShares - totalShares / 2);
        assertTrue(usdc.balanceOf(alice) > 0);
    }

    function test_redeem_revertsWhenInsufficientUnderlying() public {
        _depositAlice(100e18);
        // carol drains all of her underlying reserves from the vault
        uint256 carolMax = vault.maxWithdraw(carol);
        vm.prank(carol);
        vault.withdraw(carolMax, carol, carol);
        assertEq(usdc.balanceOf(address(vault)), 0);
        // the vault now holds only the enabled token (DAI) but must pay in underlying
        uint256 aliceShares = vault.balanceOf(alice);
        vm.prank(alice);
        vm.expectRevert(TokenizedVault.VaultInsufficientUnderlying.selector);
        vault.redeem(aliceShares, alice, alice);
    }

    function test_withdraw_revertsWhenInsufficientUnderlying() public {
        _depositAlice(100e18);
        // carol drains all of her underlying reserves from the vault
        uint256 carolMax = vault.maxWithdraw(carol);
        vm.prank(carol);
        vault.withdraw(carolMax, carol, carol);
        assertEq(usdc.balanceOf(address(vault)), 0);
        // the vault now holds only the enabled token (DAI) but must pay in underlying
        vm.prank(alice);
        vm.expectRevert(TokenizedVault.VaultInsufficientUnderlying.selector);
        vault.withdraw(10e6, alice, alice);
    }

    function test_redeem_revertsWhenNoShares() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.redeem(1, alice, alice);
    }

    function test_redeem_revertsForZeroReceiver() public {
        uint256 shares = _depositAlice(100e18);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(TokenizedVault.VaultZeroAddress.selector, address(0)));
        vault.redeem(shares, address(0), alice);
    }

    function test_withdraw_revertsForZeroReceiver() public {
        _depositAlice(100e18);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(TokenizedVault.VaultZeroAddress.selector, address(0)));
        vault.withdraw(10e6, address(0), alice);
    }
}

contract VaultWithdrawalTimelockTest is VaultTest {
    function _deployTimelocked(uint256 timelock) internal returns (TokenizedVault v) {
        v = _deployVault(usdc, feedUsdc, timelock);
        vault = v;
        v.enableToken(address(dai), address(feedDai), 18);
        // Seed underlying reserves and set the deposit timestamps in motion. Carol deposits the
        // underlying directly (identity value), which needs no enabling.
        _mintAndApprove(usdc, carol, 10_000e6);
        vm.prank(carol);
        v.deposit(address(usdc), 10_000e6, carol);
        _mintAndApprove(dai, alice, 1000e18);
        vm.prank(alice);
        v.deposit(address(dai), 100e18, alice);
    }

    function test_timelockZero_withdrawImmediately() public {
        TokenizedVault v = _deployTimelocked(0);
        uint256 shares = v.balanceOf(alice);
        vm.prank(alice);
        v.redeem(shares, alice, alice);
        assertEq(v.balanceOf(alice), 0);
    }

    function test_timelockOneHour_cannotWithdrawBefore() public {
        TokenizedVault v = _deployTimelocked(1 hours);
        uint256 shares = v.balanceOf(alice);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(TokenizedVault.VaultTimelockNotExpired.selector, block.timestamp + 1 hours)
        );
        v.redeem(shares, alice, alice);
    }

    function test_timelockOneHour_canWithdrawAfter() public {
        TokenizedVault v = _deployTimelocked(1 hours);
        uint256 shares = v.balanceOf(alice);
        vm.warp(block.timestamp + 1 hours);
        vm.prank(alice);
        v.redeem(shares, alice, alice);
        assertEq(v.balanceOf(alice), 0);
    }

    function test_timelockOneHour_canWithdrawAfterOneSecondShort() public {
        TokenizedVault v = _deployTimelocked(1 hours);
        uint256 shares = v.balanceOf(alice);
        (, uint256 depositedAt) = v.deposits(alice);
        vm.warp(block.timestamp + 1 hours - 1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(TokenizedVault.VaultTimelockNotExpired.selector, depositedAt + 1 hours));
        v.redeem(shares, alice, alice);
    }

    function test_maxRedeemAndMaxWithdraw_zeroWhileTimelocked() public {
        TokenizedVault v = _deployTimelocked(1 hours);
        assertGt(v.balanceOf(alice), 0);
        assertEq(v.maxRedeem(alice), 0);
        assertEq(v.maxWithdraw(alice), 0);
    }

    function test_maxRedeemAndMaxWithdraw_positiveAfterTimelock() public {
        TokenizedVault v = _deployTimelocked(1 hours);
        uint256 shares = v.balanceOf(alice);
        assertGt(shares, 0);
        assertEq(v.maxRedeem(alice), 0, "locked before expiry");
        vm.warp(block.timestamp + 1 hours);
        assertEq(v.maxRedeem(alice), shares, "unlocked after expiry");
        assertEq(v.maxWithdraw(alice), v.previewRedeem(shares));
    }

    function test_maxRedeemAndMaxWithdraw_positiveWhenTimelockZero() public {
        TokenizedVault v = _deployTimelocked(0);
        uint256 shares = v.balanceOf(alice);
        assertEq(v.maxRedeem(alice), shares);
        assertEq(v.maxWithdraw(alice), v.previewRedeem(shares));
    }

    function test_maxWithdraw_dependsOnOwnerTimelock_notCaller() public {
        TokenizedVault v = _deployTimelocked(1 hours);
        uint256 shares = v.balanceOf(alice);
        assertGt(shares, 0);
        vm.warp(block.timestamp + 1 hours); // alice and carol are now unlocked
        // re-lock carol only, so her caller state differs from alice's
        _mintAndApprove(usdc, carol, 100e6);
        vm.prank(carol);
        v.deposit(address(usdc), 100e6, carol);
        assertEq(v.maxWithdraw(carol), 0, "carol is still locked");
        vm.prank(alice);
        uint256 forAlice = v.maxWithdraw(alice);
        assertEq(forAlice, v.convertToAssets(shares), "maxWithdraw(alice) when unlocked");
        vm.prank(carol); // locked caller
        assertEq(v.maxWithdraw(alice), forAlice, "caller's timelock must not affect maxWithdraw(alice)");
    }

    function test_previewRedeemAndPreviewWithdraw_zeroWhileTimelocked() public {
        TokenizedVault v = _deployTimelocked(1 hours);
        uint256 shares = v.balanceOf(alice);
        assertGt(shares, 0);
        vm.prank(alice);
        assertEq(v.previewRedeem(shares), 0, "previewRedeem zero while locked");
        vm.prank(alice);
        assertEq(v.previewWithdraw(10e6), 0, "previewWithdraw zero while locked");
    }

    function test_previewRedeemAndPreviewWithdraw_positiveAfterTimelock() public {
        TokenizedVault v = _deployTimelocked(1 hours);
        uint256 shares = v.balanceOf(alice);
        assertGt(shares, 0);
        vm.warp(block.timestamp + 1 hours);
        vm.prank(alice);
        assertEq(v.previewRedeem(shares), v.convertToAssets(shares), "previewRedeem positive after expiry");
        vm.prank(alice);
        assertGt(v.previewWithdraw(10e6), 0, "previewWithdraw positive after expiry");
    }

    function test_previewRedeem_positiveWhenTimelockZero() public {
        TokenizedVault v = _deployTimelocked(0);
        uint256 shares = v.balanceOf(alice);
        vm.prank(alice);
        assertEq(v.previewRedeem(shares), v.convertToAssets(shares));
        vm.prank(alice);
        assertGt(v.previewWithdraw(10e6), 0);
    }

    function test_timelockOneDay_cannotWithdrawBefore() public {
        TokenizedVault v = _deployTimelocked(24 hours);
        uint256 shares = v.balanceOf(alice);
        (, uint256 depositedAt) = v.deposits(alice);
        vm.warp(block.timestamp + 24 hours - 1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(TokenizedVault.VaultTimelockNotExpired.selector, depositedAt + 24 hours));
        v.withdraw(uint256(10e6), alice, alice);
        assertTrue(shares > 0);
    }

    function test_timelockOneDay_canWithdrawAfter() public {
        TokenizedVault v = _deployTimelocked(24 hours);
        uint256 shares = v.balanceOf(alice);
        vm.warp(block.timestamp + 24 hours);
        vm.prank(alice);
        v.withdraw(uint256(10e6), alice, alice);
        assertTrue(shares > 0);
        assertLt(v.balanceOf(alice), shares);
    }

    function test_setWithdrawalTimelock_owner() public {
        TokenizedVault v = _deployVault(usdc, feedUsdc, 0);
        vm.expectEmit(true, true, true, true);
        emit TokenizedVault.WithdrawalTimelockChanged(48 hours);
        v.setWithdrawalTimelock(48 hours);
        assertEq(v.withdrawalTimelock(), 48 hours);
    }

    function test_setWithdrawalTimelock_onlyOwner() public {
        TokenizedVault v = _deployVault(usdc, feedUsdc, 0);
        vm.prank(alice);
        vm.expectRevert();
        v.setWithdrawalTimelock(1);
    }
}

contract VaultReceiptTokenTest is VaultTest {
    function setUp() public override {
        super.setUp();
        vault = _deployVault(usdc, feedUsdc, 0);
        _mintAndApprove(usdc, alice, 100e6);
        vm.prank(alice);
        vault.deposit(address(usdc), 100e6, alice);
    }

    function test_transfer_reverts() public {
        vm.prank(alice);
        vm.expectRevert(TokenizedVault.VaultReceiptTokenNonTransferable.selector);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        vault.transfer(bob, 1);
    }

    function test_transferFrom_reverts() public {
        vm.prank(alice);
        vault.approve(bob, 10);
        vm.prank(bob);
        vm.expectRevert(TokenizedVault.VaultReceiptTokenNonTransferable.selector);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        vault.transferFrom(alice, carol, 1);
    }

    function test_sharesTokenMetadata() public view {
        assertEq(vault.name(), "Armada Vault Shares");
        assertEq(vault.symbol(), "AVS");
        assertEq(vault.decimals(), 6);
    }

    function test_sharesAreMintedAndBurned() public {
        uint256 shares = vault.balanceOf(alice);
        assertEq(shares, 100e6);
        vm.prank(alice);
        vault.redeem(shares, alice, alice);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.totalSupply(), 0);
    }
}

contract VaultAdminUpgradeTest is VaultTest {
    function test_proxyAdmin_twoStepOwnership() public {
        proxyAdmin.transferOwnership(alice);
        assertEq(proxyAdmin.pendingOwner(), alice);
        assertEq(proxyAdmin.owner(), address(this));
        vm.prank(alice);
        proxyAdmin.acceptOwnership();
        assertEq(proxyAdmin.owner(), alice);
    }

    function test_upgrade_allowedByAdminOwner() public {
        vault = _deployVault(usdc, feedUsdc, 0);
        TokenizedVault implementationV2 = new TokenizedVault();
        vm.expectEmit(true, true, true, true);
        emit VaultProxyAdmin.Upgraded(address(vault), address(implementationV2));
        proxyAdmin.upgrade(address(vault), address(implementationV2));
        assertEq(proxyAdmin.getProxyImplementation(address(vault)), address(implementationV2));
    }

    function test_upgrade_onlyAdminOwner() public {
        vault = _deployVault(usdc, feedUsdc, 0);
        TokenizedVault implementationV2 = new TokenizedVault();
        vm.prank(alice);
        vm.expectRevert();
        proxyAdmin.upgrade(address(vault), address(implementationV2));
    }

    function test_upgrade_rejectsNonContractImplementation() public {
        vault = _deployVault(usdc, feedUsdc, 0);
        vm.expectRevert(abi.encodeWithSelector(VaultProxyAdmin.ProxyAdminNotAContract.selector, address(0xBEEF)));
        proxyAdmin.upgrade(address(vault), address(0xBEEF));
    }

    function test_getProxyImplementationAndAdmin() public {
        vault = _deployVault(usdc, feedUsdc, 0);
        assertEq(proxyAdmin.getProxyImplementation(address(vault)), address(implementation));
        assertEq(proxyAdmin.getProxyAdmin(address(vault)), address(proxyAdmin));
    }

    function test_upgradeAndGetters_rejectNonContractProxy() public {
        vm.expectRevert(
            abi.encodeWithSelector(VaultProxyAdmin.ProxyAdminNotAContract.selector, address(implementation))
        );
        proxyAdmin.upgrade(address(0xBEEF), address(implementation));
        vm.expectRevert(abi.encodeWithSelector(VaultProxyAdmin.ProxyAdminNotAContract.selector, address(0xBEEF)));
        proxyAdmin.getProxyImplementation(address(0xBEEF));
        vm.expectRevert(abi.encodeWithSelector(VaultProxyAdmin.ProxyAdminNotAContract.selector, address(0xBEEF)));
        proxyAdmin.getProxyAdmin(address(0xBEEF));
    }

    function test_transparentProxy_adminCannotCallImplFunctions() public {
        vault = _deployVault(usdc, feedUsdc, 0);
        vm.prank(address(proxyAdmin));
        (bool ok, bytes memory ret) = address(vault).call(abi.encodeCall(TokenizedVault.decimals, ()));
        assertFalse(ok);
        // casting to 'bytes4' is safe because revert reason is a 4-byte selector
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(bytes4(ret), VaultTransparentProxy.ProxyDeniedAdminAccess.selector);
    }

    function test_transparentProxy_nonAdminCallsForwarded() public {
        vault = _deployVault(usdc, feedUsdc, 0);
        assertEq(vault.decimals(), 6);
    }
}

contract ProxyFactoryTest is VaultTest {
    function test_deployProxy_emitsEventAndPredictsAddress() public {
        bytes memory initData =
            abi.encodeCall(TokenizedVault.initialize, (address(this), address(usdc), "AV", "AV", address(feedUsdc), 0, 0, 0));
        address predicted = factory.predictProxyAddress(SALT, initData);
        vm.expectEmit(true, true, true, true);
        emit ProxyFactory.ProxyDeployed(predicted, address(implementation), address(proxyAdmin));
        address proxy = factory.deployProxy(SALT, initData);
        assertEq(proxy, predicted);
        assertEq(proxyAdmin.getProxyAdmin(proxy), address(proxyAdmin));
    }

    function test_deployProxy_uniqueSalt() public {
        bytes memory initData =
            abi.encodeCall(TokenizedVault.initialize, (address(this), address(usdc), "AV", "AV", address(feedUsdc), 0, 0, 0));
        address proxy1 = factory.deployProxy(SALT, initData);
        address proxy2 = factory.deployProxy(keccak256("other"), initData);
        assertTrue(proxy1 != proxy2);
    }

    function test_deployProxy_sameSaltReverts() public {
        bytes memory initData =
            abi.encodeCall(TokenizedVault.initialize, (address(this), address(usdc), "AV", "AV", address(feedUsdc), 0, 0, 0));
        factory.deployProxy(SALT, initData);
        vm.expectRevert();
        factory.deployProxy(SALT, initData);
    }

    function test_predictProxyAddress_defined() public view {
        bytes memory initData =
            abi.encodeCall(TokenizedVault.initialize, (address(this), address(usdc), "AV", "AV", address(feedUsdc), 0, 0, 0));
        assertTrue(factory.predictProxyAddress(SALT, initData) != address(0));
    }

    function test_initialize_revertsForNonContractImplementation() public {
        ProxyFactory impl = new ProxyFactory();
        bytes memory initData =
            abi.encodeCall(ProxyFactory.initialize, (address(this), address(0xBEEF), address(proxyAdmin)));
        vm.expectRevert(
            abi.encodeWithSelector(ProxyFactory.ProxyFactoryInvalidImplementation.selector, address(0xBEEF))
        );
        new TransparentUpgradeableProxy(address(impl), address(this), initData);
    }

    function test_initialize_revertsForNonContractAdmin() public {
        ProxyFactory impl = new ProxyFactory();
        bytes memory initData =
            abi.encodeCall(ProxyFactory.initialize, (address(this), address(implementation), address(0xBEEF)));
        vm.expectRevert(abi.encodeWithSelector(ProxyFactory.ProxyFactoryInvalidAdmin.selector, address(0xBEEF)));
        new TransparentUpgradeableProxy(address(impl), address(this), initData);
    }

    function test_initialize_revertsForZeroImplementation() public {
        ProxyFactory impl = new ProxyFactory();
        bytes memory initData =
            abi.encodeCall(ProxyFactory.initialize, (address(this), address(0), address(proxyAdmin)));
        vm.expectRevert(abi.encodeWithSelector(ProxyFactory.ProxyFactoryZeroAddress.selector, address(0)));
        new TransparentUpgradeableProxy(address(impl), address(this), initData);
    }

    function test_initialize_revertsForZeroAdmin() public {
        ProxyFactory impl = new ProxyFactory();
        bytes memory initData =
            abi.encodeCall(ProxyFactory.initialize, (address(this), address(implementation), address(0)));
        vm.expectRevert(abi.encodeWithSelector(ProxyFactory.ProxyFactoryZeroAddress.selector, address(0)));
        new TransparentUpgradeableProxy(address(impl), address(this), initData);
    }

    function test_initialize_cannotBeCalledTwice() public {
        vm.expectRevert();
        factory.initialize(address(this), address(implementation), address(proxyAdmin));
    }

    function test_initialize_twoStepOwnership() public {
        factory.transferOwnership(alice);
        assertEq(factory.pendingOwner(), alice);
        assertEq(factory.owner(), address(this));
        vm.prank(alice);
        factory.acceptOwnership();
        assertEq(factory.owner(), alice);
    }

    function test_deployProxy_onlyOwner() public {
        bytes memory initData =
            abi.encodeCall(TokenizedVault.initialize, (address(this), address(usdc), "AV", "AV", address(feedUsdc), 0, 0, 0));
        vm.prank(alice);
        vm.expectRevert();
        factory.deployProxy(SALT, initData);
    }

    function test_adminCanCallUpgradeToAndCallDirectly() public {
        bytes memory initData =
            abi.encodeCall(TokenizedVault.initialize, (address(this), address(usdc), "AV", "AV", address(feedUsdc), 0, 0, 0));
        TokenizedVault impl2 = new TokenizedVault();
        address proxy = factory.deployProxy(SALT, initData);
        vm.prank(address(proxyAdmin));
        IVaultTransparentProxy(proxy).upgradeToAndCall(address(impl2), "");
        assertEq(proxyAdmin.getProxyImplementation(proxy), address(impl2));
    }
}

contract VaultProxyDirectTest is VaultTest {
    function test_constructor_rejectsZeroAdmin() public {
        bytes memory initData =
            abi.encodeCall(TokenizedVault.initialize, (address(this), address(usdc), "AV", "AV", address(feedUsdc), 0, 0, 0));
        vm.expectRevert(abi.encodeWithSelector(VaultTransparentProxy.ProxyInvalidAdmin.selector, address(0)));
        new VaultTransparentProxy(address(implementation), address(0), initData);
    }
}

contract VaultEtherRejectTest is VaultTest {
    function setUp() public override {
        super.setUp();
        vault = _deployVault(usdc, feedUsdc, 0);
    }

    function test_sendEth_reverts() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok, bytes memory ret) = address(vault).call{value: 1 ether}("");
        assertFalse(ok);
        // casting to 'bytes4' is safe because revert reason is a 4-byte selector
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(bytes4(ret), TokenizedVault.VaultEtherNotAccepted.selector);
    }

    function test_sendEthWithData_reverts() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok, bytes memory ret) = address(vault).call{value: 1 ether}(abi.encodeWithSignature("nonsense()"));
        assertFalse(ok);
        // casting to 'bytes4' is safe because revert reason is a 4-byte selector
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(bytes4(ret), TokenizedVault.VaultEtherNotAccepted.selector);
    }

    function test_vaultHoldingsNoEth() public {
        assertEq(address(vault).balance, 0);
    }
}

contract VaultErc4626StandardTest is VaultTest {
    function setUp() public override {
        super.setUp();
        vault = _deployVault(usdc, feedUsdc, 0);
    }

    function test_deposit_standard_mintsToReceiver() public {
        _mintAndApprove(usdc, alice, 100e6);
        vm.prank(alice);
        uint256 shares = vault.deposit(100e6, bob);
        assertEq(shares, 100e6);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.balanceOf(bob), 100e6);
        assertEq(usdc.balanceOf(address(vault)), 100e6);
        (uint256 amount, uint256 timestamp) = vault.deposits(bob);
        assertEq(amount, 100e6);
        assertEq(timestamp, block.timestamp);
    }

    function test_deposit_standard_revertsForZeroReceiver() public {
        _mintAndApprove(usdc, alice, 100e6);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(TokenizedVault.VaultZeroAddress.selector, address(0)));
        vault.deposit(100e6, address(0));
    }

    function test_deposit_enabledToken_mintsToReceiver() public {
        _enable(address(dai), feedDai, 18);
        _mintAndApprove(dai, alice, 1000e18);
        vm.prank(alice);
        uint256 shares = vault.deposit(address(dai), 100e18, carol);
        assertEq(shares, 100e6);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.balanceOf(carol), 100e6);
        assertEq(dai.balanceOf(address(vault)), 100e18);
        (uint256 amount,) = vault.deposits(carol);
        assertEq(amount, 100e6);
    }

    function test_deposit_enabledToken_revertsForZeroReceiver() public {
        _enable(address(dai), feedDai, 18);
        _mintAndApprove(dai, alice, 1000e18);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(TokenizedVault.VaultZeroAddress.selector, address(0)));
        vault.deposit(address(dai), 100e18, address(0));
    }

    function test_deposit_standard_revertsForZeroAssets() public {
        vm.prank(alice);
        vm.expectRevert(TokenizedVault.VaultZeroAmount.selector);
        vault.deposit(0, bob);
    }

    function test_mint_standard_mintsForReceiver() public {
        _mintAndApprove(usdc, alice, 100e6);
        vm.prank(alice);
        uint256 assets = vault.mint(50e6, carol);
        assertEq(assets, 50e6);
        assertEq(vault.balanceOf(carol), 50e6);
        assertEq(usdc.balanceOf(address(vault)), 50e6);
    }

    function test_mint_zeroShares_reverts() public {
        vm.prank(alice);
        vm.expectRevert(TokenizedVault.VaultZeroShares.selector);
        vault.mint(0, alice);
    }

    function test_withdraw_standard_paysReceiverBurnsOwner() public {
        _mintAndApprove(usdc, alice, 100e6);
        vm.prank(alice);
        uint256 shares = vault.deposit(100e6, alice);
        vm.prank(alice);
        uint256 burned = vault.withdraw(100e6, bob, alice);
        assertEq(burned, shares);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(usdc.balanceOf(bob), 100e6);
    }

    function test_vaultCanBeUsedThroughIerc4626Interface() public {
        IERC4626 v = IERC4626(address(vault));
        assertEq(v.asset(), address(usdc));
        assertEq(v.totalAssets(), 0);
        _mintAndApprove(usdc, alice, 100e6);
        vm.prank(alice);
        uint256 shares = v.deposit(100e6, alice);
        assertEq(v.balanceOf(alice), shares);
        assertEq(v.maxRedeem(alice), shares);
        vm.prank(alice);
        uint256 assets = v.redeem(shares, alice, alice);
        assertEq(assets, 100e6);
    }

    function test_redeem_standard_paysReceiverBurnsOwner() public {
        _mintAndApprove(usdc, alice, 100e6);
        vm.prank(alice);
        vault.deposit(100e6, alice);
        vm.prank(alice);
        uint256 assets = vault.redeem(100e6, carol, alice);
        assertEq(assets, 100e6);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(usdc.balanceOf(carol), 100e6);
    }

    function test_thirdParty_redeem_requiresAllowance() public {
        _mintAndApprove(usdc, alice, 100e6);
        vm.prank(alice);
        vault.deposit(100e6, alice);
        vm.prank(bob);
        vm.expectRevert(); // ERC20InsufficientAllowance
        vault.redeem(100e6, bob, alice);

        vm.prank(alice);
        vault.approve(bob, 100e6);
        vm.prank(bob);
        vault.redeem(100e6, bob, alice);
        assertEq(usdc.balanceOf(bob), 100e6);
        assertEq(vault.allowance(alice, bob), 0);
    }

    function test_thirdParty_withdraw_spendsAllowance() public {
        _mintAndApprove(usdc, alice, 100e6);
        vm.prank(alice);
        vault.deposit(100e6, alice);
        vm.prank(alice);
        vault.approve(bob, 50e6);
        vm.prank(bob);
        uint256 burned = vault.withdraw(50e6, bob, alice);
        assertEq(burned, 50e6);
        assertEq(usdc.balanceOf(bob), 50e6);
        assertEq(vault.allowance(alice, bob), 0);
    }
}

contract VaultErc4626TimelockTest is VaultTest {
    function test_deposit_standard_recordsTimelockOnReceiver() public {
        vault = _deployVault(usdc, feedUsdc, 1 hours);
        _mintAndApprove(usdc, alice, 100e6);
        vm.prank(alice);
        vault.deposit(100e6, carol);
        assertEq(vault.maxRedeem(carol), 0, "receiver should be locked");
        vm.prank(carol);
        vm.expectRevert(
            abi.encodeWithSelector(TokenizedVault.VaultTimelockNotExpired.selector, block.timestamp + 1 hours)
        );
        vault.redeem(100e6, carol, carol);
    }

    function test_withdraw_standard_checksOwnerTimelock_notCaller() public {
        vault = _deployVault(usdc, feedUsdc, 1 hours);
        _mintAndApprove(usdc, alice, 100e6);
        vm.prank(alice);
        vault.deposit(100e6, alice);
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(TokenizedVault.VaultTimelockNotExpired.selector, block.timestamp + 1 hours)
        );
        vault.withdraw(50e6, bob, alice);
        vm.warp(block.timestamp + 1 hours);
        vm.prank(alice);
        vault.approve(bob, 50e6);
        vm.prank(bob);
        vault.withdraw(50e6, bob, alice);
        assertEq(usdc.balanceOf(bob), 50e6);
    }

    function test_donation_toLockedReceiver_doesNotExtendLock() public {
        vault = _deployVault(usdc, feedUsdc, 1 hours);
        _mintAndApprove(usdc, alice, 100e6);
        vm.prank(alice);
        vault.deposit(100e6, carol);
        (uint256 amount, uint256 lockedAt) = vault.deposits(carol);
        _mintAndApprove(usdc, bob, 1);
        vm.prank(bob);
        vault.deposit(1, carol);
        (, uint256 afterTs) = vault.deposits(carol);
        assertEq(afterTs, lockedAt, "donation must not extend the receiver's lock");
        assertGt(vault.balanceOf(carol), 100e6);
    }
}

contract VaultPausableTest is VaultTest {
    function setUp() public override {
        super.setUp();
        vault = _deployVault(usdc, feedUsdc, 0);
        vault.enableToken(address(dai), address(feedDai), 18);
    }

    function test_paused_isFalseByDefault() public view {
        assertFalse(vault.paused());
    }

    function test_pause_byOwner() public {
        vm.expectEmit(true, true, true, true);
        emit PausableUpgradeable.Paused(address(this));
        vault.pause();
        assertTrue(vault.paused());
    }

    function test_pause_revertsForNonOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.pause();
    }

    function test_pause_revertsWhenAlreadyPaused() public {
        vault.pause();
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vault.pause();
    }

    function test_unpause_byOwner() public {
        vault.pause();
        vm.expectEmit(true, true, true, true);
        emit PausableUpgradeable.Unpaused(address(this));
        vault.unpause();
        assertFalse(vault.paused());
    }

    function test_unpause_revertsForNonOwner() public {
        vault.pause();
        vm.prank(alice);
        vm.expectRevert();
        vault.unpause();
    }

    function test_deposit_revertsWhenPaused() public {
        _mintAndApprove(usdc, alice, 100e6);
        _mintAndApprove(dai, alice, 100e18);
        vault.pause();
        vm.prank(alice);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vault.deposit(address(usdc), 100e6, alice);
        vm.prank(alice);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vault.deposit(address(dai), 100e18, alice);
        vm.prank(alice);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vault.deposit(100e6, alice);
    }

    function test_mint_revertsWhenPaused() public {
        _mintAndApprove(usdc, alice, 100e6);
        vault.pause();
        vm.prank(alice);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vault.mint(100e6, alice);
    }

    function test_withdrawAndRedeem_revertWhenPaused() public {
        _mintAndApprove(usdc, alice, 100e6);
        vm.prank(alice);
        vault.deposit(100e6, alice);
        vault.pause();
        vm.prank(alice);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vault.withdraw(100e6, alice, alice);
        vm.prank(alice);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vault.redeem(100e6, alice, alice);
    }

    function test_unpause_restoresDeposits() public {
        vault.pause();
        vault.unpause();
        _mintAndApprove(usdc, alice, 100e6);
        vm.prank(alice);
        uint256 shares = vault.deposit(100e6, alice);
        assertEq(shares, 100e6);
    }

    function test_adminConfig_availableWhilePaused() public {
        vault.pause();
        vault.enableToken(address(weth), address(feedWeth), 18);
        assertTrue(vault.isTokenEnabled(address(weth)));
    }
}

contract VaultMinimumDepositTest is VaultTest {
    uint256 internal constant MIN_DEPOSIT = 100e6; // 100 USDC

    function setUp() public override {
        super.setUp();
        vault = _deployVault(usdc, feedUsdc, 0);
        vault.setMinimumDepositAmount(MIN_DEPOSIT);
        _enable(address(dai), feedDai, 18);
    }

    function test_minimumDepositZeroByDefault() public {
        bytes memory initData = abi.encodeCall(
            TokenizedVault.initialize, (address(this), address(usdc), "AV", "AV", address(feedUsdc), 0, 0, 0)
        );
        address proxy = factory.deployProxy(keccak256("minimum-deposit-default"), initData);
        TokenizedVault v = TokenizedVault(payable(proxy));
        assertEq(v.minimumDepositAmount(), 0);
    }

    function test_deposit_revertsBelowMinimum() public {
        _mintAndApprove(usdc, alice, 1000e6);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(TokenizedVault.VaultBelowMinimumDeposit.selector, MIN_DEPOSIT));
        vault.deposit(address(usdc), MIN_DEPOSIT - 1, alice);
    }

    function test_deposit_atMinimum_succeeds() public {
        _mintAndApprove(usdc, alice, 1000e6);
        vm.prank(alice);
        uint256 shares = vault.deposit(address(usdc), MIN_DEPOSIT, alice);
        assertEq(shares, MIN_DEPOSIT);
    }

    function test_deposit_standard_revertsBelowMinimum() public {
        _mintAndApprove(usdc, alice, 1000e6);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(TokenizedVault.VaultBelowMinimumDeposit.selector, MIN_DEPOSIT));
        vault.deposit(MIN_DEPOSIT - 1, alice);
    }

    function test_depositEnabledToken_revertsBelowMinimum() public {
        _mintAndApprove(dai, alice, 1000e18);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(TokenizedVault.VaultBelowMinimumDeposit.selector, MIN_DEPOSIT));
        vault.deposit(address(dai), 99e18, alice); // 99 USDC of DAI, below 100 USDC minimum
    }

    function test_mint_revertsBelowMinimum() public {
        _mintAndApprove(usdc, alice, 1000e6);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(TokenizedVault.VaultBelowMinimumDeposit.selector, MIN_DEPOSIT));
        vault.mint(MIN_DEPOSIT - 1, alice);
    }

    function test_setMinimumDepositAmount_emitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit TokenizedVault.MinimumDepositAmountChanged(50e6);
        vault.setMinimumDepositAmount(50e6);
        assertEq(vault.minimumDepositAmount(), 50e6);
    }

    function test_setMinimumDepositAmount_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.setMinimumDepositAmount(50e6);
    }

    function test_loweringMinimum_allowsSmallerDeposits() public {
        vault.setMinimumDepositAmount(1e6);
        _mintAndApprove(usdc, alice, 1000e6);
        vm.prank(alice);
        uint256 shares = vault.deposit(address(usdc), 1e6, alice);
        assertEq(shares, 1e6);
    }
}

contract VaultPriceFeedUpdateTest is VaultTest {
    function setUp() public override {
        super.setUp();
        vault = _deployVault(usdc, feedUsdc, 0);
        _enable(address(dai), feedDai, 18);
    }

    function test_updateTokenPriceFeed_updatesValuation() public {
        MockChainlinkPriceFeed newFeed = new MockChainlinkPriceFeed(8, 2e8); // DAI at $2
        vm.expectEmit(true, true, true, true);
        emit TokenizedVault.PriceFeedUpdated(address(dai), address(newFeed));
        vault.updateTokenPriceFeed(address(dai), address(newFeed));
        (address feed,) = vault.tokenPriceFeeds(address(dai));
        assertEq(feed, address(newFeed));
        assertEq(vault.getTokenValue(address(dai)), 2e18);
    }

    function test_updateTokenPriceFeed_updatesUnderlyingFeed() public {
        MockChainlinkPriceFeed newFeed = new MockChainlinkPriceFeed(8, 2e8); // USDC at $2
        vm.expectEmit(true, true, true, true);
        emit TokenizedVault.PriceFeedUpdated(address(usdc), address(newFeed));
        vault.updateTokenPriceFeed(address(usdc), address(newFeed));
        assertEq(vault.underlyingPriceFeed(), address(newFeed));
        // DAI at $1 relative to USDC at $2 -> 0.5 USDC per DAI
        assertEq(vault.getTokenValue(address(dai)), 5e17);
    }

    function test_updateTokenPriceFeed_revertsWhenNotEnabled() public {
        vm.expectRevert(abi.encodeWithSelector(TokenizedVault.VaultNotEnabled.selector, address(wbtc)));
        vault.updateTokenPriceFeed(address(wbtc), address(feedWbtc));
    }

    function test_updateTokenPriceFeed_revertsForZeroFeed() public {
        vm.expectRevert(abi.encodeWithSelector(TokenizedVault.VaultInvalidPriceFeed.selector, address(0)));
        vault.updateTokenPriceFeed(address(dai), address(0));
    }

    function test_updateTokenPriceFeed_revertsForEOA() public {
        vm.expectRevert(abi.encodeWithSelector(TokenizedVault.VaultInvalidPriceFeed.selector, address(0xBEEF)));
        vault.updateTokenPriceFeed(address(dai), address(0xBEEF));
    }

    function test_updateTokenPriceFeed_revertsForStaleFeed() public {
        MockChainlinkPriceFeed staleFeed = new MockChainlinkPriceFeed(8, 1e8);
        staleFeed.setUpdatedAt(0);
        vm.expectRevert(abi.encodeWithSelector(TokenizedVault.VaultStalePriceFeed.selector, address(staleFeed)));
        vault.updateTokenPriceFeed(address(dai), address(staleFeed));
    }

    function test_updateTokenPriceFeed_onlyOwner() public {
        MockChainlinkPriceFeed newFeed = new MockChainlinkPriceFeed(8, 2e8);
        vm.prank(alice);
        vm.expectRevert();
        vault.updateTokenPriceFeed(address(dai), address(newFeed));
    }

    function test_updateTokenPriceFeed_rejectsFeedWithRoundMismatch() public {
        MockChainlinkPriceFeed badFeed = new MockChainlinkPriceFeed(8, 1e8);
        badFeed.setAnsweredInRound(0);
        vm.expectRevert(abi.encodeWithSelector(TokenizedVault.VaultInvalidPriceFeedRound.selector, address(badFeed)));
        vault.updateTokenPriceFeed(address(dai), address(badFeed));
    }
}

contract VaultWithdrawalFeeTest is VaultTest {
    function setUp() public override {
        super.setUp();
        vault = _deployVault(usdc, feedUsdc, 0);
        vault.setFeeCollector(bob);
    }

    function test_withdrawalFee_zeroByDefault() public {
        assertEq(vault.withdrawalFee(), 0);
        assertEq(vault.FEE_DENOMINATOR(), 10_000);
    }

    function test_withdrawalFee_setViaInitialize() public {
        bytes memory initData = abi.encodeCall(
            TokenizedVault.initialize,
            (address(this), address(usdc), "AV", "AV", address(feedUsdc), 0, 0, 250)
        );
        address proxy = factory.deployProxy(keccak256("fee-init"), initData);
        TokenizedVault v = TokenizedVault(payable(proxy));
        assertEq(v.withdrawalFee(), 250);
        assertEq(v.feeCollector(), address(this)); // defaults to the initial owner
    }

    function test_initialize_rejectsFeeAboveDenominator() public {
        bytes memory initData = abi.encodeCall(
            TokenizedVault.initialize,
            (address(this), address(usdc), "AV", "AV", address(feedUsdc), 0, 0, 10_001)
        );
        vm.expectRevert(TokenizedVault.VaultInvalidFee.selector);
        factory.deployProxy(keccak256("fee-bad-init"), initData);
    }

    function test_withdraw_appliesFeeToCollector() public {
        _mintAndApprove(usdc, alice, 10_000e6);
        vm.prank(alice);
        vault.deposit(10_000e6, alice);
        vault.setWithdrawalFee(500); // 5%
        vm.prank(alice);
        uint256 shares = vault.withdraw(1_000e6, alice, alice);
        assertEq(shares, 1_000e6);
        assertEq(usdc.balanceOf(alice), 950e6); // fee deducted from payout
        assertEq(usdc.balanceOf(bob), 50e6); // fee forwarded to the fee collector
        assertEq(usdc.balanceOf(address(vault)), 9_000e6);
    }

    function test_redeem_appliesFeeToCollector() public {
        _mintAndApprove(usdc, alice, 10_000e6);
        vm.prank(alice);
        uint256 sharesMinted = vault.deposit(10_000e6, alice);
        vault.setWithdrawalFee(500); // 5%
        vm.prank(alice);
        uint256 received = vault.redeem(sharesMinted, alice, alice);
        assertEq(received, 9_500e6);
        assertEq(usdc.balanceOf(alice), 9_500e6);
        assertEq(usdc.balanceOf(bob), 500e6);
        assertEq(usdc.balanceOf(address(vault)), 0);
    }

    function test_withdraw_feeRoundsUpInCollectorsFavor() public {
        _mintAndApprove(usdc, alice, 999);
        vm.prank(alice);
        vault.deposit(999, alice);
        vault.setWithdrawalFee(5000); // 50%
        vm.prank(alice);
        vault.withdraw(999, alice, alice); // fee = ceil(499.5) = 500
        assertEq(usdc.balanceOf(alice), 499);
        assertEq(usdc.balanceOf(bob), 500);
        assertEq(usdc.balanceOf(address(vault)), 0);
    }

    function test_fullWithdrawal_sendsFeeToCollector() public {
        _mintAndApprove(usdc, alice, 1_000e6);
        vm.prank(alice);
        vault.deposit(1_000e6, alice);
        vault.setWithdrawalFee(1000); // 10%
        vm.prank(alice);
        vault.withdraw(1_000e6, alice, alice);
        assertEq(usdc.balanceOf(alice), 900e6);
        assertEq(usdc.balanceOf(bob), 100e6);
        assertEq(usdc.balanceOf(address(vault)), 0);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.totalSupply(), 0);
    }

    function test_withdraw_zeroFee_transfersNothingToCollector() public {
        _mintAndApprove(usdc, alice, 1_000e6);
        vm.prank(alice);
        vault.deposit(1_000e6, alice);
        vm.prank(alice);
        vault.withdraw(1_000e6, alice, alice);
        assertEq(usdc.balanceOf(alice), 1_000e6);
        assertEq(usdc.balanceOf(bob), 0);
    }

    function test_withdraw_revertsWhenFeeConsumesWholeAmount() public {
        _mintAndApprove(usdc, alice, 1_000e6);
        vm.prank(alice);
        vault.deposit(1_000e6, alice);
        vault.setWithdrawalFee(vault.FEE_DENOMINATOR()); // 100%
        vm.prank(alice);
        vm.expectRevert(TokenizedVault.VaultFeeExceedsAssets.selector);
        vault.withdraw(100e6, alice, alice);
    }

    function test_redeem_revertsWhenFeeConsumesWholeAmount() public {
        _mintAndApprove(usdc, alice, 1_000e6);
        vm.prank(alice);
        vault.deposit(1_000e6, alice);
        vault.setWithdrawalFee(vault.FEE_DENOMINATOR()); // 100%
        vm.prank(alice);
        vm.expectRevert(TokenizedVault.VaultFeeExceedsAssets.selector);
        vault.redeem(100e6, alice, alice);
    }

    function test_withdraw_revertsWhenRoundedFeeConsumesDust() public {
        _mintAndApprove(usdc, alice, 999);
        vm.prank(alice);
        vault.deposit(999, alice);
        vault.setWithdrawalFee(5000); // 50%; ceil(0.5 * 1) = 1 >= 1 wei
        vm.prank(alice);
        vm.expectRevert(TokenizedVault.VaultFeeExceedsAssets.selector);
        vault.withdraw(1, alice, alice);
    }

    function test_feeCollectorChange_appliesToNextWithdraw() public {
        _mintAndApprove(usdc, alice, 10_000e6);
        vm.prank(alice);
        vault.deposit(10_000e6, alice);
        vault.setWithdrawalFee(500); // 5%
        vault.setFeeCollector(carol);
        vm.prank(alice);
        vault.withdraw(1_000e6, alice, alice);
        assertEq(usdc.balanceOf(carol), 50e6);
        assertEq(usdc.balanceOf(bob), 0);
    }

    function test_setWithdrawalFee_emitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit TokenizedVault.WithdrawalFeeChanged(250);
        vault.setWithdrawalFee(250);
        assertEq(vault.withdrawalFee(), 250);
    }

    function test_setWithdrawalFee_revertsAboveDenominator() public {
        vm.expectRevert(TokenizedVault.VaultInvalidFee.selector);
        vault.setWithdrawalFee(10_001);
        vm.expectRevert(TokenizedVault.VaultInvalidFee.selector);
        vault.setWithdrawalFee(type(uint256).max);
    }

    function test_setWithdrawalFee_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.setWithdrawalFee(250);
    }

    function test_setWithdrawalFee_toZero_disablesFee() public {
        vault.setWithdrawalFee(250);
        vault.setWithdrawalFee(0);
        _mintAndApprove(usdc, alice, 1_000e6);
        vm.prank(alice);
        vault.deposit(1_000e6, alice);
        vm.prank(alice);
        uint256 received = vault.redeem(1_000e6, alice, alice);
        assertEq(received, 1_000e6);
        assertEq(usdc.balanceOf(bob), 0);
    }

    function test_setFeeCollector_emitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit TokenizedVault.FeeCollectorChanged(carol);
        vault.setFeeCollector(carol);
        assertEq(vault.feeCollector(), carol);
    }

    function test_setFeeCollector_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.setFeeCollector(carol);
    }

    function test_setFeeCollector_revertsForZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(TokenizedVault.VaultZeroAddress.selector, address(0)));
        vault.setFeeCollector(address(0));
    }
}
