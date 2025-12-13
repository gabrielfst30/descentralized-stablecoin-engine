// SPDX-License-Identifier: MIT

// Layout of the contract file:
// version
// imports
// errors
// interfaces, libraries, contract

// Inside Contract:
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.20;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
// interface for ERC20 tokens to make interactions
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title Decentralized Stable Coin
 * @author Gabriel Santa Ritta
 * 
 * Peg: 1 DSC = 1 USD
 * This stablecoin has the properties:
 * - Collateral: Exogenous stable coin (ETH and BTC)
 * - Minting: Algorithmic
 * - Dollar Pegged
 * 
 * It is similar to DAI if DAI had no governance, no fees, and only used ETH and BTC as collateral.
 * 
 * Our DSC system should always be overcollateralized. At no point, should the value of 
   all the collateral <= the value of all the DSC.
 * 
 * @notice This contract is the core of the DSC System.
 */

contract DSCEngine is ReentrancyGuard {
    ////////////////
    // Errors    //
    ///////////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();

    ////////////////////////
    // State Variables    //
    ////////////////////////
    uint265 private constant ADDITIONNAL_FEED_PRECISION = 1e10; // to bring price feed to 18 decimals
    uint265 private constant PRECISION = 1e18;

    // array of collateral token addresses
    mapping(address token => address priceFeed) private s_priceFeeds; // token address -> price feed address
    mapping(address user => mapping(address token => uint256 amount))
        private s_collateralDeposited; // user -> token -> amount deposited
    mapping(address user => uint256 amountDscMinted) private s_dscMinted; // user -> amount of DSC minted
    address[] private s_collateralTokens; // array of collateral token addresses

    DecentralizedStableCoin private immutable i_dsc; // stable coin contract

    ///////////////
    // Events    //
    ///////////////
    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 indexed amount
    );

    ////////////////
    // Modifiers //
    ///////////////
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    //////////////////
    // Functions /////
    //////////////////

    /**
     * @notice Initializes the DSC Engine with collateral tokens, price feeds, and the DSC token contract
     * @dev Sets up the mapping between collateral tokens and their corresponding Chainlink price feeds
     * @param tokenAddresses Array of ERC20 collateral token contract addresses (e.g., WETH, WBTC)
     * @param priceFeedAddresses Array of Chainlink price feed contract addresses for USD pricing (e.g., ETH/USD, BTC/USD)
     * @param dscAddress The contract address of the DecentralizedStableCoin token
     *
     * Validations performed:
     * - Ensures tokenAddresses and priceFeedAddresses arrays have the same length
     * - Each token address is mapped to its corresponding price feed address
     *
     * Initializations performed:
     * - Maps each collateral token to its USD price feed in s_priceFeeds mapping
     * - Sets the immutable DSC token contract reference (i_dsc)
     * - Establishes the foundation for collateral valuation and DSC minting/burning
     *
     * @custom:security The constructor validates array lengths to prevent misconfiguration
     * @custom:note Price feeds should be Chainlink AggregatorV3Interface compatible contracts
     */
    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address dscAddress
    ) {
        // USD Price Feeds
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        // map token to price feed (ETH/USD and BTC/USD)
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i]; // map token to price feed
            s_collateralTokens.push(tokenAddresses[i]); // store the collateral token
        }

        // initialize DSC contract
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ////////////////////////
    // External Functions //
    ////////////////////////

    // deposit collateral and mint DSC
    function depositCollateralAndMintDsc() external {}

    /**
     * @notice Allows users to deposit collateral tokens into the system
     * @dev This function only deposits collateral without minting DSC tokens
     * @param tokenCollateralAddress The contract address of the ERC20 collateral token to deposit (ETH or BTC)
     * @param amountCollateral The amount of collateral tokens to deposit (in wei for ETH or satoshis for BTC)
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        // update the deposited collateral mapping
        s_collateralDeposited[msg.sender][
            tokenCollateralAddress
        ] += amountCollateral;

        // emit event of collateral deposit
        emit CollateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );

        // transfer the collateral from the user to the DSCEngine contract
        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateral() external {}

    /**
     * @param amountDscToMint The amount of DSC tokens to mint (in wei, 18 decimals)
     * @notice they must have more collateral value than the minimum threshold
     **/

    function mintDsc(
        uint256 amountDscToMint
    ) external moreThanZero(amountDscToMint) nonReentrant {
        s_dscMinted[msg.sender] += amountDscToMint; // track how much DSC the user has minted
        revertIfHealthFactorIsBroken(msg.sender);
    }

    // redeem collateral by burning DSC
    function redeemCollateralForDsc() external {}

    // burn DSC tokens
    function burnDsc() external {}

    // liquidate undercollateralized users
    function liquidate() external {}

    function getHealthFactor() external view {}

    /////////////////////////////////////////
    // Private and Internal View Functions //
    /////////////////////////////////////////

    // return the account information for a user
    function _getAccountInformation(
        address user
    )
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        // 1. return total DSC minted
        totalDscMinted = s_dscMinted[user];

        // 2. return collateral value in USD
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     * @notice Calculates the health factor for a user to determine proximity to liquidation
     * @dev Health factor = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / totalDscMinted
     * @param user The address of the user whose health factor is being calculated
     * @return healthFactor The health factor with 18 decimal precision (< 1.0 = liquidatable)
     **/

    function _healthFactor(address user) private view returns (uint256) {
        // 1. get the total collateral value
        // 2. get the total DSC minted
        // 3. calculate the health factor and return it
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        // 1. Check the user's health factor (do they have enough collateral?)
        // 2. Revert if they don't good factor
    }

    /////////////////////////////////////////
    // Public and External View Functions ///
    /////////////////////////////////////////

    /**
     * @notice Calculates the total USD value of all collateral deposited by a user
     * @dev Iterates through all accepted collateral tokens and sums their USD values.
     * For each token: gets user's deposited amount → converts to USD via getUsdValue() → accumulates total
     * @param user The address of the user to check collateral value for
     * @return totalCollateralValueInUsd The total value of user's collateral in USD (18 decimals)
     * 
     * Process:
     * 1. Loop through s_collateralTokens array (all accepted collateral types)
     * 2. For each token: query s_collateralDeposited[user][token] to get deposited amount
     * 3. Call getUsdValue(token, amount) to convert token amount to USD using Chainlink prices
     * 4. Sum all USD values to get total collateral value
     * 
     * Example: User deposited 2 ETH + 0.1 BTC → returns total USD value (e.g., $6000 + $4000 = $10000)
     */
    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralValueInUsd) {
        // loop through each collateral token, get the amount deposited and the price
        // calculate the USD value and sum it all up
        for (uint i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i]; // get the token address
            uint256 amount = s_collateralDeposited[user][token]; // get the amount deposited
            totalCollateralValueInUsd += getUsdValue(token, amount); // get the USD value and sum it up
        }

        return totalCollateralValueInUsd;
    }

    /**
     * @notice Converts token amount to USD value using Chainlink price feeds
     * @dev Fetches real-time price from Chainlink oracle and calculates USD value with proper decimal handling.
     * Uses price precision constants to convert Chainlink's 8-decimal prices to 18-decimal precision.
     * @param token The address of the token to get price for
     * @param amount The amount of tokens to convert (in wei/smallest unit)
     * @return The USD value with 18 decimal precision
     * 
     * Process:
     * 1. Get Chainlink price feed contract for the token from s_priceFeeds mapping
     * 2. Call latestRoundData() to get current price (returns int256 with 8 decimals)
     * 3. Apply formula: (price * ADDITIONNAL_FEED_PRECISION * amount) / PRECISION
     * 
     * Precision handling:
     * - ADDITIONNAL_FEED_PRECISION (1e10): Converts Chainlink's 8 decimals to 18 decimals
     * - PRECISION (1e18): Maintains 18-decimal precision in final result
     * 
     * Example: getUsdValue(ETH_address, 2e18) with ETH price $3000 → returns $6000 in 18-decimal format
     */
    function getUsdValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        // get the price feed address for the token
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );

        // returns the actual price
        (, int256 price, , , ) = priceFeed.latestRoundData();

        // convert price to uint256
        return
            (uint256(price) * ADDITIONNAL_FEED_PRECISION * amount) / PRECISION;
    }
}
