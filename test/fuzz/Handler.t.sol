// SPDX-License-Identifier: MIT
// Será o manipulador que vai restringir a forma como chamamos funções do contrato

pragma solidity ^0.8.30;

import { Test } from "forge-std/Test.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract Handler is Test {
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max; // limitando o tamanho do depósito para evitar overflow

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        dscEngine = _dscEngine;
        dsc = _dsc;
        
        // pegando os endereços dos tokens de colateral do DSCEngine e instanciando os mocks para interagir com eles
        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

    }

    // redeem collateral
    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        // aqui vamos depositar o colateral no protocolo, mas antes disso, precisamos pegar o endereço do colateral com base no collateralSeed, por exemplo, se for 0, pegamos o endereço do WETH, se for 1, pegamos o endereço do WBTC
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        // limitando o tamanho do depósito para evitar overflow
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        // mintando tokens para o msg.sender e aprovando o dscEngine para gastar
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dscEngine), amountCollateral);

        // depositando o colateral no protocolo
        dscEngine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    // Helper functions
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        // aqui vamos retornar o endereço do colateral com base no collateralSeed, por exemplo, se for 0, retornamos o endereço do WETH, se for 1, retornamos o endereço do WBTC
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }

}