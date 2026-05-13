// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @title OracleLib
/// @notice Biblioteca para verificar se o oráculo da Chainlink está obsoleto (stale).
/// @dev Se o preço estiver obsoleto, a função será revertida e inutilizará o DSCEngine.
///      Queremos que o DSCEngine congele se os preços ficarem obsoletos.
///      Se a rede Chainlink explodir e você tiver muito dinheiro trancado no contrato...deu ruim.
library OracleLib {
    error OracleLib__StalePrice();

    uint256 private constant TIMEOUT = 3 hours;

    function staleCheckLatestRoundData(
        AggregatorV3Interface priceFeed
    ) public view returns (uint80, int256, uint256, uint80) {
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();

        // A subtração calcula quantos segundos se passaram desde a última atualização do preço.
        // Se esse valor for maior que TIMEOUT (3 horas), significa que o oráculo está obsoleto (stale) — ou seja, o preço não foi atualizado há mais de 3 horas — e a transação é revertida.
        uint256 secondsSince = block.timestamp - updatedAt;
        // Se o preço estiver obsoleto, reverter a transação
        if(secondsSince > TIMEOUT) revert OracleLib__StalePrice();

        // Se o preço não estiver obsoleto, retornar os dados do round normalmente
        return (roundId, answer, startedAt, answeredInRound);
    }
}
