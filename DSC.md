# Funcionamento do Protocolo DSC

# 1. Depositar garantia e cunhar DSC

O usuário deposita um colateral cujo valor é maior que a quantidade de DSC que deseja emitir.
Esse depósito gera os DSCTokens.

# 2. Resgatar garantia devolvendo DSC

O usuário pode devolver seus DSC ao protocolo para recuperar o colateral correspondente.
Esse processo envolve a queima do DSC devolvido.

# 3. Queimar DSC voluntariamente

Se o valor da garantia cair rapidamente, o usuário pode queimar DSC para ajustar sua razão de colateralização e evitar liquidação.

# 4. Liquidar contas subcolateralizadas

O protocolo exige sobrecolateralização.
Quando o colateral de uma conta cai abaixo do mínimo necessário, ela se torna liquidável.

Durante a liquidação:

Outro usuário paga/queima os DSC da posição insolvente.

O liquidante recebe a garantia com desconto como recompensa.

Esse incentivo econômico mantém o protocolo seguro.

# 5. healthFactor

O healthFactor representa a proporção entre o colateral depositado e os DSC emitidos pelo usuário.

Se o colateral cai enquanto o DSC permanece constante → o healthFactor diminui.

Se o healthFactor ficar abaixo do limite mínimo → a conta pode ser liquidada.

# Exemplo:

Limite de colateralização: 150%

Colateral: US$ 75 em ETH

DSC possível: US$ 50

Se o ETH cair para US$ 74, o healthFactor quebra o limite e a conta se torna liquidável.

# Resumo Geral

Usuários depositam colateral maior que o valor dos DSC que cunham.

Se a posição ficar under-collateralized, ela pode ser liquidada.

O liquidante queima DSC e recebe o colateral, lucrando com a diferença.

Esse mecanismo mantém o sistema estável e incentiva a correção rápida de posições arriscadas.