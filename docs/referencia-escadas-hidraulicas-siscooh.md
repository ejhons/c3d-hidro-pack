# Escoamento em Degraus (escadas hidráulicas)

Transcrição da seção 4.2 do *Manual Técnico do Programa SisCCoH 1.1*, com as equações em LaTeX.
A numeração das equações é a do manual. Onde a grafia impressa era ambígua, a forma adotada aparece
com a marca **[leitura]** e foi conferida contra as figuras e os exemplos numéricos do próprio manual
(ver a seção [Notas de leitura](#notas-de-leitura)). O código correspondente é `escada_hidraulica.py`.

## Notação

| Símbolo | Significado | Unidade |
|---|---|---|
| $Q$ | vazão | m³/s |
| $B$ | largura do canal | m |
| $q = Q/B$ | vazão específica | m²/s |
| $S$ (ou $h$) | altura do degrau | m |
| $l$ | comprimento (piso) do degrau | m |
| $\tan\theta = S/l$ | declividade da calha | — |
| $\theta$ | ângulo entre a horizontal e o plano que contém as quinas dos degraus | ° |
| $y_c = \sqrt[3]{q^2/g}$ | profundidade crítica | m |
| $H_d$ ou $H_{dam}$ | desnível total da escada | m |
| $N$ | número de degraus | — |
| $g$ | aceleração da gravidade, $9{,}81$ | m/s² |

---

## 4.2.1 Regime de escoamento em degraus

Há três regimes:

- **Nappe flow** (quedas sucessivas): formação de bolsões de ar em cada degrau.
- **Skimming flow** (escoamento deslizante sob turbilhões, segundo Ohtsu et al. 2004): formação de vórtices em cada degrau.
- **Transição:** alterna entre as características dos dois regimes anteriores (Matos e Quintela *apud* Simões 2008).

O SisCCoH dimensiona o escoamento em degraus por estudos empíricos e **desconsidera o material do canal**: a dissipação
é mais influenciada pelas características dos degraus do que pela rugosidade do revestimento. Para estruturas de maior
magnitude ou com velocidades altas, recomenda-se revestimento em concreto.

**Dados de entrada:** $Q$, $B$, $S$ e $l$.
**Calculados:** $S/l$, $\theta$, $y_c$, $q$ e as vazões limite de cada regime.

### Faixas de validade

| Faixa | $S/l$ | $\theta$ | Base |
|---|---|---|---|
| Declividades baixas | $0{,}05 \le S/l < 0{,}1$ | $2{,}86^\circ$ a $5{,}71^\circ$ | Chanson (2001): só nappe ou transição |
| Declividades altas | $0{,}1 \le S/l \le 1{,}43$ | $5{,}7^\circ$ a $55^\circ$ | Nappe: Yasuda et al. (2001); skimming: Ohtsu et al. (2004) |

A modelagem empírica de Yasuda et al. mostra que a relação $y_c/h$ depende de Reynolds, de $B/y_c$ e da declividade, mas
essas dependências podem ser desprezadas para $B/y_c \ge 5$ e $Re \ge 20\,000$.

### Limite do nappe para $0{,}05 \le S/l < 0{,}1$

$$
y_{c,\text{máx}} = \left(0{,}89 - 0{,}4\,\frac{S}{l}\right) S
\qquad 0{,}05 \le \frac{S}{l} < 0{,}1
\tag{4.17}
$$

Se $y_c > y_{c,\text{máx}}$ a vazão excede o limite do nappe e o regime é de transição.

### Limites para $5{,}7^\circ \le \theta \le 55^\circ$

**Limite inferior do nappe** (Yasuda et al., 2001): há nappe se $S/y_c$ for **maior ou igual** a

$$
\frac{S}{y_c} = 0{,}57\,(\tan\theta)^3 + 1{,}3
\qquad 5{,}7^\circ \le \theta \le 55^\circ
\tag{4.18}
$$

**Limite superior do skimming** (Ohtsu et al., 2004): há skimming se $S/y_c$ for **menor ou igual** a

$$
\left(\frac{S}{y_c}\right)_s = \frac{7}{6}\,(\tan\theta)^{1/6}
\qquad 5{,}7^\circ < \theta < 55^\circ
\tag{4.21}
$$

**[leitura]** O fator $7/6$ fica fora do expoente. É a forma que reproduz as faixas de vazão das Figuras 4.3 e 4.4 do manual.

Entre os dois limites o regime é de **transição**. A vazão mínima do skimming sai de $y_c$ obtido em (4.21),
e a vazão máxima do nappe, de (4.18) ou (4.17).

### Subtipos do nappe

**Ressalto hidráulico completo**, para $5{,}7^\circ \le \theta \le 10{,}2^\circ$:

$$
\frac{S}{y_c} \ge -12{,}5537\,(\tan\theta)^3 + 21{,}4360\,(\tan\theta)^2 + 15{,}7799\,\tan\theta - 0{,}4583
\tag{4.19}
$$

**Ressalto hidráulico parcial** (Chanson, 1994), para $11{,}31^\circ \le \theta \le 30{,}96^\circ$. Se a condição valer, um aumento
da declividade ou da vazão não leva ao ressalto completo:

$$
\frac{S}{y_c} \ge \left\{\left[0{,}0916\,(\tan\theta)^{-1{,}276}\right]\right\}^{-1}
= \frac{(\tan\theta)^{1{,}276}}{0{,}0916}
\tag{4.20}
$$

**[leitura]** A grafia impressa deixa ambíguo onde fica o expoente. A forma acima segue a curva tracejada da Figura 4.4 do manual.

Fora das duas condições o nappe é **sem ressalto**.

### Subtipos do skimming

Nas inclinações de $19^\circ$ a $55^\circ$ a linha d'água é quase uniforme e paralela ao plano das quinas (**tipo A**).
Entre $5{,}7^\circ$ e $19^\circ$ o escoamento varia entre o tipo A e, quando $S/y_c$ cresce, o **tipo B**. O limite entre os tipos é

$$
\left(\frac{S}{y_c}\right)_B = 13\,(\tan\theta)^2 - 2{,}73\,\tan\theta + 0{,}373
\qquad 5{,}7^\circ < \theta < 19^\circ
\tag{4.22}
$$

Tipo B se $S/y_c > (S/y_c)_B$; caso contrário, tipo A.

### Notificações do módulo

| Mensagem | Significado |
|---|---|
| "Entrada incompleta de dados!" | campo em branco |
| "Dados incompatíveis para a resolução do problema!" | valor nulo |
| "Faixas de Vazão não Calculada!" | solução negativa para as vazões limite; mudar a geometria |
| "Os cálculos são válidos para o intervalo $0{,}1 \le S/y_c < (S/y_c)_s$" | condição de contorno do skimming |
| "S/yc maior que 10. Tente outros valores!" | limite superior do nappe com ressalto completo |
| "O cálculo é válido para a faixa de inclinações com ângulos entre 2,86° e 5,71°" | limite do nappe com $S/l < 0{,}1$ |
| "S/yc menor que 1,14 ou S/yc maior que 7. Tente outros valores!" | limite do nappe para $S/l < 0{,}1$ (Chanson, 2001) |
| "Tente outros Valores!" | dados fora do condicionamento empírico |

**Exemplo 4.1.** $Q = 10$ m³/s, $B = 2{,}5$ m, $S = 0{,}5$ m, $l = 1{,}0$ m.
$q = 4$ m²/s, $y_c = 1{,}177$ m, $S/y_c = 0{,}425$, $\tan\theta = 0{,}5$.
O limite (4.21) vale $1{,}039 > 0{,}425$, logo o regime é **skimming**.

| Regime | $Q$ mínima (m³/s) | $Q$ máxima (m³/s) |
|---|---|---|
| Nappe flow | 0 | 1,724 |
| Transição | 1,724 | 2,613 |
| Skimming flow | 2,613 | — |

---

## 4.2.2 Regime Nappe flow

O módulo calcula: ângulo da estrutura, vazão específica, profundidade crítica, número de queda, altura da parede,
energias máxima e residual, eficiência, profundidade final, velocidade e número de Froude no final.

### Geometria da queda

Número de queda:

$$
D_N = \frac{(Q/B)^2}{9{,}81\,S^3} = \frac{q^2}{g\,S^3}
\tag{4.23}
$$

Comprimento da queda e profundidades conjugadas (Rand):

$$
\frac{L_d}{S} = 4{,}3\,D_N^{0{,}27}
\tag{4.24}
$$

$$
\frac{y_1}{S} = 0{,}54\,D_N^{0{,}425}
\tag{4.25}
$$

$$
\frac{y_2}{S} = 1{,}66\,D_N^{0{,}27}
\tag{4.26}
$$

O manual imprime (4.24) como $L_d = 4{,}3\,D_N^{0{,}27}$, sem o divisor $S$. O exemplo 4.2 ($L_d = 1{,}399$ m) confirma $L_d/S$.

Profundidade anterior à queda (eq. 4.56, usada também aqui):

$$
y_a = S\,D_N^{0{,}22}
\tag{4.56}
$$

Comprimento do ressalto (eq. 3.13 do manual), com $y_2$ obtido pela conjugada de Bélanger a partir de $y_1$:

$$
L_j = 6{,}9\,(y_2 - y_1)
\qquad
y_2 = \frac{y_1}{2}\left(\sqrt{1 + 8F_1^2} - 1\right),
\quad
F_1 = \frac{q}{\sqrt{g\,y_1^3}}
$$

O exemplo 4.2 usa $y_2$ de Bélanger no módulo Nappe flow ($L_j = 2{,}808$ m). O exemplo 4.5 usa $y_2$ de Rand, na eq. (4.26), no módulo Quedas singulares.

### Altura mínima da parede (Simões, 2008)

Sem ressalto:

$$
H_{parede,mín,\,sem\ ressalto} = 2\,\tanh\!\left(0{,}02^{2{,}5} + 0{,}65\right) y_c \cdot 1{,}4
\tag{4.27}
$$

Com ressalto, ainda que parcial:

$$
H_{parede,mín,\,com\ ressalto} = 1{,}4\,y_2
\tag{4.28}
$$

**[leitura]** A grafia de (4.27) é duvidosa ("$0{,}02^{2{,}5{,}0}$"). Foi lida literalmente; o termo $0{,}02^{2{,}5}$ é desprezível e a expressão vale cerca de $1{,}6\,y_c$.

### Energias

$$
H_{máx} = H_d + 1{,}5\,y_c
\tag{4.29}
$$

**Ressalto completo:**

$$
H_{r,completo} = H_{máx}\;\frac{0{,}54\left(\dfrac{y_c}{S}\right)^{0{,}275} + 1{,}715\left(\dfrac{y_c}{S}\right)^{-0{,}55}}{1{,}5 + H_d/y_c}
\tag{4.30}
$$

**Ressalto parcial.** A expressão (4.31) dá a fração dissipada $\Delta H/H_{máx}$, e a energia residual é $H_r = H_{máx}\,(1-\Delta H/H_{máx})$:

$$
\frac{\Delta H}{H_{máx}} = 1 - \frac{(1-\alpha)\left[1 + 1{,}5\,\dfrac{y_c}{S}\right] + \displaystyle\sum_{i=1}^{N-1}(1-\alpha)^{i}}{N + 1{,}5\,\dfrac{y_c}{S}}
\tag{4.31}
$$

**Energia dissipada:**

$$
H_{dissip} = H_{máx} - H_r
\tag{4.32}
$$

Eficiência de dissipação: $\eta = H_{dissip}/H_{máx}$.

**[leitura]** O manual rotula (4.31) como $H_{r,parcial}$, mas o valor impresso corresponde à fração dissipada: com
$\alpha = 0{,}54$ ela dá $\eta = 84{,}22\,\%$, e o exemplo 4.2 informa $84{,}214\,\%$ com $H_r = 0{,}859$ m.
O parâmetro $\alpha$ **não é definido** no texto da seção; $0{,}54$ foi calibrado nesse exemplo.
Para nappe **sem ressalto** o manual não traz fórmula de energia residual.

**Estado final.** A profundidade final é a raiz supercrítica de $H_r = d + \dfrac{q^2}{2\,g\,d^2}$. Dela saem

$$
V = \frac{q}{d}, \qquad Fr = \frac{V}{\sqrt{g\,d}}
$$

### Exemplo 4.2

Dados: 10 degraus, $S = 0{,}5$ m, $l = 2{,}5$ m, $B = 4{,}0$ m, $H_d = 5{,}0$ m, $Q = 2{,}0$ m³/s.

| Grandeza | Valor |
|---|---|
| Regime | nappe, ressalto parcial |
| Faixas de $Q$ (m³/s) | nappe 0 a 2,973; transição 2,973 a 5,256; skimming a partir de 5,256 |
| $\theta$ | 11,31° |
| $q$ | 0,5 m²/s |
| $y_c$ | 0,294 m |
| $D_N$ | 0,204 |
| $L_d$ / $L_j$ | 1,399 m / 2,808 m |
| Parede mínima | 0,762 m |
| $H_{máx}$ | 5,441 m |
| $H_r$ | 0,859 m |
| $H_{dissip}$ | 4,582 m |
| Eficiência | 84,214 % |
| $d$ final | 0,132 m |
| $V$ final | 3,776 m/s |
| $Fr$ final | 3,313 |

---

## 4.2.3 Regime Skimming flow

Metodologia de Ohtsu et al. (2004), com experimentos de $5{,}7^\circ$ a $55^\circ$. Dados: $Q$, $B$, $S$, $l$ e $H_{dam}$.
Abas do módulo: Dados, Resultados, Visualização, Início do Escoamento, Risco de Cavitação e Relatório.

### Região quase uniforme

A altura relativa da escada necessária para formar escoamento aproximadamente uniforme é

$$
\frac{H_e}{y_c} = \frac{5{,}7 + 6{,}7\,e^{-6{,}5\,S/y_c}}{-1{,}21\!\times\!10^{-5}\,\theta^3 + 1{,}6\!\times\!10^{-3}\,\theta^2 - 7{,}13\!\times\!10^{-2}\,\theta + 1{,}3}
\tag{4.33}
$$

com $\theta$ em graus.

- Se $H_{dam}/y_c \ge H_e/y_c$: há região quase uniforme. Calculam-se atrito, profundidade representativa e concentração de ar.
- Caso contrário: só há região não uniforme, e calcula-se a energia residual relativa $E_r/y_c$.

### Coeficiente de atrito

$$
f = f_{máx} - A\left(0{,}5 - \frac{S}{y_c}\right)^{2}
\qquad 0{,}1 \le \frac{S}{y_c} \le 0{,}5
\tag{4.34}
$$

$$
f = f_{máx}
\qquad 0{,}5 \le \frac{S}{y_c} \le \left(\frac{S}{y_c}\right)_s
\tag{4.35}
$$

Para $5{,}7^\circ \le \theta \le 19^\circ$:

$$
A = -1{,}7\!\times\!10^{-3}\,\theta^2 + 6{,}4\!\times\!10^{-2}\,\theta - 1{,}5\!\times\!10^{-1}
\tag{4.36}
$$

$$
f_{máx} = -4{,}2\!\times\!10^{-4}\,\theta^2 + 1{,}6\!\times\!10^{-2}\,\theta + 3{,}2\!\times\!10^{-2}
\tag{4.37}
$$

Para $19^\circ \le \theta \le 55^\circ$:

$$
A = 0{,}452
\tag{4.38}
$$

$$
f_{máx} = 2{,}32\!\times\!10^{-5}\,\theta^2 - 2{,}75\!\times\!10^{-3}\,\theta + 2{,}31\!\times\!10^{-1}
\tag{4.39}
$$

**[leitura]** O manual imprime (4.34) sem o quadrado e (4.36) sem os sinais dos expoentes. Foram restabelecidos porque:
(i) com eles $A(19^\circ) = 0{,}452$, igual à (4.38), o que garante continuidade;
(ii) o exemplo 4.3 dá $f = 0{,}1718$ contra $0{,}172$ no manual.

### Profundidade representativa

Estimada pela igualdade entre a energia residual do skimming e a energia $E_1$ anterior ao ressalto (Yasuda e Ohtsu, 1999):

$$
d_w = \left(\frac{f}{8\,\sin\theta}\right)^{1/3} y_c
\tag{4.40}
$$

### Energia residual na região quase uniforme

Skimming tipo A:

$$
E_{ru,A} = y_c\left[\frac{d_w}{y_c}\cos\theta + 0{,}5\left(\frac{y_c}{d_w}\right)^{2}\right]
\tag{4.41}
$$

Skimming tipo B:

$$
E_{ru,B} = y_c\left[\frac{d_w}{y_c} + 0{,}5\left(\frac{y_c}{d_w}\right)^{2}\right]
\tag{4.42}
$$

### Região não uniforme ($H_{dam}/y_c < H_e/y_c$)

$$
E_r = y_c\left\{1{,}5 + \left(\frac{E_{ru}}{y_c} - 1{,}5\right)\left[1 - \left(1 - \frac{H_{dam}}{H_e}\right)^{m}\right]\right\}
\tag{4.43}
$$

$$
m = -\frac{\theta}{25} + 4
\tag{4.44}
$$

Com $\theta$ em graus e $E_{ru}$ de (4.41) ou (4.42). **[leitura]** Em (4.43) $E_{ru}$ entra dividido por $y_c$: a expressão dá $E_r = 1{,}5\,y_c$ em $H_{dam} = 0$ e $E_r = E_{ru}$ em $H_{dam} = H_e$.

### Concentração de ar e altura do muro

Concentração média de ar (Ohtsu et al., 2004):

$$
C_{med} = d - 0{,}3\,\exp\!\left[-5\left(\frac{S}{y_c}\right)^{2} - 4\,\frac{S}{y_c}\right]
\tag{4.45}
$$

com

$$
d = 0{,}3 \quad (5{,}7^\circ \le \theta < 19^\circ)
$$

$$
d = -2\!\times\!10^{-4}\,\theta^2 + 2{,}14\!\times\!10^{-2}\,\theta - 3{,}57\!\times\!10^{-2} \quad (19^\circ \le \theta \le 55^\circ)
\tag{4.46}
$$

**[leitura]** O manual imprime o expoente de (4.45) como "$-5\,S/y_c - 4\,S/y_c$". A forma com o quadrado no primeiro termo reproduz $C_{med} = 0{,}369$ do exemplo 4.3. Já a forma literal dá $0{,}385$.

Profundidade normal para $C = 0{,}9$ e altura do muro:

$$
Y_{0{,}9} = \frac{d_w}{1 - C_{med}}
\tag{4.47}
$$

$$
H_w = 1{,}4\,Y_{0{,}9}
\tag{4.48}
$$

### Início da aeração (Chanson, 2002, *apud* Gomes, 2006)

Rugosidade da calha e número de Froude rugoso (Keller e Rastogi, 1977):

$$
k = S\cos\theta
\tag{4.50}
$$

$$
F' = \frac{Q/B}{\sqrt{g\,k^3\,\sin\theta}}
\tag{4.49}
$$

Posição e profundidade de início da aeração, medidas ao longo do pseudo-fundo:

$$
L_a = 9{,}719\,(\sin\theta)^{0{,}0796}\,F'^{\,0{,}713}\,k
\tag{4.51}
$$

$$
Y_a = \frac{0{,}4034\,F'^{\,0{,}592}\,k}{(\sin\theta)^{0{,}04}}
\tag{4.52}
$$

A velocidade do escoamento aerado sai da continuidade: $V = q/Y_{0{,}9}$. A velocidade final é $V = q/d_w$.

### Risco de cavitação

Velocidade crítica de cavitação no início da aeração:

$$
V_{cra} = 16{,}29 + \frac{9{,}91}{1 + e^{\,0{,}4\left(\frac{1}{0{,}23}\right)}}
\tag{4.53}
$$

O programa avisa "$V_a < V_{cra}$: Sem risco de cavitação" ou "$V_a \ge V_{cra}$: Risco de cavitação. Tente outros valores."
(metodologia de Gomes, 2006). A grafia impressa de (4.53) parece ter perdido a variável $x/L_a$ do expoente (a aba Risco de Cavitação
traça uma curva em função de $x/L_a$). Por isso ela **não foi implementada** no código.

Condições de contorno da verificação:

- $0{,}35 \le x/L_a \le 1{,}2$
- $y_c/S \le 4{,}09$
- $48^\circ \le \theta \le 58^\circ$
- $S = 0{,}30;\ 0{,}60;\ 0{,}90;\ 1{,}20$ m
- vertedouro com muros verticais no sentido do escoamento (nem divergentes nem convergentes)
- sem elementos sobre a calha (pilares, manipuladores, turbulência)
- tensão relativa de vapor a 20 °C, ao nível do mar, $-10{,}09$ mH$_2$O

### Notificações adicionais

| Mensagem | Significado |
|---|---|
| "Os cálculos são válidos para o intervalo $0{,}1 \le S/y_c < (S/y_c)_s$" | $S/y_c$ fora do intervalo |
| "O cálculo é válido para a faixa de inclinações com ângulos entre 5,7° e 55°" | limite de Ohtsu et al. (2004) |
| "Não há raízes reais positivas" | ao calcular $d_w$ e a energia residual |
| "Os resultados obtidos estão fora do intervalo estabelecido para o cálculo. Tente outros dados." | fora do condicionamento empírico |

### Exemplo 4.3

Dados: $Q = 10$ m³/s, $B = 2{,}5$ m, $S = 0{,}5$ m, $l = 1$ m, $H_{dam} = 50$ m.

| Grandeza | Valor |
|---|---|
| $\theta$ | 26,565° |
| $q$ | 4 m²/s |
| $y_c$ | 1,177 m |
| $C_{med}$ | 0,369 |
| $f$ | 0,172 |
| Profundidade aerada $Y_{0{,}9}$ | 0,678 m |
| Velocidade aerada | 5,9 m/s |
| Profundidade final $d_w$ | 0,428 m |
| Velocidade final | 9,35 m/s |
| Energia residual | 4,838 m |
| Altura de referência da parede | 0,95 m |

---

## 4.2.4 Canais em trechos distintos

Canais retangulares com trechos em degraus ou com trechos de calha lisa intercalados, até **17 trechos**.
A energia residual e a profundidade final de cada trecho são dados de entrada e podem vir dos módulos anteriores.

$$
E_{tot} = H_{dam} + 1{,}5\,y_c
\tag{4.54}
$$

$$
E_{tot} = E_{res} + \Delta E
\tag{4.55}
$$

Para cada trecho, o código usa (4.54) com a energia de entrada do trecho, e (4.55) para a perda de carga:

$$
E_{tot,1} = H_1 + \left(y_0 + \frac{q^2}{2\,g\,y_0^2}\right),
\qquad
E_{tot,i} = H_i + \left(y_{f,i-1} + \frac{q^2}{2\,g\,y_{f,i-1}^2}\right),
\qquad
\Delta E_i = E_{tot,i} - E_{res,i}
$$

Para o canal inteiro:

$$
E_{tot} = \sum H_i + E(y_0), \qquad E_{res} = E_{tot} - \sum \Delta E_i
$$

e a profundidade final, a velocidade e o Froude saem de $E(y) = E_{res}$ (raiz supercrítica).

### Exemplo 4.4

Profundidade inicial $0{,}77$ m e $Q = 8$ m³/s, $B = 2$ m em todos os trechos.

| Trecho | $H$ (m) | $E_{res}$ (m) | $y_f$ (m) | $E_{tot}$ (m) | $\Delta E$ (m) |
|---|---|---|---|---|---|
| 01 | 13,3 | 3,04 | 0,57 | 15,445 | 12,405 |
| 02 | 27,78 | 3,6 | 0,51 | 30,86 | 27,26 |
| 03 | 38,46 | 4,16 | 0,47 | 42,105 | 37,945 |

Canal: $E_{tot} = 81{,}685$ m, $E_{res} = 4{,}075$ m, $y_f = 0{,}476$ m, $V_f = 8{,}403$ m/s, $Fr = 3{,}888$.

---

## 4.2.5 Quedas singulares

Avalia **um único degrau** (diferente das descidas em degraus acima). Calcula $D_N$ (4.23), $L_d$ (4.24), a profundidade
anterior (4.56), a posterior (4.25), a jusante do ressalto (4.26), a profundidade crítica e o comprimento do ressalto (3.13).

### Exemplo 4.5

Dados: $Q = 4$ m³/s, $B = 2{,}5$ m, $S = 1{,}5$ m, profundidade a montante $0{,}85$ m.

| Grandeza | Valor |
|---|---|
| $D_N$ | 0,077 |
| $L_d$ | 3,23 m |
| Profundidade anterior à queda $y_a$ | 0,85 m |
| Profundidade posterior à queda $y_1$ | 0,27 m |
| Profundidade a jusante do ressalto $y_2$ | 1,25 m |
| $y_c$ | 0,64 m |
| Comprimento do ressalto $L_j$ | 6,72 m |

---

## Escadas com trechos diferentes (extensão ao manual)

Esta seção **não vem do manual**: aplica a seção 4.2.4 a uma escada cujos trechos têm $S$, $l$, $N$ ou $B$ diferentes
(`escada_composta()` no código).

1. Cada trecho $i$ é classificado e dimensionado isoladamente, com sua vazão específica $q_i = Q/B_i$. Isso dá $E_{res,i}$ e $y_{f,i}$.
2. As energias são encadeadas pelas eqs. (4.54) e (4.55):

$$
E_{tot,1} = H_1 + E(y_0), \qquad
E_{tot,i} = H_i + E(y_{f,i-1}), \qquad
\Delta E_i = E_{tot,i} - E_{res,i}
$$

com $E(y) = y + \dfrac{q^2}{2\,g\,y^2}$. Se $y_0$ não for informado, o 1º trecho parte da crista em profundidade crítica, $E(y_c) = 1{,}5\,y_c$.

3. Para o canal inteiro: $E_{tot} = \sum H_i + E(y_0)$, $E_{res} = E_{tot} - \sum \Delta E_i$ e a profundidade final sai de $E(y) = E_{res}$.

**Extensão própria (não validada).** As eqs. do manual partem da crista, com $1{,}5\,y_c$. Num trecho de skimming ainda não
uniforme ($H_{dam} < H_e$) que não é o primeiro, a eq. (4.43) é aplicada com a energia de entrada do trecho:

$$
E_r = E_{in} + \left(E_{ru} - E_{in}\right)\left[1 - \left(1 - \frac{H_{dam}}{H_e}\right)^{m}\right]
$$

**Limites.** O encadeamento para quando um trecho cai em transição, em nappe sem ressalto ou fora das faixas de validade,
porque o manual não fornece $E_{res}$ nesses casos. Trechos de nappe seguintes ao primeiro são calculados a partir da crista, o que é aproximação.
Mudança de largura entre trechos não inclui perdas de transição. Exige-se que cada trecho tenha $0{,}05 \le S/l \le 1{,}43$.

---

## Notas de leitura

As equações abaixo têm grafia ambígua na versão em PDF do manual. Cada uma foi conferida contra os exemplos 4.1 a 4.5 e
reproduz os números dados lá (`validar_exemplos()` no código).

| Eq. | Leitura adotada | Evidência |
|---|---|---|
| 4.21 | $(7/6)\,(\tan\theta)^{1/6}$ | faixas de $Q$ das Figs. 4.3 e 4.4 (2,613 e 5,256 m³/s) |
| 4.20 | $(\tan\theta)^{1{,}276}/0{,}0916$ | curva tracejada da Fig. 4.4; classifica o exemplo 4.2 como parcial |
| 4.24 | $L_d/S$ | $L_d = 1{,}399$ m no exemplo 4.2 |
| 4.27 | termo $0{,}02^{2{,}5}$ lido literalmente | impressão duvidosa; sem exemplo para conferir |
| 4.30 | $H_{máx}$ multiplica o numerador inteiro | análise dimensional |
| 4.31 | $\Delta H/H_{máx}$, soma de $(1-\alpha)^i$, $\alpha = 0{,}54$ | eficiência de 84,214 % no exemplo 4.2 |
| 4.34 | $f_{máx} - A\,(0{,}5 - S/y_c)^2$ | $f = 0{,}172$ no exemplo 4.3 |
| 4.36 | $A = -1{,}7\!\times\!10^{-3}\theta^2 + 6{,}4\!\times\!10^{-2}\theta - 1{,}5\!\times\!10^{-1}$ | continuidade: $A(19^\circ) = 0{,}452$ |
| 4.43 | $E_{ru}$ dividido por $y_c$ | limites $H_{dam}=0$ e $H_{dam}=H_e$ |
| 4.45 | expoente $-5\,(S/y_c)^2 - 4\,S/y_c$ | $C_{med} = 0{,}369$ no exemplo 4.3 |
| 4.53 | não implementada | a variável $x/L_a$ não aparece na grafia impressa |

Os polinômios (4.19), (4.22), (4.33), (4.37), (4.39) e (4.46) foram lidos como impressos e são consistentes com os gráficos
e exemplos do manual, mas apenas os exemplos 4.1 a 4.5 foram testados. Para uso em projeto, confira os coeficientes
nas fontes originais (Yasuda et al. 2001; Chanson 1994 e 2001; Ohtsu et al. 2004).

## Mapa equação → código

| Seção do manual | Função em `escada_hidraulica.py` |
|---|---|
| 4.17 a 4.22 | `lim_nappe`, `lim_skimming`, `lim_ressalto_completo`, `lim_ressalto_parcial`, `lim_tipo_B`, `yc_max_chanson`, `faixas_vazao`, `classificar_regime` |
| 4.23 a 4.32 | `calcular_nappe` |
| 4.33 a 4.52 | `calcular_skimming`, `coef_atrito`, `conc_ar` |
| 4.54 e 4.55 | `canal_trechos_distintos` |
| 4.56 | `queda_singular` |
| Orquestração | `dimensionar`, `relatorio` |
| Extensão (trechos diferentes) | `escada_composta`, `relatorio_composta` |
| Validação | `validar_exemplos` |
| Extra (não é do SisCCoH) | `perfil_gvf` |

## Referências citadas no manual

- Chanson (1994, 2001, 2002); Gomes (2006); Keller e Rastogi (1977); Matos e Quintela *apud* Simões (2008); Ohtsu et al. (2004);
  Simões (2008); Yasuda e Ohtsu (1999); Yasuda et al. (2001).
- Gomes, J. F. (2006). *Campo de pressões: condições de incipiência à cavitação em vertedouros em degraus com declividade IV:0,75H.*
  Tese (Doutorado), IPH/UFRGS, Porto Alegre.
