//SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { Test, console2 } from "lib/forge-std/src/Test.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { DeploySVC } from "../../script/DeploySVC.s.sol";
import { SVCEngine } from "../../src/SVCEngine.sol";
import { SVCTreasury } from "../../src/SVCTreasury.sol";
import { StableValueCoin } from "../../src/StableValueCoin.sol";
import { HelperConfig } from "../../script/HelperConfig.s.sol";
import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";
import { MockMoreDebtSVC } from "../mocks/MockMoreDebtSVC.sol";
import { MockFailedMintSVC } from "../mocks/MockFailedMintSVC.sol";
import { MockFailedTransferFrom } from "../mocks/MockFailedTransferFrom.sol";
import { MockFailedTransfer } from "../mocks/MockFailedTransfer.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SVCEngineTest is StdCheats, Test {
    event CollateralRedeemed(
        address indexed redeemFrom, address indexed redeemTo, address indexed token, uint256 amount
    );

    SVCTreasury public svct;
    StableValueCoin public svc;
    SVCEngine public svce;
    HelperConfig public helperConfig;

    address public ethUsdPriceFeed;
    address public weth;
    address public cbethUsdPriceFeed;
    address public cbeth;
    address public cbbtcUsdPriceFeed;
    address public cbbtc;
    uint256 public deployerKey;

    uint256 amountCollateral = 10 ether;
    uint256 amountToMint = 100 ether;
    address public user = address(1);

    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant TREASURY_FEE = 5;
    uint256 private constant LIQUIDATION_PRECISION = 100;

    // Liquidation
    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;

    function setUp() external {
        DeploySVC deployer = new DeploySVC();
        (svc, svce, helperConfig, svct) = deployer.run();
        (ethUsdPriceFeed, cbethUsdPriceFeed, cbbtcUsdPriceFeed, weth, cbeth, cbbtc, deployerKey) =
            helperConfig.activeNetworkConfig();
        if (block.chainid == 84_532) {
            vm.deal(user, STARTING_USER_BALANCE);
        }
        ERC20Mock(weth).mint(user, STARTING_USER_BALANCE);
        ERC20Mock(cbeth).mint(user, STARTING_USER_BALANCE);
        ERC20Mock(cbbtc).mint(user, STARTING_USER_BALANCE);
    }

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    modifier depositedCollateralAndMintedSvc() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(svce), amountCollateral);
        svce.depositCollateralAndMintSVC(weth, amountCollateral, amountToMint);
        vm.stopPrank();
        _;
    }

    modifier depositedCollateral() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(svce), amountCollateral);
        svce.depositCollateral(weth, amountCollateral);
        vm.stopPrank();
        _;
    }

    modifier liquidated() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(svce), amountCollateral);
        svce.depositCollateralAndMintSVC(weth, amountCollateral, amountToMint);
        vm.stopPrank();
        int256 ethUsdUpdatedPrice = 18e8; //$18 eth

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 userHealthFactor = svce.getHealthFactor(user);

        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(svce), collateralToCover);
        svce.depositCollateralAndMintSVC(weth, collateralToCover, amountToMint);
        svc.approve(address(svce), amountToMint);
        svce.liquidate(weth, user, amountToMint); // covering whole debt
        vm.stopPrank();
        _;
    }

    //////////////////////////
    // Constructor Tests ////
    //////////////////////////

    function testRevertsIfTokenLengthDoesntMatchPricedFeedLength() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(cbethUsdPriceFeed);

        vm.expectRevert(SVCEngine.SVCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new SVCEngine(tokenAddresses, priceFeedAddresses, address(svc), payable(address(svct)));
    }

    ///////////////////
    // Price Tests ////
    ///////////////////

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30_000e18;
        uint256 actualUsd = svce._getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = svce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    ////////////////////////////////
    // Deposit Collateral Tests ////
    ////////////////////////////////

    function testRevertsIfTransferFromFails() public {
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransferFrom mockSvc = new MockFailedTransferFrom();
        tokenAddresses = [address(mockSvc)];
        priceFeedAddresses = [ethUsdPriceFeed];
        vm.prank(owner);
        SVCEngine mockSvce = new SVCEngine(tokenAddresses, priceFeedAddresses, address(mockSvc), payable(address(svct)));
        mockSvc.mint(user, amountCollateral);

        vm.prank(owner);
        mockSvc.transferOwnership(address(mockSvce));
        vm.startPrank(user);
        ERC20Mock(address(mockSvc)).approve(address(mockSvce), amountCollateral);

        vm.expectRevert(SVCEngine.SVCEngine__TransferFailed.selector);
        mockSvce.depositCollateral(address(mockSvc), amountCollateral);
        vm.stopPrank();
    }

    function testRevertsIfCollateralZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(svce), amountCollateral);

        vm.expectRevert(SVCEngine.SVCEngine__NeedsMoreThanZero.selector);
        svce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock randomToken = new ERC20Mock("Random", "Random", user, STARTING_USER_BALANCE);
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(SVCEngine.SVCEngine__TokenNotAllowed.selector, address(randomToken)));
        svce.depositCollateral(address(randomToken), STARTING_USER_BALANCE);
        vm.stopPrank();
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalSvcMinted, uint256 collateralValueInUsd) = svce.getAccountInformation(user);

        uint256 expectedTotalSvcMinted = 0;
        uint256 expectedDepositAmount = svce.getTokenAmountFromUsd(weth, collateralValueInUsd);

        assertEq(totalSvcMinted, expectedTotalSvcMinted);
        assertEq(amountCollateral, expectedDepositAmount);
    }

    function testCanDepositCollateralWithoutMinting() public depositedCollateral {
        uint256 userBalance = svc.balanceOf(user);
        assertEq(userBalance, 0);
    }

    ///////////////////////////////////////
    // depositCollateralAndMintSVC Tests //
    ///////////////////////////////////////

    function testRevertsIfMintedSvcBreaksHealthFactor() public {
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        amountToMint = (amountCollateral * (uint256(price) * svce.getAdditionalFeedPrecision())) / svce.getPrecision();
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(svce), amountCollateral);

        uint256 expectedHealthFactor =
            svce.calculateHealthFactor(amountToMint, svce.getUsdValue(weth, amountCollateral));
        vm.expectRevert(abi.encodeWithSelector(SVCEngine.SVCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        svce.depositCollateralAndMintSVC(weth, amountCollateral, amountToMint);
        vm.stopPrank();
    }

    function testCanMintWithDepositedCollateral() public depositedCollateralAndMintedSvc {
        uint256 userBalance = svc.balanceOf(user);
        assertEq(userBalance, amountToMint);
    }

    ////////////////////
    // mintSVC Tests //
    ///////////////////

    function testRevertsIfMintFails() public {
        // Arrange - Setup
        MockFailedMintSVC mockSvc = new MockFailedMintSVC();
        tokenAddresses = [weth];
        priceFeedAddresses = [ethUsdPriceFeed];
        address owner = msg.sender;
        vm.prank(owner);
        SVCEngine mockSvce = new SVCEngine(tokenAddresses, priceFeedAddresses, address(mockSvc), payable(address(svct)));
        mockSvc.transferOwnership(address(mockSvce));
        // Arrange - User
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(mockSvce), amountCollateral);

        vm.expectRevert(SVCEngine.SVCEngine__MintFailed.selector);
        mockSvce.depositCollateralAndMintSVC(weth, amountCollateral, amountToMint);
        vm.stopPrank();
    }

    function testRevertsIfMintAmountIsZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(svce), amountCollateral);
        svce.depositCollateralAndMintSVC(weth, amountCollateral, amountToMint);
        vm.expectRevert(SVCEngine.SVCEngine__NeedsMoreThanZero.selector);
        svce.mintSVC(0);
        vm.stopPrank();
    }

    function testRevertsIfMintAmountBreaksHealthFactor() public depositedCollateral {
        // 0xe580cc6100000000000000000000000000000000000000000000000006f05b59d3b20000
        // 0xe580cc6100000000000000000000000000000000000000000000003635c9adc5dea00000
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        amountToMint = (amountCollateral * (uint256(price) * svce.getAdditionalFeedPrecision())) / svce.getPrecision();

        vm.startPrank(user);
        uint256 expectedHealthFactor =
            svce.calculateHealthFactor(amountToMint, svce.getUsdValue(weth, amountCollateral));
        vm.expectRevert(abi.encodeWithSelector(SVCEngine.SVCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        svce.mintSVC(amountToMint);
        vm.stopPrank();
    }

    function testCanMintSvc() public depositedCollateral {
        vm.prank(user);
        svce.mintSVC(amountToMint);

        uint256 userBalance = svc.balanceOf(user);
        assertEq(userBalance, amountToMint);
    }

    ////////////////////
    // burnSVC Tests //
    ///////////////////

    function testRevertsIfBurnAmountIsZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(svce), amountCollateral);
        svce.depositCollateralAndMintSVC(weth, amountCollateral, amountToMint);
        vm.expectRevert(SVCEngine.SVCEngine__NeedsMoreThanZero.selector);
        svce.burnSvc(0);
        vm.stopPrank();
    }

    function testCantBurnMoreThanUserHas() public {
        vm.prank(user);
        vm.expectRevert();
        svce.burnSvc(2);
    }

    function testCanBurnSvc() public depositedCollateralAndMintedSvc {
        vm.startPrank(user);
        svc.approve(address(svce), amountToMint);
        svce.burnSvc(amountToMint);
        vm.stopPrank();

        uint256 userBalance = svc.balanceOf(user);
        assertEq(userBalance, 0);
    }

    /////////////////////////////
    // redeemCollateral Tests //
    ////////////////////////////

    function testRevertsIfTransferFails() public {
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransfer mockSvc = new MockFailedTransfer();
        tokenAddresses = [address(mockSvc)];
        priceFeedAddresses = [ethUsdPriceFeed];
        vm.prank(owner);
        SVCEngine mockSvce = new SVCEngine(tokenAddresses, priceFeedAddresses, address(mockSvc), payable(address(svct)));
        mockSvc.mint(user, amountCollateral);

        vm.prank(owner);
        mockSvc.transferOwnership(address(mockSvce));

        vm.startPrank(user);
        ERC20Mock(address(mockSvc)).approve(address(mockSvce), amountCollateral);

        mockSvce.depositCollateral(address(mockSvc), amountCollateral);
        vm.expectRevert(SVCEngine.SVCEngine__TransferFailed.selector);
        mockSvce.redeemCollateral(address(mockSvc), amountCollateral);
        vm.stopPrank();
    }

    function testRevertsIfRedeemAmountIsZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(svce), amountCollateral);
        svce.depositCollateralAndMintSVC(weth, amountCollateral, amountToMint);
        vm.expectRevert(SVCEngine.SVCEngine__NeedsMoreThanZero.selector);
        svce.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testCanRedeemCollateral() public depositedCollateral {
        vm.startPrank(user);
        svce.redeemCollateral(weth, amountCollateral);
        uint256 userBalance = ERC20Mock(weth).balanceOf(user);
        assertEq(userBalance, amountCollateral);
        vm.stopPrank();
    }

    function testEmitCollateralRedeemedWithCorrectArgs() public depositedCollateral {
        vm.expectEmit(true, true, true, true, address(svce));
        emit CollateralRedeemed(user, user, weth, amountCollateral);
        vm.startPrank(user);
        svce.redeemCollateral(weth, amountCollateral);
        vm.stopPrank();
    }

    ////////////////////////////////////
    // redeemCollateral For SVC Tests //
    ////////////////////////////////////

    function testMustRedeemMoreThanZero() public depositedCollateralAndMintedSvc {
        vm.startPrank(user);
        svc.approve(address(svce), amountToMint);
        vm.expectRevert(SVCEngine.SVCEngine__NeedsMoreThanZero.selector);
        svce.redeemCollateralForSVC(weth, 0, amountToMint);
        vm.stopPrank();
    }

    function testCanRedeemDepositedCollateral() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(svce), amountCollateral);
        svce.depositCollateralAndMintSVC(weth, amountCollateral, amountToMint);
        svc.approve(address(svce), amountToMint);
        svce.redeemCollateralForSVC(weth, amountCollateral, amountToMint);
        vm.stopPrank();

        uint256 userBalance = svc.balanceOf(user);
        assertEq(userBalance, 0);
    }

    ////////////////////////
    // healthFactor Tests //
    ////////////////////////

    function testProperlyReportsHealthFactor() public depositedCollateralAndMintedSvc {
        uint256 expectedHealthFactor = 100 ether;
        uint256 healthFactor = svce.getHealthFactor(user);

        assertEq(healthFactor, expectedHealthFactor);
    }

    function testHealthFactorCanGoBelowOne() public depositedCollateralAndMintedSvc {
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        uint256 userHealthFactor = svce.getHealthFactor(user);
        assert(userHealthFactor == 0.9 ether);
    }

    ///////////////////////
    // Liquidation Tests //
    ///////////////////////

    function testMustImproveHealthFactorOnLiquidation() public {
        // Arrange - Setup
        MockMoreDebtSVC mockSvc = new MockMoreDebtSVC(ethUsdPriceFeed);
        tokenAddresses = [weth];
        priceFeedAddresses = [ethUsdPriceFeed];
        address owner = msg.sender;
        vm.prank(owner);
        SVCEngine mockSvce = new SVCEngine(tokenAddresses, priceFeedAddresses, address(mockSvc), payable(address(svct)));
        mockSvc.transferOwnership(address(mockSvce));
        // Arrange - User
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(mockSvce), amountCollateral);
        mockSvce.depositCollateralAndMintSVC(weth, amountCollateral, amountToMint);
        vm.stopPrank();

        // Arrange - Liquidator
        collateralToCover = 1 ether;
        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(mockSvce), collateralToCover);
        uint256 debtToCover = 10 ether;
        mockSvce.depositCollateralAndMintSVC(weth, collateralToCover, amountToMint);
        mockSvc.approve(address(mockSvce), debtToCover);
        // Act
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        // Act/Assert
        vm.expectRevert(SVCEngine.SVCEngine__HealthFactorNotImproved.selector);
        mockSvce.liquidate(weth, user, debtToCover);
        vm.stopPrank();
    }

    function testCantLiquidateGoodHealthFactor() public depositedCollateralAndMintedSvc {
        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(svce), collateralToCover);
        svce.depositCollateralAndMintSVC(weth, collateralToCover, amountToMint);
        svc.approve(address(svce), amountToMint);

        vm.expectRevert(SVCEngine.SVCEngine__HealthFactorIsOk.selector);
        svce.liquidate(weth, user, amountToMint);
        vm.stopPrank();
    }

    function testLiquidationPayoutIsCorrect() public liquidated {
        uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(liquidator);
        uint256 expectedWeth = svce.getTokenAmountFromUsd(weth, amountToMint)
            + (svce.getTokenAmountFromUsd(weth, amountToMint) / svce.getLiquidationBonus());
        uint256 hardCodedExpected = 6_111_111_111_111_111_110;
        assertEq(liquidatorWethBalance, hardCodedExpected);
        assertEq(liquidatorWethBalance, expectedWeth);
    }

    function testUserStillHasSomeEthAfterLiquidation() public liquidated {
        // Get how much WETH the user lost
        uint256 amountLiquidated = svce.getTokenAmountFromUsd(weth, amountToMint)
            + (svce.getTokenAmountFromUsd(weth, amountToMint) / svce.getLiquidationBonus());

        uint256 usdAmountLiquidated = svce.getUsdValue(weth, amountLiquidated);
        uint256 expectedUserCollateralValueInUsd = svce.getUsdValue(weth, amountCollateral) - (usdAmountLiquidated);

        (, uint256 userCollateralValueInUsd) = svce.getAccountInformation(user);
        uint256 hardCodedExpectedValue = 70_000_000_000_000_000_020;
        assertEq(userCollateralValueInUsd, expectedUserCollateralValueInUsd);
        assertEq(userCollateralValueInUsd, hardCodedExpectedValue);
    }

    function testLiquidatorTakesOnUsersDebt() public liquidated {
        (uint256 liquidatorSvcMinted,) = svce.getAccountInformation(liquidator);
        assertEq(liquidatorSvcMinted, amountToMint);
    }

    function testUserHasNoMoreDebt() public liquidated {
        (uint256 userSvcMinted,) = svce.getAccountInformation(user);
        assertEq(userSvcMinted, 0);
    }

    /////////////////////////////////
    // View & Pure Function Tests //
    ////////////////////////////////

    function testGetCollateralTokenPriceFeed() public view {
        address priceFeed = svce.getCollateralTokenPriceFeed(weth);
        assertEq(priceFeed, ethUsdPriceFeed);
    }

    function testGetCollateralTokens() public view {
        address[] memory collateralTokens = svce.getCollateralTokens();
        assertEq(collateralTokens[0], weth);
    }

    function testGetMinHealthFactor() public view {
        uint256 minHealthFactor = svce.getMinHealthFactor();
        assertEq(minHealthFactor, MIN_HEALTH_FACTOR);
    }

    function testGetLiquidationThreshold() public view {
        uint256 liquidationThreshold = svce.getLiquidationThreshold();
        assertEq(liquidationThreshold, LIQUIDATION_THRESHOLD);
    }

    function testGetAccountCollateralValueFromInformation() public depositedCollateral {
        (, uint256 collateralValue) = svce.getAccountInformation(user);
        uint256 expectedCollateralValue = svce.getUsdValue(weth, amountCollateral);
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetCollateralBalanceOfUser() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(svce), amountCollateral);
        svce.depositCollateral(weth, amountCollateral);
        vm.stopPrank();
        uint256 collateralBalance = svce.getCollateralBalanceOfUser(user, weth);
        assertEq(collateralBalance, amountCollateral);
    }

    function testGetAccountCollateralValue() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(svce), amountCollateral);
        svce.depositCollateral(weth, amountCollateral);
        vm.stopPrank();
        uint256 collateralValue = svce.getAccountCollateralValue(user);
        uint256 expectedCollateralValue = svce.getUsdValue(weth, amountCollateral);
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetSvc() public view {
        address svcAddress = svce.getSvc();
        assertEq(svcAddress, address(svc));
    }

    function testLiquidationPrecision() public view {
        uint256 expectedLiquidationPrecision = 100;
        uint256 actualLiquidationPrecision = svce.getLiquidationPrecision();
        assertEq(actualLiquidationPrecision, expectedLiquidationPrecision);
    }
}
