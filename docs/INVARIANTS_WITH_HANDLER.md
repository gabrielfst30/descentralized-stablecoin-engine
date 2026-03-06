## Guia: Criando Invariants com um `Handler` (exemplo deste projeto)

Este documento descreve como estruturar invariants usando um `Handler` para reduzir o espaço de ações durante fuzzing/invariant testing. O exemplo referencia este repositório: use os arquivos [test/fuzz/Handler.t.sol](test/fuzz/Handler.t.sol) e [test/fuzz/Invariants.t.sol](test/fuzz/Invariants.t.sol) como ponto de partida.

**Pré-requisitos**
- Conhecimentos básicos de Solidity e Foundry (`forge`).
- Projeto compilável com Foundry (veja [foundry.toml](foundry.toml)).

**Por que usar um `Handler`?**
- O `Handler` encapsula e restringe as chamadas que o fuzz pode executar, fornecendo controles (por exemplo `bound`) e ações compostas (mint + approve + deposit) — isso evita que o fuzz gere combos inválidos que saturariam a execução.
- Em invariants, o target é normalmente o `Handler`, não diretamente o protocolo. Assim o fuzzer explora sequências de chamadas válidas.

Passos práticos (usando este projeto)

1. Identifique propriedades invariantes que sempre devem ser verdadeiras.
   - Ex.: `totalCollateralValue >= dsc.totalSupply()` (implementada em [test/fuzz/Invariants.t.sol](test/fuzz/Invariants.t.sol)).

2. Escreva um `Handler` com um conjunto limitado de ações.
   - Exemplos de ações no `Handler`: `mintDsc(amount)`, `depositCollateral(tokenSeed, amount)`, `redeemCollateral(tokenSeed, amount)`.
   - Use tipos de contrato (ex.: `ERC20Mock`) para poder chamar helpers de teste (`mint`) sem casts repetidos — veja [test/fuzz/Handler.t.sol](test/fuzz/Handler.t.sol).

3. Reduza o espaço de entrada com `bound(x, min, max)`
   - `bound` normaliza um valor `x` para o intervalo inclusivo `[min,max]`. Evite reverts: garanta `min <= max` ou cheque `max` previamente.
   - Ex.: no `Handler` use `amount = bound(amount, 1, MAX_DEPOSIT_SIZE)` para impedir valores inválidos ou overflow.

4. Exponha o `Handler` como `targetContract` nas invariants
   - Em `setUp()` de `Invariants.t.sol`: `handler = new Handler(dscEngine, dsc); targetContract(address(handler));`

5. Configure `foundry.toml` adequadamente
   - Para fuzz/invariant runs, `fail_on_revert = false` (permite continuar após reverts esperados). Em debugging/CI prefira `true`.

6. Execute e observe resultados
   - Comando típico:
   ```bash
   forge test --match-path test/fuzz -vv
   ```

Metodologia para mentalizar um teste de invariante (como pensar sobre o problema)

- Defina a propriedade invariável com clareza (o que nunca pode quebrar?).
- Liste todas as ações que participantes/atores podem executar (criar um `Handler` mapeando essas ações).
- Para cada ação, pense nos pré-condições e efeitos (estado antes/depois). Use `bound` e checks no `Handler` para garantir pre-condições.
- Considere ataques e sequências adversariais (ex.: mint → deposit → flash-type sequences). Pergunte: essa sequência pode violar a propriedade?
- Reduza o espaço de ações no `Handler` para focar apenas nos caminhos relevantes; menos ações = execução mais eficiente do fuzz.
- Itere: se uma invariante falhar, analise o contra-exemplo, ajuste o `Handler` (se necessário) ou corrija o contrato.

Boas práticas e dicas rápidas
- Use `ERC20Mock` no `Handler` quando precisar de `mint` (conveniência). Caso só precise de `approve/transfer`, prefira `IERC20` para abstração.
- Evite chamar `bound` com `min` > `max`; faça checagens antecipadas quando `max` depende do estado (por exemplo saldo do usuário).
- Logging: `bound` chama `console2` — pode gerar ruído; use `-vv` para ver mais informações quando depurando.
- Em invariants, escreva invariantes “evergreen” (não dependem de execução) e “safety” (garantem propriedades econômicas). Ambos têm valor.

Exemplo rápido de verificação mental
- Propriedade: colateral em USD >= totalSupply.
- Ações do `Handler`: depositCollateral, redeemCollateral, mintDsc, burnDsc (se aplicável).
- Perguntas: existe sequências que mintam dsc sem colateral? O `Handler` consegue observar e executar essas sequências? Se sim, então o protocolo tem bug.

Conclusão
- Use o `Handler` para controlar e filtrar o espaço de entradas do fuzzer. Mentalize invariantes como propriedades matemáticas simples, depois enumere ações e efeitos. Itere enquanto refina invariants e ações do `Handler`.

Referências nos arquivos do projeto
- Handler: [test/fuzz/Handler.t.sol](test/fuzz/Handler.t.sol)
- Invariants: [test/fuzz/Invariants.t.sol](test/fuzz/Invariants.t.sol)
- Config: [foundry.toml](foundry.toml)

--
Guia gerado a partir da estrutura atual do projeto.
