# DSCEngine - Guia de Fluxos

## 1. Depositar Colateral e Mintar DSC

### Fluxo: `depositCollateralAndMintDsc(token, amountCollateral, amountDscToMint)`

```
Usuário
  │
  ├─► 1. depositCollateral(token, amountCollateral)
  │     │
  │     ├─► 2. Valida: amount > 0 && token permitido
  │     ├─► 3. Atualiza: s_collateralDeposited[user][token] += amount
  │     ├─► 4. Emite: CollateralDeposited(user, token, amount)
  │     └─► 5. Transfere: IERC20(token).transferFrom(user → DSCEngine)
  │
  └─► 6. mintDsc(amountDscToMint)
        │
        ├─► 7. Atualiza: s_dscMinted[user] += amountDscToMint
        ├─► 8. Valida: _revertIfHealthFactorIsBroken(user)
        │     │
        │     ├─► Calcula HF = (colateral_USD × 50 / 100) / dívida_DSC
        │     └─► Se HF < 1.0 → ❌ REVERT
        │
        └─► 9. Mina: i_dsc.mint(user, amountDscToMint)
              └─► ✅ DSC transferido para o usuário
```

**Regra Health Factor:**
```
HF = (Valor_Colateral_USD × LIQUIDATION_THRESHOLD) / (LIQUIDATION_PRECISION × Dívida_DSC)
HF = (Colateral × 50) / (100 × Dívida)

HF >= 1.0 → Posição segura (200% overcollateralized)
HF < 1.0  → Posição liquidável
```

**Exemplo:**
- Deposita: $1000 ETH
- Pode mintar: até $500 DSC (HF = 1.0)
- Recomendado: $400 DSC (HF = 1.25, margem de segurança 25%)

---

## 2. Queimar DSC e Resgatar Colateral

### Fluxo: `redeemCollateralForDsc(token, amountCollateral, amountDscToBurn)`

```
Usuário
  │
  ├─► 1. burnDsc(amountDscToBurn)
  │     │
  │     └─► 2. _burnDsc(amount, user, user)
  │           │
  │           ├─► 3. Atualiza: s_dscMinted[user] -= amount
  │           ├─► 4. Transfere: i_dsc.transferFrom(user → DSCEngine)
  │           ├─► 5. Queima: i_dsc.burn(amount)
  │           └─► 6. Valida HF (redundante, burn melhora HF)
  │
  └─► 7. redeemCollateral(token, amountCollateral)
        │
        └─► 8. _redeemCollateral(token, amount, user, user)
              │
              ├─► 9. Atualiza: s_collateralDeposited[user][token] -= amount
              ├─► 10. Emite: CollateralRedeemed(user, user, token, amount)
              ├─► 11. Transfere: IERC20(token).transfer(user, amount)
              └─► 12. Valida: _revertIfHealthFactorIsBroken(user)
                    └─► Se HF < 1.0 → ❌ REVERT
```

**Ordem importante:** Primeiro queima DSC (reduz dívida), depois resgata colateral.

---

## 3. Liquidação

### Fluxo: `liquidate(collateralAddress, user, debtToCover)`

```
Liquidador
  │
  ├─► 1. Valida: _healthFactor(user) < MIN_HEALTH_FACTOR (1.0)
  │     └─► Se HF >= 1.0 → ❌ REVERT DSCEngine__HealthFactorOk
  │
  ├─► 2. Calcula colateral a confiscar:
  │     │
  │     ├─► tokenAmount = getTokenAmountFromUsd(collateralAddress, debtToCover)
  │     │     └─► Exemplo: $100 DSC → 0.05 ETH (se ETH = $2000)
  │     │
  │     ├─► bonusCollateral = tokenAmount × 10 / 100
  │     │     └─► Exemplo: 0.05 ETH × 10% = 0.005 ETH
  │     │
  │     └─► totalCollateral = tokenAmount + bonusCollateral
  │           └─► Exemplo: 0.05 + 0.005 = 0.055 ETH
  │
  ├─► 3. Confisca colateral:
  │     │
  │     └─► _redeemCollateral(collateralAddress, totalCollateral, user, liquidador)
  │           │
  │           ├─► s_collateralDeposited[user][token] -= totalCollateral
  │           ├─► Emite: CollateralRedeemed(user, liquidador, token, totalCollateral)
  │           └─► IERC20(token).transfer(liquidador, totalCollateral)
  │
  ├─► 4. Queima dívida do usuário:
  │     │
  │     └─► _burnDsc(debtToCover, user, liquidador)
  │           │
  │           ├─► s_dscMinted[user] -= debtToCover
  │           ├─► i_dsc.transferFrom(liquidador → DSCEngine, debtToCover)
  │           └─► i_dsc.burn(debtToCover)
  │
  ├─► 5. Valida: HF do usuário melhorou
  │     └─► Se endingHF <= startingHF → ❌ REVERT DSCEngine__HealthFactorNotImproved
  │
  └─► 6. Valida: HF do liquidador >= 1.0
        └─► _revertIfHealthFactorIsBroken(liquidador)
              └─► ✅ Liquidação concluída
```

**Exemplo numérico:**
```
Estado inicial:
- Usuário: $140 ETH colateral, $100 DSC dívida
- Preço ETH cai → HF < 1.0 → liquidável

Liquidação:
- Liquidador cobre: $100 DSC
- Liquidador recebe: $110 ETH ($100 dívida + $10 bônus)
- Lucro: $10 (10% da dívida coberta)

Estado final:
- Usuário: $30 ETH colateral restante, $0 DSC dívida → HF melhorou
- Liquidador: +$110 ETH, -$100 DSC
```

