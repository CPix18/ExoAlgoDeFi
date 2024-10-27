//SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { StableValueCoin } from "./StableValueCoin.sol";
import { SVCTreasury } from "./SVCTreasury.sol";
import { OracleLib, AggregatorV3Interface } from "./libraries/OracleLib.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { console2 } from "lib/forge-std/src/Test.sol";

/*
 * @title Stable Value Coin Engine
 * @author Collin Pixley
 * Designed to be minimalistic
 * Properties: Exogenous, Value Pegged, Algo-based
 * Similar to DAI/MakerDAO if no governance, no fees, and only backed by ETH and Grocery Index
 * @notice This is based loosly on DAI/MakerDAO system but for Grocery Spend
 * @notice This contract will be the base for how the stablecoin functions
 * Based on Code Audited by CodeHawks on 8-25-23
 * @disclaimer THIS CODE IS NOT AUDITED
 */

contract SVCEngine is ReentrancyGuard {
    ///////////////////
    // Errors
    ///////////////////
    error SVCEngine__NeedsMoreThanZero();
    error SVCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error SVCEngine__TokenNotAllowed(address token);
    error SVCEngine__TransferFailed();
    error SVCEngine__BreaksHealthFactor(uint256 healthFactor);
    error SVCEngine__MintFailed();
    error SVCEngine__HealthFactorIsOk();
    error SVCEngine__HealthFactorNotImproved();

    ///////////////////
    // Types
    ///////////////////
    using OracleLib for AggregatorV3Interface;

    ///////////////////
    // State Variables
    ///////////////////
    StableValueCoin private immutable i_svc;
    SVCTreasury private immutable i_svct;

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant FEED_PRECISION = 1e8;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // Need to be 200% over-collateralized
    uint256 private constant LIQUIDATION_BONUS = 10; // Get assets at a 10% discount when liquidating
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    //uint256 private constant TREASURY_FEE = 5; // 5% fee for treasury
    //uint256 private constant TREASURY_DIV = 2;

    mapping(address collateralToken => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address collateralToken => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amount) private s_SVCMinted; // previously had this set to amountSVCMinted
    address[] private s_collateralTokens;

    ///////////////////
    // Events
    ///////////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemFrom, address indexed redeemTo, address indexed token, uint256 amount
    );
    //event TreasuryFeePaid(address indexed from, address indexed to, address tokenCollateralAddress, uint256
    // treasuryFee);
    event ContractInitialized(address svcAddress, address svcTreasury);

    ///////////////////
    // Modifiers
    ///////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert SVCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert SVCEngine__TokenNotAllowed(token);
        }
        _;
    }

    ///////////////////
    // Functions
    ///////////////////
    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address svcAddress,
        address payable svcTreasury
    ) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert SVCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_svc = StableValueCoin(svcAddress);
        i_svct = SVCTreasury(svcTreasury);

        emit ContractInitialized(svcAddress, svcTreasury); // Emit the initialization event
    }

    ///////////////////
    // External Functions
    ///////////////////

    /*
    * @param tokenCollateralAddress The address of the token to deposit as collateral
    * @param amountCollateral The amount of the token to deposit as collateral
    * @param amountSVCToMint The amount of SVC to mint
    * @notice This function will deposit your collateral and mint SVC in one transaction
    */

    function depositCollateralAndMintSVC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountSVCToMint
    )
        external
    {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintSVC(amountSVCToMint);
    }

    function redeemCollateralForSVC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 svcAmountToBurn
    )
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
    {
        _burnSvc(svcAmountToBurn, msg.sender, msg.sender);
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnSvc(uint256 amount) external moreThanZero(amount) {
        _burnSvc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
    * @param collateral the erc20 collateral address to liquidate
    * @param address of the user with broken health factor
    * @param debtToCover is the amount needed to burn
    * @notice This function will liquidate the collateral of the user with a broken health factor
    * @notice You will get paid for liquidating the collateral
    * @notice protocol aims to stay over collateralized by 200%
    * @notice If collateral to debt drops to 100% or below, liquidator won't get paid
    */
    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    )
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert SVCEngine__HealthFactorIsOk();
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * (LIQUIDATION_BONUS)) / LIQUIDATION_PRECISION;
        _redeemCollateral(collateral, tokenAmountFromDebtCovered + bonusCollateral, user, msg.sender);
        //_payTreasuryFee(collateral, treasuryFee, user, address(i_svct));
        _burnSvc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert SVCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    ///////////////////
    // Public Functions
    ///////////////////

    function mintSVC(uint256 amountSVCToMint) public moreThanZero(amountSVCToMint) nonReentrant {
        s_SVCMinted[msg.sender] += amountSVCToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_svc.mint(msg.sender, amountSVCToMint);

        if (minted != true) {
            revert SVCEngine__MintFailed();
        }
    }

    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert SVCEngine__TransferFailed();
        }
    }

    /////////////////////
    // Private Functions
    /////////////////////

    function _redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        address from,
        address to
    )
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        console2.log("From:", from);
        console2.log("To:", to);
        console2.log("Token Address:", tokenCollateralAddress);
        console2.log("Amount Collateral:", amountCollateral);
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert SVCEngine__TransferFailed();
        }
    }
    /*
    function _payTreasuryFee(
        address tokenCollateralAddress,
        uint256 treasuryFee,
        address from,
        address to
    )
        private
        moreThanZero(treasuryFee)
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= treasuryFee;
        emit TreasuryFeePaid(from, to, tokenCollateralAddress, treasuryFee);
        bool success = IERC20(tokenCollateralAddress).transferFrom(from, to, treasuryFee);
        if (!success) {
            revert SVCEngine__TransferFailed();
        }
    }
    */

    function _burnSvc(uint256 svcAmountToBurn, address onBehalfOf, address svcFrom) private {
        s_SVCMinted[onBehalfOf] -= svcAmountToBurn;

        bool success = i_svc.transferFrom(svcFrom, address(this), svcAmountToBurn);
        if (!success) {
            revert SVCEngine__TransferFailed();
        }
        i_svc.burn(svcAmountToBurn);
    }

    ///////////////////////////////////////////
    // Private & Internal View & Pure Functions
    ///////////////////////////////////////////

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalSVCMinted, uint256 collateralValueInUsd)
    {
        totalSVCMinted = s_SVCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalSVCMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalSVCMinted, collateralValueInUsd);
    }

    function _getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function _calculateHealthFactor(
        uint256 totalSVCMinted,
        uint256 collateralValueInUsd
    )
        internal
        pure
        returns (uint256)
    {
        if (totalSVCMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalSVCMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert SVCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    ////////////////////////////////////////////
    // External & Public View & Pure Functions
    ////////////////////////////////////////////

    function calculateHealthFactor(
        uint256 totalVscMinted,
        uint256 collateralValueInUsd
    )
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalVscMinted, collateralValueInUsd);
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalVscMinted, uint256 collateralValueInUsd)
    {
        return _getAccountInformation(user);
    }

    function getUsdValue(
        address token,
        uint256 amount // in WEI
    )
        external
        view
        returns (uint256)
    {
        return _getUsdValue(token, amount);
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 index = 0; index < s_collateralTokens.length; index++) {
            address token = s_collateralTokens[index];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += _getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }
    /*
    function getTreasuryFee() external pure returns (uint256) {
        return TREASURY_FEE;
    }
    */

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getSvc() external view returns (address) {
        return address(i_svc);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
}
