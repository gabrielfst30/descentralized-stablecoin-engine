// SPDX-License-Identifier: MIT

// Terá nossa invariante/propriedade que queremos testar

// Quais são as invariantes? Quais são as propriedades que sempre devem ser mantidas? Algo que nunca pode mudar?
// 1. O totalSupply do DSC sempre deve ser menor ou igual ao valor total de colateral depositado
// 2. Getter view functions nunca devem reverter <- evergreen invariant

pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantsTest is StdInvariant, Test {
    // aqui vamos ter o setup do nosso teste, onde vamos implantar os contratos e criar o manipulador
    DeployDSC deployer; // variável do tipo DeployDSC
    DSCEngine dscEngine; // variável do tipo DSCEngine
    DecentralizedStableCoin dsc; // variável do tipo DecentralizedStableCoin
    HelperConfig helperConfig; // variável do tipo HelperConfig
    address weth; // endereço do token WETH
    address wbtc; // endereço do token WBTC
    Handler handler; // variável do tipo Handler

    function setUp() external {
        deployer = new DeployDSC(); // instanciando o deployer
        (dsc, dscEngine, helperConfig) = deployer.run(); // rodando o deployer para obter as instâncias dos contratos
        (, , weth, wbtc, ) = helperConfig.activeNetworkConfig(); // pegando os endereços dos tokens do helperConfig
        // targetContract(address(dscEngine)); // definindo o contrato alvo para as invariantes
        handler = new Handler(dscEngine, dsc); // instanciando o manipulador
        targetContract(address(handler)); // definindo o manipulador como o contrato alvo para as invariants
        // Não ligue em resgatar garantias ao menos que exista garantias para resgatar.
    }

    // INVARIANTE: O colateral deve ser maior que o totalSupply do DSC
    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        // pegar o valor total do collateral no protocolo
        // comparar com o debito total do DSC
        uint256 totalSupply = dsc.totalSupply(); // pegando o totalSupply do DSC
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dscEngine)); // pegando o total de WETH depositado no protocolo
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dscEngine)); // pegando o total de WBTC depositado no protocolo

        uint256 wethValue = dscEngine.getUsdValue(weth, totalWethDeposited); // convertendo o total de WETH para USD
        uint256 wbtcValue = dscEngine.getUsdValue(wbtc, totalWbtcDeposited); // convertendo o total de WBTC para USD

        console.log("Valor total de WETH depositado (em USD):", wethValue);
        console.log("Valor total de WBTC depositado (em USD):", wbtcValue);
        console.log("Total Supply do DSC:", totalSupply);
        console.log("Times mintDsc is called:", handler.timesMintIsCalled());

        assert(wethValue + wbtcValue >= totalSupply); // verificando a invariante mesmo que o valor seja 0
    }

    // INVARIANTE: Getter functions nunca devem reverter
    function invariant_getterFunctionsNeverRevert() public view {
        // basic DSC getter
        dsc.totalSupply();

        // collateral getters (safe calls with zero values where applicable)
        dscEngine.getCollateralBalanceOfUser(weth, address(this));
        dscEngine.getCollateralBalanceOfUser(wbtc, address(this));
        dscEngine.getAccountInformation(address(this));

        // all other public/external view getters from DSCEngine
        dscEngine.getCollateralTokens();
        dscEngine.getUsdValue(weth, 0);
        dscEngine.getUsdValue(wbtc, 0);
        dscEngine.getAccountCollateralValue(address(this));
        dscEngine.getTokenAmountFromUsd(weth, 0);
        dscEngine.calculateHealthFactor(0, 0);
        // call placeholder (exists but has empty body)
        dscEngine.getHealthFactor();
    }
}