---

## 4. Funções Públicas vs Privadas

### Estrutura Wrapper

```
FUNÇÕES PÚBLICAS (validam msg.sender)
│
├─► redeemCollateral(token, amount)
│     ├─► _redeemCollateral(token, amount, msg.sender, msg.sender)
│     └─► _revertIfHealthFactorIsBroken(msg.sender)
│
└─► burnDsc(amount)
      ├─► _burnDsc(amount, msg.sender, msg.sender)
      └─► _revertIfHealthFactorIsBroken(msg.sender)


FUNÇÕES PRIVADAS (flexíveis, usadas por liquidate)
│
├─► _redeemCollateral(token, amount, from, to)
│     └─► Transfere colateral: from → to
│
└─► _burnDsc(amount, onBehalfOf, dscFrom)
      └─► Queima dívida de: onBehalfOf, DSC vem de: dscFrom


liquidate() usa privadas diretamente:
│
├─► _redeemCollateral(token, amount, user, liquidador)
│     └─► Colateral do user vai pro liquidador
│
└─► _burnDsc(amount, user, liquidador)
      └─► Dívida do user, DSC vem do liquidador
```

**Por que separar?**
- **Públicas:** Operações do próprio usuário → valida HF do `msg.sender`
- **Privadas:** Usadas em liquidação → mexem em múltiplas contas (vítima + liquidador)

---

## 5. Cálculo do Health Factor

### Função: `_healthFactor(user)`

```
1. _getAccountInformation(user)
   │
   ├─► totalDscMinted = s_dscMinted[user]
   └─► collateralValueInUsd = getAccountCollateralValue(user)
         │
         └─► Loop por todos os tokens:
               collateralValueInUsd += getUsdValue(token, amount)
                 └─► preço Chainlink × amount

2. collateralAdjustedForThreshold = (collateralValueInUsd × 50) / 100

3. healthFactor = (collateralAdjustedForThreshold × 1e18) / totalDscMinted

4. Retorna: healthFactor (18 decimais)
```

### Função: `_revertIfHealthFactorIsBroken(user)`

```
1. healthFactor = _healthFactor(user)

2. Se healthFactor < MIN_HEALTH_FACTOR (1e18):
   └─► ❌ REVERT DSCEngine__BreaksHealthFactor(healthFactor)

3. Caso contrário:
   └─► ✅ Prossegue
```

**Interpretação:**
```
HF = 2.0 (2e18) → 400% collateralization → Muito seguro
HF = 1.5 (1.5e18) → 300% collateralization → Seguro
HF = 1.0 (1e18) → 200% collateralization → Limite mínimo
HF = 0.8 (0.8e18) → 160% collateralization → Liquidável
```

---

## 6. Arquitetura e Componentes

### Estado do Protocolo

```
DSCEngine mantém:

s_priceFeeds: mapping(token → chainlinkPriceFeed)
├─► WETH → ETH/USD feed
└─► WBTC → BTC/USD feed

s_collateralDeposited: mapping(user → mapping(token → amount))
├─► Alice → WETH → 2 ETH
└─► Bob → WBTC → 0.1 BTC

s_dscMinted: mapping(user → amountDSC)
├─► Alice → 1000 DSC
└─► Bob → 500 DSC

s_collateralTokens: array[WETH, WBTC]
└─► Lista de tokens aceitos como colateral

i_dsc: DecentralizedStableCoin (immutable)
└─► Contrato ERC20 do DSC
```

### Interações Externas

```
Usuário
  │
  ├─► Deposita colateral (WETH/WBTC)
  │     └─► IERC20.transferFrom(user → DSCEngine)
  │
  ├─► Mina DSC
  │     └─► DSCEngine → i_dsc.mint(user, amount)
  │
  ├─► Consulta preços
  │     └─► DSCEngine → Chainlink.latestRoundData()
  │           └─► Retorna: preço em USD (8 decimais)
  │
  └─► Resgata colateral
        └─► IERC20.transfer(DSCEngine → user)
```

---

## 7. Regras de Validação

| Função | Health Factor Check | Momento | Objetivo |
|--------|---------------------|---------|----------|
| `depositCollateral` | ❌ Não | N/A | Depositar sempre melhora HF |
| `mintDsc` | ✅ Sim | **Antes** do mint | Prevenir mint excessivo |
| `redeemCollateral` | ✅ Sim | **Depois** do resgate | Garantir HF após retirada |
| `burnDsc` | ✅ Sim (redundante) | **Depois** do burn | Queimar sempre melhora HF |
| `liquidate` | ✅ Sim (2×) | **Antes** + **Depois** | Vítima liquidável + liquidador saudável |

### Constantes Importantes

```
LIQUIDATION_THRESHOLD = 50       → 50% do colateral pode ser DSC
LIQUIDATION_PRECISION = 100      → Precisão para threshold
MIN_HEALTH_FACTOR = 1e18         → 1.0 em 18 decimais
LIQUIDATION_BONUS = 10           → 10% de bônus para liquidadores
PRECISION = 1e18                 → 18 decimais padrão
ADDITIONNAL_FEED_PRECISION = 1e10 → Ajuste Chainlink 8d → 18d
```

### Fórmulas

```
Health Factor:
HF = (Colateral_USD × 50 / 100 × 1e18) / Dívida_DSC

Colateral USD:
Valor = Preço_Chainlink × 1e10 × Amount / 1e18

Token de USD:
Amount = (USD_valor × 1e18) / (Preço_Chainlink × 1e10)

Bônus Liquidação:
Bônus = Token_Amount × 10 / 100
Total = Token_Amount + Bônus
```
