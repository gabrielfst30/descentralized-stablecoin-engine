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
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
// interface for ERC20 tokens to make interactions
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    AggregatorV3Interface
} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

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
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();

    ////////////////////////
    // State Variables    //
    ////////////////////////
    uint256 private constant ADDITIONNAL_FEED_PRECISION = 1e10; // to bring price feed to 18 decimals
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 50% collateralization ratio / 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100; // precision for liquidation threshold
    uint256 private constant MIN_HEALTH_FACTOR = 1e18; // 1.0 with 18 decimals of precision
    uint216 private constant LIQUIDATION_BONUS = 10; // 10% bonus for liquidators

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
    event CollateralRedeemed(
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

    /**
     * @notice Allows users to deposit collateral and mint DSC tokens in a single transaction
     * @dev Convenience function that combines depositCollateral and mintDsc operations sequentially
     * @param tokenCollateralAddress The contract address of the ERC20 collateral token to deposit (ETH or BTC)
     * @param amountCollateral The amount of collateral tokens to deposit (in wei)
     * @param amountDscToMint The amount of DSC tokens to mint (in wei, 18 decimals)
     *
     * Requirements:
     * - Both amounts must be greater than zero
     * - Token must be an allowed collateral type
     * - User must maintain 200% overcollateralization after minting
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress, // collateral token address
        uint256 amountCollateral, // amount of collateral to deposit
        uint256 amountDscToMint // amount of DSC to mint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

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
        public
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

    /**
     * @notice Allows users to withdraw their deposited collateral from the system
     * @dev Removes collateral from user's balance and transfers tokens back. Health factor must remain >= 1.0 after withdrawal.
     * @param tokenCollateralAddress The contract address of the ERC20 collateral token to redeem (ETH or BTC)
     * @param amountCollateral The amount of collateral tokens to withdraw (in wei)
     *
     * Requirements:
     * - amountCollateral must be greater than zero
     * - User must have sufficient collateral deposited
     * - Health factor must remain >= MIN_HEALTH_FACTOR (1.0) after withdrawal
     * - Transfer operation must succeed
     *
     * Process:
     * 1. Decrements s_collateralDeposited[msg.sender][token] to update user's collateral balance
     * 2. Emits CollateralRedeemed event for tracking
     * 3. Transfers collateral tokens from contract back to user via IERC20.transfer()
     * 4. Validates health factor remains above minimum threshold post-withdrawal
     *
     * @custom:security Protected by nonReentrant modifier to prevent reentrancy attacks
     * @custom:reverts DSCEngine__NeedsMoreThanZero if amountCollateral is 0
     * @custom:reverts DSCEngine__TransferFailed if token transfer fails
     * @custom:reverts DSCEngine__BreaksHealthFactor if withdrawal causes undercollateralization
     */
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public moreThanZero(amountCollateral) nonReentrant {
        // 1. Update user's collateral balance
        s_collateralDeposited[msg.sender][
            tokenCollateralAddress
        ] -= amountCollateral;

        // 2. Emit event for successful redemption
        emit CollateralRedeemed(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );

        // 3. Transfer collateral tokens back to user
        bool success = IERC20(tokenCollateralAddress).transfer(
            msg.sender,
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }

        // 4. Verify health factor remains safe after withdrawal
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Mints DSC tokens to the caller if they maintain sufficient collateralization
     * @dev Creates new DSC tokens and assigns them to msg.sender. Requires 200% overcollateralization.
     * The function updates the user's minted DSC balance, validates their health factor,
     * then calls the DSC contract to mint tokens. Reverts if health factor drops below minimum threshold.
     * @param amountDscToMint The amount of DSC tokens to mint (in wei, 18 decimals)
     *
     * Requirements:
     * - amountDscToMint must be greater than zero
     * - User must have deposited sufficient collateral (minimum 200% of DSC value)
     * - Health factor must remain >= MIN_HEALTH_FACTOR (1.0) after minting
     * - The mint operation on the DSC contract must succeed
     *
     * Process:
     * 1. Increments s_dscMinted[msg.sender] to track total DSC minted by user
     * 2. Validates health factor: (collateral * 50%) / totalDscMinted >= 1.0
     * 3. Calls i_dsc.mint() to create and transfer DSC tokens to user
     * 4. Reverts if mint fails or health factor is broken
     *
     * Example: User with $1000 collateral can mint up to $500 DSC (200% ratio)
     *
     * @custom:security Protected by nonReentrant modifier to prevent reentrancy attacks
     * @custom:reverts DSCEngine__NeedsMoreThanZero if amountDscToMint is 0
     * @custom:reverts DSCEngine__BreaksHealthFactor if collateralization drops below 200%
     * @custom:reverts DSCEngine__MintFailed if the DSC contract mint operation fails
     */
    function mintDsc(
        uint256 amountDscToMint
    ) public moreThanZero(amountDscToMint) nonReentrant {
        s_dscMinted[msg.sender] += amountDscToMint; // track how much DSC the user has minted
        _revertIfHealthFactorIsBroken(msg.sender);

        // mint DSC to the user
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);

        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    /**
     * @notice Burns DSC and redeems collateral in a single transaction
     * @dev Convenience function that burns DSC first to improve health factor, then redeems collateral.
     * The order is important: burning DSC reduces debt before withdrawing collateral.
     * @param tokenCollateralAddress The ERC20 collateral token address to redeem
     * @param amountCollateral The amount of collateral to withdraw
     * @param amountDscToBurn The amount of DSC tokens to burn
     *
     * @custom:security Health factor is checked in redeemCollateral after both operations complete
     */
    function redeemCollateralForDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToBurn
    ) external {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // redeem collateral already checks health factor
    }

    /**
     * @notice Burns DSC tokens to reduce user's debt
     * @dev Transfers DSC from user to contract then destroys them. Improves health factor by reducing debt.
     * @param amount The amount of DSC tokens to burn
     *
     * Requirements:
     * - User must have at least `amount` DSC minted
     * - User must approve DSCEngine to spend their DSC tokens
     *
     * @custom:note Health factor check is redundant here since burning DSC always improves collateralization
     */
    function burnDsc(uint256 amount) public moreThanZero(amount) nonReentrant {
        // reduce the minted DSC amount
        s_dscMinted[msg.sender] -= amount;

        // transfer DSC from user to DSCEngine contract
        bool success = i_dsc.transferFrom(msg.sender, address(this), amount);

        // check if transfer was successful
        if (!success) {
            revert DSCEngine__TransferFailed();
        }

        i_dsc.burn(amount); // burn the DSC tokens
        _revertIfHealthFactorIsBroken(msg.sender); // i don't think this is necessary but just in case
    }

    /**
     * @notice Liquida a posição de um usuário subcapitalizado, queimando sua dívida DSC e confiscando colateral
     * @dev Permite que qualquer um liquide usuários com health factor < 1.0. Liquidador recebe bônus de 10% como incentivo.
     *
     * @param collateralAddress Endereço do token de colateral a ser confiscado (ETH ou BTC)
     * @param user Endereço do usuário subcapitalizado (health factor < 1.0)
     * @param debtToCover Quantidade de dívida DSC a pagar (em wei, 18 decimais)
     *
     * Cálculos da Liquidação:
     * 1. Converte dívida DSC em quantidade de colateral:
     *    tokenAmount = getTokenAmountFromUsd(collateralAddress, debtToCover)
     *    Exemplo: $100 DSC → 0.05 ETH (se ETH = $2000)
     * 
     * 2. Calcula bônus de 10% para o liquidador:
     *    bonus = (tokenAmount * 10) / 100
     *    Exemplo: (0.05 ETH * 10) / 100 = 0.005 ETH
     * 
     * 3. Total de colateral a receber:
     *    total = tokenAmount + bonus
     *    Exemplo: 0.05 + 0.005 = 0.055 ETH (vale $110)
     * 
     * Resultado: Liquidador paga $100 DSC e recebe $110 em colateral (lucro de $10)
     *
     * @custom:example User tem $140 ETH e $100 DSC mintado. Preço cai, HF < 1.0. Liquidador cobre $100 DSC e recebe $110 em ETH.
     * @custom:reverts DSCEngine__HealthFactorOk se health factor >= 1.0 (usuário não é liquidável)
     * @custom:security Protegido por nonReentrant. Segue padrão CEI (Checks-Effects-Interactions)
     */
    function liquidate(
        address collateralAddress,
        address user,
        uint256 debtToCover
    ) external moreThanZero(debtToCover) nonReentrant {
        // Verifica o health factor do usuário antes da liquidação
        uint256 startingUserHealthFactor = _healthFactor(user);

        // 1. Verifica se o usuário pode ser liquidado (HF < 1.0)
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk(startingUserHealthFactor);
        }

        // 2. Calcula quanto colateral o liquidador receberá
        // Converte o valor da dívida DSC para quantidade de tokens de colateral
        // Exemplo: $100 DSC → 0.05 ETH (se ETH = $2000)
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(
            collateral,
            debtToCover
        );
        
        // 3. Adiciona bônus de 10% como incentivo para o liquidador
        // Cálculo: (quantidade * 10) / 100
        // Exemplo: (0.05 ETH * 10) / 100 = 0.005 ETH
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        
        // 4. Calcula o total de colateral a ser resgatado (dívida + bônus)
        // Exemplo: 0.05 ETH + 0.005 ETH = 0.055 ETH
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
    }

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
     * @dev Health factor formula: (collateralValueInUsd * LIQUIDATION_THRESHOLD * PRECISION) / (LIQUIDATION_PRECISION * totalDscMinted)
     *
     * The health factor measures how well-collateralized a user's position is:
     * - Health Factor >= 1.0: Position is safe (sufficiently collateralized)
     * - Health Factor < 1.0: Position is undercollateralized and can be liquidated
     *
     * @param user The address of the user whose health factor is being calculated
     * @return The health factor with 18 decimal precision (1e18 = 1.0)
     *
     * Collateralization Rules:
     * - LIQUIDATION_THRESHOLD = 50 means users can mint maximum 50% of their collateral value
     * - This enforces 200% overcollateralization (collateral / DSC = 2.0)
     * - Example: $1000 collateral → max $500 DSC mintable → 200% collateralization
     *
     * Health Factor Interpretation:
     * - HF = 1.0 (1e18): At liquidation threshold, exactly 200% collateralization
     * - HF = 1.5 (1.5e18): 50% above minimum, 300% collateralization (very safe)
     * - HF = 0.8 (0.8e18): Below threshold, 160% collateralization (liquidatable)
     *
     * Calculation Example:
     * Given: $1000 collateral, $400 DSC minted
     * 1. Adjusted collateral = $1000 * 50 / 100 = $500
     * 2. Health Factor = ($500 * 1e18) / $400 = 1.25e18
     * 3. Interpretation: 1.25 = 25% safety margin above minimum
     * 4. Actual collateralization: $1000 / $400 = 250%
     *
     * @custom:security Returns max uint256 if no DSC minted (division by zero protection needed)
     */
    function _healthFactor(address user) private view returns (uint256) {
        // 1. get the total collateral value
        // 2. get the total DSC minted
        (
            uint256 totalDscMinted,
            uint256 collateralValueInUsd
        ) = _getAccountInformation(user);
        // 3. calculate the health factor and return it
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        // 4. return health factor
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    // 1. Check the user's health factor (do they have enough collateral?)
    // 2. Revert if they don't good factor
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    /////////////////////////////////////////
    // Public and External View Functions ///
    /////////////////////////////////////////

    /**
     * @notice Converte um valor em USD para a quantidade equivalente de tokens de colateral
     * @dev Usa Chainlink price feeds para obter o preço atual do token e calcula a quantidade necessária
     * 
     * Cálculo: quantidade_token = (valor_USD * 1e18) / (preço_token * 1e10)
     * 
     * Exemplo prático:
     * - Valor USD desejado = $1000 (passa como 1000e18)
     * - Preço ETH = $2000 (retorna como 2000e8 do Chainlink)
     * - Cálculo: (1000e18 * 1e18) / (2000e8 * 1e10) = 0.5e18 = 0.5 ETH
     * 
     * @param token Endereço do token de colateral (ETH ou BTC)
     * @param usdAmountInWei Valor em USD com 18 decimais (ex: 1000e18 = $1000)
     * @return Quantidade de tokens equivalente ao valor USD (com 18 decimais)
     * 
     * @custom:precision Chainlink retorna preços com 8 decimais, multiplicamos por 1e10 para chegar a 18 decimais
     */
    function getTokenAmountFromUsd(
        address token,
        uint256 usdAmountInWei
    ) public view returns (uint256) {
        // Obtém o price feed do Chainlink para o token
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        // Busca o preço atual (retorna com 8 decimais)
        (, int256 price, , , ) = priceFeed.latestRoundData();
        // Fórmula: (USD_valor * 1e18) / (preço * 1e10)
        // Exemplo: ($1000 * 1e18) / ($2000e8 * 1e10) = 0.5 ETH
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONNAL_FEED_PRECISION);
    }

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
