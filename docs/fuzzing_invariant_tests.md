# Testes Fuzzing com Invariantes no Foundry

## Introdução
Testes fuzzing com invariantes são uma técnica poderosa para verificar propriedades fundamentais de um contrato inteligente. Esses testes geram chamadas aleatórias para funções do contrato e verificam se certas condições (invariantes) permanecem verdadeiras em todos os estados possíveis do contrato.

No contexto do Foundry, os testes fuzzing com invariantes são configurados para explorar diferentes estados do contrato e garantir que ele se comporte conforme o esperado, mesmo em cenários extremos ou inesperados.

---

## Implementação de um Teste Fuzzing com Invariantes

### Estrutura do Teste
Um teste fuzzing com invariantes geralmente segue esta estrutura:

1. **Setup do Ambiente**:
   - Implantação dos contratos necessários.
   - Configuração de dependências e variáveis globais.
   - Definição do contrato-alvo para os testes fuzzing.

2. **Definição da Invariante**:
   - Uma função pública que verifica uma propriedade fundamental do contrato.
   - Essa função é chamada repetidamente pelo framework para garantir que a propriedade seja mantida em todos os estados possíveis.

### Exemplo de Teste
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract InvariantsTest is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    HelperConfig helperConfig;
    address weth;
    address wbtc;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (, , weth, wbtc, ) = helperConfig.activeNetworkConfig();
        targetContract(address(dscEngine));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dscEngine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dscEngine));

        uint256 wethValue = dscEngine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dscEngine.getUsdValue(wbtc, totalWbtcDeposited);

        console.log("Valor total de WETH depositado (em USD):", wethValue);
        console.log("Valor total de WBTC depositado (em USD):", wbtcValue);
        console.log("Total Supply do DSC:", totalSupply);

        assert(wethValue + wbtcValue >= totalSupply);
    }
}
```

---

## Configurações do `foundry.toml`
O arquivo `foundry.toml` é usado para configurar o comportamento dos testes fuzzing. Aqui estão as configurações relevantes:

```toml
[invariant]
runs = 1000 # Número de execuções para cada invariante
depth = 128 # Profundidade máxima (número de chamadas em uma única execução)
fail_on_revert = false # Se o teste deve falhar quando uma transação reverter
```

### Explicação das Configurações
- **`runs`**: Define quantas vezes cada invariante será testada. Um número maior aumenta a cobertura, mas também o tempo de execução.
- **`depth`**: Limita o número de chamadas feitas em uma única execução. Isso ajuda a evitar loops infinitos ou execuções muito longas.
- **`fail_on_revert`**: Quando `false`, o teste não falha automaticamente se uma transação reverter. Isso é útil para cenários onde reverts são esperados e fazem parte do comportamento normal do contrato. No entanto, isso também significa que entradas aleatórias podem gerar fluxos inesperados ou incorretos, já que o teste continuará mesmo após reverts, o que pode dificultar a identificação de problemas reais.

---

## Utilidade do Handler
O `Handler` é um contrato auxiliar usado para restringir ou controlar como as funções do contrato-alvo são chamadas durante os testes fuzzing. Ele permite:

1. **Definir Restrições**:
   - Por exemplo, impedir que certas funções sejam chamadas com parâmetros inválidos.

2. **Simular Cenários Específicos**:
   - Como múltiplos usuários interagindo com o contrato.

3. **Registrar Estados**:
   - O `Handler` pode armazenar informações sobre o estado do contrato para ajudar na depuração.

### Exemplo de Handler
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract Handler {
    DSCEngine dscEngine;

    constructor(DSCEngine _dscEngine) {
        dscEngine = _dscEngine;
    }

    function callDepositCollateral(address token, uint256 amount) external {
        dscEngine.depositCollateral(token, amount);
    }
}
```

---

## Conclusão
Testes fuzzing com invariantes são uma ferramenta essencial para garantir a segurança e a robustez de contratos inteligentes. Com as configurações adequadas no `foundry.toml` e o uso de um `Handler`, é possível explorar uma ampla gama de cenários e verificar se o contrato se comporta corretamente em todos eles.