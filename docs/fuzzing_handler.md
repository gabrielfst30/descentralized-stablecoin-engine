# Handler de Fuzzing — Como funciona o `collateralSeed`, mint e approve

## Visão geral

O `Handler.t.sol` é o contrato intermediário usado nos testes de invariante com fuzzing do Foundry. Ele **restringe** as chamadas do fuzzer para que apenas ações válidas sejam executadas contra o protocolo.

---

## O problema sem o Handler

O fuzzer gera valores completamente aleatórios para os parâmetros das funções. Se `depositCollateral` recebesse um `address` diretamente, o fuzzer passaria endereços aleatórios como:

```
0x1a2b3c...  → não é colateral suportado → revert
0xdeadbeef... → não é colateral suportado → revert
```

O teste ficaria atolado em reverts inúteis, nunca testando o comportamento real do protocolo.

---

## A solução: `collateralSeed` + `_getCollateralFromSeed`

Em vez de receber um `address`, `depositCollateral` recebe um `uint256 collateralSeed`. O fuzzer gera qualquer número aleatório, e a função `_getCollateralFromSeed` transforma esse número em um dos dois colaterais válidos do protocolo.

```solidity
function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
    if (collateralSeed % 2 == 0) {
        return weth;
    } else {
        return wbtc;
    }
}
```

### Como funciona o mapeamento

| `collateralSeed` (gerado pelo fuzzer) | `% 2` | Colateral retornado |
|---------------------------------------|-------|---------------------|
| 0, 2, 4, 847392, ...                  | 0     | `weth`              |
| 1, 3, 7, 999999, ...                  | 1     | `wbtc`              |

Qualquer `uint256`, por maior que seja, sempre cai em um dos dois casos — **garantindo que o endereço passado para o protocolo seja sempre válido**.

---

## Fluxo completo de uma chamada fuzzada

```
Fuzzer gera: collateralSeed = 847392, amountCollateral = 99999999999

1. depositCollateral(847392, 99999999999) é chamado

2. _getCollateralFromSeed(847392)
   → 847392 % 2 == 0
   → retorna weth

3. amountCollateral = bound(99999999999, 1, type(uint96).max)
   → limita o valor para evitar overflow

4. vm.startPrank(msg.sender)
   → todas as chamadas seguintes são executadas como msg.sender

5. collateral.mint(msg.sender, amountCollateral)
   → o usuário recebe os tokens para poder depositar

6. collateral.approve(address(dscEngine), amountCollateral)
   → o dscEngine recebe permissão para chamar transferFrom

7. dscEngine.depositCollateral(address(weth), amountCollateral)
   → execução válida ✓

8. vm.stopPrank()
```

---

## Por que `mint` + `approve` + `vm.prank`?

Sem essas três etapas, **100% das chamadas revertiam** porque:

| Problema                          | Causa                                                         | Solução                          |
|-----------------------------------|---------------------------------------------------------------|----------------------------------|
| `ERC20: transfer amount exceeds balance` | O `msg.sender` não tinha tokens              | `collateral.mint(msg.sender, ...)` |
| `ERC20: insufficient allowance`   | O `dscEngine` não tinha permissão para gastar os tokens       | `collateral.approve(dscEngine, ...)` |
| Mint/approve executados como `Handler` | O `Handler` mintava para si mesmo, não para `msg.sender` | `vm.startPrank(msg.sender)` |

O `vm.startPrank(msg.sender)` garante que o mint, approve e deposit acontecem todos **sob a identidade do mesmo endereço** (o gerado pelo fuzzer), tornando o fluxo auto-consistente.

---

## Por que `bound`?

O `bound(amountCollateral, 1, MAX_DEPOSIT_SIZE)` restringe o valor do depósito entre `1` e `type(uint96).max`. Isso evita:

- Depósito de `0` → revert por valor inválido
- Valores absurdamente grandes → overflow em operações internas

```solidity
uint256 MAX_DEPOSIT_SIZE = type(uint96).max; // 79228162514264337593543950335
```

---

## Resumo

| Técnica                  | Objetivo                                                      |
|--------------------------|---------------------------------------------------------------|
| `uint256 collateralSeed` | Receber input aleatório do fuzzer                             |
| `% 2` no seed            | Mapear número aleatório para colateral válido                 |
| `bound()`                | Restringir o range numérico para valores plausíveis           |
| `collateral.mint()`      | Garantir que o usuário tenha saldo antes de depositar         |
| `collateral.approve()`   | Dar permissão ao `dscEngine` para chamar `transferFrom`       |
| `vm.startPrank()`        | Executar mint, approve e deposit sob a mesma identidade       |

Essas técnicas juntas garantem que o fuzzer **sempre execute chamadas válidas**, maximizando a cobertura de estados relevantes do protocolo em vez de desperdiçar execuções em reverts triviais.
