# Guia Prático: interpretar e testar `revert` em testes/fuzz

Este documento resume uma metodologia prática para decidir quando um `revert` é esperado/aceitável ou quando indica um problema, e como testar/diagnosticar cada caso. Baseado na ideia: "se a intenção do teste é que falhe e ele falhar, passou; se a intenção é que não falhe e não falhar, passou".

## 1 — Regra simples
- Teste positivo (happy path): você espera que a chamada NÃO reverta. Se não reverter e os efeitos estiverem corretos → OK.
- Teste negativo (negative assertion): você espera que a chamada reverta (ex.: pré-condição violada). Use `vm.expectRevert()` para afirmar o motivo → OK.

## 2 — Classificando reverts: bom vs ruim
- Bom (esperado): revert causado por checagens de pré-condição (saldo insuficiente, allowance, checagem de colateralização, `require` com mensagem esperada).
- Ruim (não esperado): `panic`, underflow/overflow, `assert` não esperada, revert sem razão clara — provavelmente bug.

## 3 — Interpretando a tabela de chamadas
Tabela exemplo:

| Contract | Selector | Calls | Reverts | Interpretação rápida |
|---|---:|---:|---:|---|
| Handler  | depositCollateral | 5438 | 0    | OK — handler prepara pré-condições (mint/approve).
| Handler  | mintDsc           | 5488 | 0    | OK — pré-checagens aplicadas antes do mint.
| Handler  | redeemCollateral  | 5458 | 5215 | Alto número de reverts: investigar — provavelmente inputs inválidos do fuzzer ou falta de pré-checagens no `Handler`.

## 4 — Passos práticos para diagnosticar reverts excessivos
1. Verifique a especificação da função que reverte (quais `require`s existem?).
2. Rode com verbosidade para ver mensagens de revert:
```bash
forge test --match-path test/fuzz -vv
```
3. Para depuração rápida, habilite `fail_on_revert = true` temporariamente em `foundry.toml` para parar no primeiro revert e inspecionar a razão.
4. Adicione `vm.expectRevert(<reason>)` em testes unitários que checam comportamento negativo explícito.
5. No `Handler`, pré-cheque estado antes de chamar a função externa (ex.: saldo, allowance, razão de colateralização). Isso transforma reverts esperados em `return` e reduz ruído no fuzz.

## 5 — Exemplos de mitigação no `Handler`
- Pré-checar saldo antes de `redeemCollateral`:
```solidity
uint256 maxCollateral = dscEngine.getCollateralBalanceOfUser(token, msg.sender);
if (maxCollateral == 0) return; // evita revert por saldo insuficiente
amount = bound(amount, 1, maxCollateral);
dscEngine.redeemCollateral(token, amount);
```
- Para `mintDsc`, calcule `allowed = collateralValueInUsd / 2; if (allowed <= totalDscMinted) return;` e então subtraia com segurança (evita underflow).

## 6 — Como decidir a ação correta
- Se o revert for esperado pelo cenário de teste: registre com `vm.expectRevert` ou ignore-no-Handler (retornar antes) e documente.
- Se for inesperado: reproduza com `fail_on_revert = true`, capture a razão e abra uma investigação (pode ser bug no contrato ou erro de lógica no `Handler`).

## 7 — Ferramentas e técnicas úteis
- `vm.expectRevert(<reason>)` — afirmar reverts em testes unitários.
- `try/catch` — capturar reverts para logar sem falhar a run.
- `forge test -vv` — mais detalhes e motivos de revert.
- Ajuste `fail_on_revert` em `foundry.toml`: `false` durante fuzz/invariant, `true` durante debugging/CI.

## 8 — Checklist rápido antes de rodar invariants
- O `Handler` faz pré-checagens básicas (saldos, allowance, bounds)?
- `bound` é usado corretamente com `min <= max`? (use checagens caso `max` dependa do estado)
- As invariantes são escritas para propriedades essenciais (ex.: colateral >= totalSupply)?

## Conclusão
Reverts são mecanismos válidos para proteger invariantes e garantir segurança. O objetivo do desenvolvedor/testador é garantir que reverts observados sejam os esperados para cada caso de teste, e reduzir reverts “ruidosos” durante fuzzing aplicando pré-checagens no `Handler` e usando ferramentas de diagnóstico quando necessário.

---
Guia gerado a partir da configuração e arquivos de teste deste projeto.
