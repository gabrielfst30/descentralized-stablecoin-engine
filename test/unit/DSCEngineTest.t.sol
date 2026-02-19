// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {
    AggregatorV3Interface
} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import "forge-std/console.sol";
contract DSCEngineTest is Test {
    DeployDSC deployer; // DeployDSC contract reference
    DecentralizedStableCoin dsc; // DecentralizedStableCoin contract reference
    DSCEngine dscEngine; // DSCEngine contract reference
    HelperConfig helperConfig; // HelperConfig contract reference
    address ethUsdPriceFeed; // ETH/USD price feed address
    address btcUsdPriceFeed; // BTC/USD price feed address
    address weth; // WETH token address

    // A user address for testing
    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether; // 10 ETH as collateral
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether; // Initial ERC20 balance for USER

    /**
     * @notice Inicializa o ambiente de teste com contratos deployados.
     * @dev Cria instâncias de `DeployDSC`, `DecentralizedStableCoin` e `DSCEngine`.
     *      Define o usuário `USER` com saldo inicial de WETH.
     *      Em Anvil (chainid 31337), usa `vm.deal` para fornecer ETH nativo.
     */
    function setUp() external {
        // Create a new instance of the DeployDSC contract
        deployer = new DeployDSC();

        // Deploy the DSC and DSCEngine contracts
        (dsc, dscEngine, helperConfig) = deployer.run();

        // Get the WETH/USD price feed and WETH address
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, , ) = helperConfig
            .activeNetworkConfig();

        if (block.chainid == 31337) {
            vm.deal(USER, STARTING_ERC20_BALANCE);
        }
        // Mint some WETH tokens to the USER for testing (as the deployer/contract owner)
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    /** @dev Constructor Tests */
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    /**
     * @notice Verifica que o construtor de `DSCEngine` reverte se arrays de tokens
     *         e price feeds tiverem tamanhos diferentes.
     * @dev Arrange: cria 1 token e 2 price feeds.
     *      Act/Assert: espera revert com `DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength`.
     */
    function testRevertsIfTokenLenghtDoesntMatchPriceFeedLength() public {
        // Arrange - set up mismatched arrays
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        // Act / Assert - expect the constructor to revert due to length mismatch
        vm.expectRevert(
            DSCEngine
                .DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength
                .selector
        );
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /**
     * @notice Testa se `getUsdValue()` calcula corretamente o valor USD de um token.
     * @dev Arrange: lê o preço atual do feed Chainlink (`latestRoundData()`).
     *      Calcula o valor esperado: (preço * 1e10 * quantidade) / 1e18.
     *      Act: chama `dscEngine.getUsdValue(weth, 15e18)`.
     *      Assert: valida se o valor retornado coincide com o esperado.
     */
    function testGetUsdValue() public {
        uint256 ethAmount = 15e18; // 15 ETH in wei

        // Read price from the configured Chainlink feed
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            ethUsdPriceFeed
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();

        // Match DSCEngine.getUsdValue logic: (price * 1e10 * amount) / 1e18
        uint256 expectedUsdValue = (uint256(price) * 1e10 * ethAmount) / 1e18;

        uint256 actualUsdValue = dscEngine.getUsdValue(weth, ethAmount);

        assertEq(actualUsdValue, expectedUsdValue);
    }

    /**
     * @notice Valida se `getTokenAmountFromUsd()` converte USD (18d) para a quantidade correta de WETH.
     * @dev Arrange: usa `usdAmount = 100e18` (100 USD em 18 casas). Preço mockado é 2000 USD/WETH (8d).
     *      Cálculo esperado pela fórmula do contrato: (usd * 1e18) / (preço * 1e10) = 0.05 WETH.
     *      Act: chama `dscEngine.getTokenAmountFromUsd(weth, usdAmount)`.
     *      Assert: compara com `expectedWeth = 0.05 ether`.
     */
    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether; // 100 * 1e18 (USD em 18 decimais)
        uint256 expectedWeth = 0.05 ether; // $100 / $2000 = 0.05 WETH
        uint256 actualWeth = dscEngine.getTokenAmountFromUsd(weth, usdAmount); // (2000 USD/WETH) / (100 USD)
        assertEq(actualWeth, expectedWeth); // 0.05 == 0.05
    }

    /**
     * @notice Testa se `depositCollateral()` reverte quando a quantidade é zero.
     * @dev Arrange: aprova `dscEngine` a gastar WETH do usuário.
     *      Act: tenta depositar 0 WETH via `startPrank(USER)`.
     *      Assert: espera revert com erro `DSCEngine__NeedsMoreThanZero`.
     */
    function testRevertIfCollateralZero() public {
        vm.startPrank(USER);

        /// @dev Approves dscEngine to spend up to AMOUNT_COLLATERAL of WETH tokens from USER
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        // Expect the depositCollateral function to revert with the DSCEngine__NeedsMoreThanZero error
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);

        // Attempt to deposit zero collateral, which should trigger the revert
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock();
        ranToken.mint(USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dscEngine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);

        /// @dev Approves dscEngine to spend up to AMOUNT_COLLATERAL of WETH tokens from USER
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        // Deposit the collateral
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        // Getting account info after depositing collateral
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine
            .getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0;

        // Calculating expected collateral value in USD
        uint256 expectedDepositAmount = dscEngine.getUsdValue(
            weth,
            AMOUNT_COLLATERAL
        );

        // Asserting that no DSC has been minted yet
        assertEq(totalDscMinted, expectedTotalDscMinted);
        console.log(
            "Collateral Value in USD:",
            totalDscMinted
        );
        console.log(
            "Expected Expected Dsc Minted:",
            expectedTotalDscMinted
        );

        // Expecting collateral value in USD to match the deposited amount
        assertEq(collateralValueInUsd, expectedDepositAmount);
    }
}
