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
    error DSCEngine__HealthFactorNotImproved();

    ////////////////////////
    // State Variables    //
    ////////////////////////
    uint256 private constant ADDITIONNAL_FEED_PRECISION = 1e10; // to bring price feed to 18 decimals
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 50% collateralization ratio / 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100; // precision for liquidation threshold
    uint256 private constant MIN_HEALTH_FACTOR = 1e18; // 1.0 with 18 decimals of precision
    uint216 private constant LIQUIDATION_BONUS = 10; // 10% bonus for liquidators

    // mappinngs of collateral token addresses
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
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed token,
        uint256 amount
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
     * @notice Inicializa tokens de colateral, price feeds e o DSC.
     * @dev Mapeia `tokenAddresses` para `priceFeedAddresses` e define `i_dsc`.
     * @param tokenAddresses Tokens aceitos como colateral.
     * @param priceFeedAddresses Feeds Chainlink USD correspondentes.
     * @param dscAddress Endereço do contrato DSC.
     * @custom:reverts DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength se tamanhos divergem.
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
     * @notice Deposita colateral e mina DSC na mesma transação.
     * @dev Chama `depositCollateral` e `mintDsc` em sequência.
     * @param tokenCollateralAddress Endereço do token de colateral.
     * @param amountCollateral Quantidade de colateral.
     * @param amountDscToMint Quantidade de DSC.
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
     * @notice Deposita token de colateral no protocolo.
     * @dev Atualiza saldo e transfere tokens para o contrato.
     * @param tokenCollateralAddress Endereço do token aceito.
     * @param amountCollateral Quantidade a depositar.
     * @custom:reverts DSCEngine__NeedsMoreThanZero, DSCEngine__NotAllowedToken, DSCEngine__TransferFailed.
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
     * @notice Resgata parte do colateral depositado.
     * @dev Atualiza saldo, transfere ao usuário e checa health factor.
     * @param tokenCollateralAddress Token de colateral.
     * @param amountCollateral Quantidade a resgatar.
     * @custom:reverts DSCEngine__NeedsMoreThanZero, DSCEngine__TransferFailed, DSCEngine__BreaksHealthFactor.
     */
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public moreThanZero(amountCollateral) nonReentrant {
        _redeemCollateral(
            tokenCollateralAddress,
            amountCollateral,
            msg.sender,
            msg.sender
        );
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Mina DSC para o chamador.
     * @dev Incrementa dívida, valida health factor e chama `i_dsc.mint`.
     * @param amountDscToMint Quantidade de DSC.
     * @custom:reverts DSCEngine__NeedsMoreThanZero, DSCEngine__BreaksHealthFactor, DSCEngine__MintFailed.
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
     * @notice Queima DSC e resgata colateral em uma única chamada.
     * @dev Primeiro queima DSC, depois resgata colateral.
     * @param tokenCollateralAddress Token de colateral.
     * @param amountCollateral Quantidade de colateral.
     * @param amountDscToBurn Quantidade de DSC a queimar.
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
     * @notice Queima DSC do chamador para reduzir dívida.
     * @dev Transfere DSC ao contrato e chama `burn`.
     * @param amount Quantidade de DSC.
     * @custom:reverts DSCEngine__NeedsMoreThanZero, DSCEngine__TransferFailed.
     */
    function burnDsc(uint256 amount) public moreThanZero(amount) nonReentrant {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // i don't think this is necessary but just in case
    }

    /**
     * @notice Liquida usuário com health factor < 1.0.
     * @dev Cobre `debtToCover`, confisca colateral + bônus e melhora HF.
     * @param collateralAddress Token de colateral a receber.
     * @param user Usuário a ser liquidado.
     * @param debtToCover Quantidade de DSC a cobrir.
     * @custom:reverts DSCEngine__HealthFactorOk, DSCEngine__TransferFailed, DSCEngine__HealthFactorNotImproved.
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
            revert DSCEngine__HealthFactorOk();
        }

        // 2. Calcula quanto colateral o liquidador receberá
        // Converte o valor da dívida DSC para quantidade de tokens de colateral
        // Exemplo: $100 DSC → 0.05 ETH (se ETH = $2000)
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(
            collateralAddress,
            debtToCover
        );

        // 3. Adiciona bônus de 10% como incentivo para o liquidador
        // Cálculo: (quantidade * 10) / 100
        // Exemplo: (0.05 ETH * 10) / 100 = 0.005 ETH
        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        // 4. Calcula o total de colateral a ser resgatado (dívida + bônus)
        // Exemplo: 0.05 ETH + 0.005 ETH = 0.055 ETH
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered +
            bonusCollateral;
        _redeemCollateral(
            collateralAddress,
            totalCollateralToRedeem,
            user,
            msg.sender
        );

        // 5. Queima a dívida DSC do usuário liquidado
        _burnDsc(debtToCover, user, msg.sender);

        // 6. Verifica se o health factor do usuário melhorou após a liquidação
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }

        // 7. Garantir que o liquidador não quebre seu próprio health factor
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor() external view {}

    /////////////////////////////////////////
    // Private and Internal View Functions //
    /////////////////////////////////////////

    /**
     * @notice Queima DSC em nome de outro usuário.
     * @dev Decrementa dívida, transfere DSC ao contrato e chama `i_dsc.burn`.
     * @param amountDscToBurn Quantidade de DSC a queimar.
     * @param onBehalfOf Usuário cuja dívida será reduzida.
     * @param dscFrom Endereço de onde os DSC serão transferidos.
     * @dev Ninguém chama essa função antes de verificar o health factor.
     * @custom:reverts DSCEngine__TransferFailed.
     */
    function _burnDsc(
        uint256 amountDscToBurn,
        address onBehalfOf,
        address dscFrom
    ) private {
        // reduce the minted DSC amount
        s_dscMinted[onBehalfOf] -= amountDscToBurn;

        // transfer DSC from user to DSCEngine contract
        bool success = i_dsc.transferFrom(
            dscFrom,
            address(this),
            amountDscToBurn
        );

        // check if transfer was successful
        if (!success) {
            revert DSCEngine__TransferFailed();
        }

        i_dsc.burn(amountDscToBurn); // burn the DSC tokens
        _revertIfHealthFactorIsBroken(msg.sender); // i don't think this is necessary but just in case
    }

    /**
     * @notice Função utilitária privada para resgatar colateral entre duas contas
     * @dev Decrementa o saldo de colateral de `from`, emite `CollateralRedeemed`,
     *      e transfere os tokens de colateral do contrato para `to` via `IERC20.transfer`.
     *      Utilizada por `redeemCollateral` (retirada pelo próprio usuário) e `liquidate`.
     * @param tokenCollateralAddress Endereço do token ERC20 de colateral
     * @param amountCollateral Quantidade de colateral a resgatar (em wei)
     * @param from Endereço do devedor/doador do colateral a ser reduzido
     * @param to Endereço do recebedor do colateral transferido
     *
     * Requisitos:
     * - `amountCollateral` Deve ser maior que zero no chamador externo (verificado fora)
     * - `from` Deve ter saldo suficiente (subtração sob Solidity >=0.8 reverte em underflow)
     * - Transferência `IERC20.transfer(to, amountCollateral)` deve suceder
     *
     * Efeitos e eventos:
     * - Atualiza `s_collateralDeposited[from][tokenCollateralAddress]`
     * - Emite `CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral)`
     * - Move tokens do contrato para `to`
     *
     * Segurança:
     * - Não marcado com `nonReentrant`; pressupõe que o chamador externo aplica o guard
     * @custom:reverts DSCEngine__TransferFailed se a transferência do token falhar
     */
    function _redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        address from,
        address to
    ) private {
        // 1. Update user's collateral balance
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;

        // 2. Emit event for successful redemption
        emit CollateralRedeemed(
            from,
            to,
            tokenCollateralAddress,
            amountCollateral
        );

        // 3. Transfer collateral tokens back to user
        bool success = IERC20(tokenCollateralAddress).transfer(
            to,
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

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
     * @notice Calcula o health factor (HF) do usuário.
     * @dev HF = (colateral_USD * THRESHOLD / PRECISION) / dívida_DSC.
     * @param user Usuário alvo.
     * @return Health factor com 18 decimais.
     * @custom:note Reverte se `totalDscMinted == 0` (divisão por zero).
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

    /**
     * @notice Reverte se HF do usuário estiver abaixo do mínimo.
     * @dev Calcula `_healthFactor(user)` e compara com `MIN_HEALTH_FACTOR`.
     * @param user Usuário alvo.
     * @custom:reverts DSCEngine__BreaksHealthFactor.
     */
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
     * @notice Converte USD (18d) em quantidade do token.
     * @dev Usa preço Chainlink (8d) ajustado para 18d.
     * @param token Token de colateral.
     * @param usdAmountInWei Valor USD (18 decimais).
     * @return Quantidade de tokens (18 decimais).
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
        return
            (usdAmountInWei * PRECISION) /
            (uint256(price) * ADDITIONNAL_FEED_PRECISION);
    }

    /**
     * @notice Retorna o valor total em USD do colateral do usuário.
     * @dev Soma `getUsdValue` para todos os tokens aceitos.
     * @param user Endereço do usuário.
     * @return totalCollateralValueInUsd Valor em USD (18 decimais).
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
     * @notice Converte quantidade do token para USD.
     * @dev Preço Chainlink (8d) ajustado para 18d.
     * @param token Token de colateral.
     * @param amount Quantidade do token.
     * @return Valor em USD (18 decimais).
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

    // return the account information for msg.sender
    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        // return the account information for the specified user
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }
}
