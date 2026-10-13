# Bacias de dissipação — SisCCoH 1.1 (seções 4.3 e 4.4)

Transcrição em Markdown + LaTeX das seções **4.3 (Bacias por ressalto hidráulico, USBR)** e **4.4 (Bacias em enrocamento, FHWA/HEC‑14)** do *Manual Técnico do SisCCoH 1.1*, com o mapa para o código `bacias_dissipacao.py`.

Etiquetas usadas: **[LEITURA]** equação lida da figura do manual · **[CALIBRADO]** ambiguidade resolvida pelo exemplo numérico · **[DEDUZIDO]** inferido do texto · **[MEMÓRIA]** não consta no manual (vem de Peterka 1984 / HEC‑14) · **[FIGURA]** dado só na figura.

---

## 1. Notação

| Símbolo | Significado | Unidade |
|---|---|---|
| $Q$ | vazão | m³/s |
| $B$ | largura da bacia (canal retangular) | m |
| $D_1$ | profundidade a montante (supercrítica) | m |
| $D_2$ | profundidade conjugada a jusante | m |
| $V_1 = U_1$ | velocidade a montante | m/s |
| $Fr_1$ | Froude a montante | – |
| $L$ | comprimento da bacia | m |
| $\Delta E$ | energia dissipada no ressalto | m |
| $U_{saída}$ | velocidade de saída | m/s |
| $h_1, w_1, s_1$ | altura, largura e espaçamento dos blocos de queda | m |
| $h_3$ | altura dos blocos de amortecimento (*baffle piers*) | m |
| $h_4$ | altura da soleira terminal (*end sill / end fill*) | m |

---

## 2. Bacias por ressalto hidráulico (USBR — Peterka, 1984)

### 2.1 Dados e verificações

Entram $Q$, $B$ e $D_1$. Calcula-se:

$$V_1 = \frac{Q}{B\,D_1} \qquad\qquad Fr_1 = \frac{V_1}{\sqrt{g\,D_1}}$$

- Dados ausentes ou nulos → *"Dados incompatíveis para a resolução do problema!"*
- $Fr_1 < 1{,}2$ → *"Os resultados obtidos estão fora do intervalo estabelecido para o cálculo. Tente outros dados."*

### 2.2 Classificação

| Condição | Tipo |
|---|---|
| $1{,}2 < Fr_1 < 2{,}5$ | **I** |
| $2{,}5 \le Fr_1 \le 4{,}5$ | **IV** |
| $Fr_1 > 4{,}5$ e $V_1 \ge 20$ m/s ("próxima a 20") | **II** |
| $Fr_1 > 4{,}5$ e $V_1 < 20$ m/s | **III** |

### 2.3 Bacia tipo I

$$D_2 = 2\,D_1 \tag{4.57}$$

$$L_I = 4\,D_2 \tag{4.58}$$

$$\Delta E = \frac{(D_2 - D_1)^3}{4\,D_1\,D_2} \tag{4.59}$$

$$U_{saída} = \frac{Q}{B\,D_2} \tag{4.60}$$

$$\text{borda livre} = 0{,}1\,(U_1 + D_2) \tag{4.61}$$

$$H_{parede} = \text{borda livre} + D_2 \tag{4.62}$$

### 2.4 Bacia tipo II

$D_1$ = profundidade de entrada; $D_2$ = conjugada a jusante; profundidade de saída 5 % maior que $D_2$; comprimento

$$L_{II} \approx 4{,}3\,D_2$$

### 2.5 Bacia tipo III

Comprimento adotado

$$L_{III} = 2{,}7\,D_2$$

com blocos de queda ($w_1$, $h_1$), blocos de amortecimento e soleira terminal (Fig. 4.17):

$$\frac{h_3}{D_1} = 0{,}1652\,Fr_1 + 0{,}6768 \tag{4.63}$$

$$\frac{h_4}{D_1} = 0{,}0542\,Fr_1 + 1{,}0167 \tag{4.64}$$

Demais dimensões [FIGURA/MEMÓRIA — Peterka]: $h_1 = w_1 = s_1 = D_1$; $A = 0{,}5\,D_1$; $w_3 = s_3 = 0{,}75\,h_3$; $B_{dente} = 0{,}375\,h_3$; $C = 0{,}2\,h_3$; $D = 0{,}8\,D_2$.

### 2.6 Bacia tipo IV ($2{,}5 \le Fr_1 \le 4{,}5$)

$$\frac{L_{IV}}{D_2} = 2{,}0543\,\ln Fr_1 + 2{,}8865 \tag{4.65}$$

Blocos conforme a Fig. 4.18 (valores de Peterka, **não validados** contra o manual): largura $=D_1$, espaçamento $=2{,}5\,D_1$, altura $=2\,D_1$, primeira fila a $\ge 2\,D_1$ do início.

### 2.7 Exemplo 4.6

Dados: $Q=10$ m³/s, $B=2{,}5$ m, $D_1=0{,}215$ m.

| Grandeza | Valor |
|---|---|
| $V_1$ | 18,6 m/s |
| $Fr_1$ | 12,81 → **tipo III** |
| $D_2$ | 3,79 m |
| $L_{III}=2{,}7D_2$ | 10,23 m |
| $\Delta E$ | 14,01 m |
| $U_{saída}$ | 1,06 m/s |
| borda livre | 2,24 m |
| $H_{parede}$ | 6,03 m |

O código reproduz todos os valores acima (e as dimensões $h_3,h_4,A,B,C,w_1,w_3,s_1,s_3,h_1,D$ da figura) dentro de 1,2 %.

---

## 3. Bacias em enrocamento (FHWA, 2006 — HEC‑14)

### 3.1 Premissas

a) espessura do enrocamento $\ge 2D_{50}$ ou $1{,}5D_{máx}$;
b) $h_s/D_{50} \ge 2$;
c) $L_s = 10\,h_s$ e $L_s \ge 3W_0$;
d) comprimento de aproximação $L_A = 15\,h_s$ e $\ge 4W_0$ (ver nota 5).

Diâmetros extremos (Taylor, 1973):

$$D_{máx} = D_{100} = D_{50}\sqrt[3]{4} \tag{4.66}$$

$$D_{mín} = D_0 = D_{50}\sqrt[3]{\tfrac{1}{4}} \tag{4.67}$$

Em canal retangular com escoamento supercrítico, $y_e$ = profundidade ao final do canal.

### 3.2 Procedimento

1. Escolher a curva: **Best curve** (jusante supercrítico, ou falha facilmente reparável) ou **Envelope curve** (jusante subcrítico ou falha severa).
2. Informar $W_0$, $y_e$, $D_{50}$, $TW$ (nível a jusante) e $V_0$.
3. Obter o parâmetro de tailwater $C_o$ (depende de $TW/y_e$ e da curva) e a relação $h_s/y_e$.
4. Verificar:
   - $D_{50}/y_e \ge 0{,}1$ → senão *"…D50/ye < 0,1. Tente outro D50!"*
   - $D_{50}/y_e \le 0{,}7$ → senão *"…D50/ye > 0,7. Tente outro D50!"*
   - $h_s/D_{50} \ge 2$ → senão *"…hs/D50 < 2. Tente outro D50!"*
5. Calcular $L_s$, $L_B$, espessuras e largura de saída; comparar velocidade de saída com a permitida no canal de jusante.

Profundidade na saída (trapezoidal, iterativa):

$$\frac{Q^2}{g} = \frac{\left[(W_B + z\,y_3)\,y_3\right]^3}{W_B + 2\,z\,y_3} \tag{4.68}$$

com $z$ = declividade lateral (H:V), $y_3$ = profundidade e $W_B$ = largura de fundo na saída.

### 3.3 Valores de $C_o$ [MEMÓRIA — HEC‑14]

| $TW/y_e$ | Best curve | Envelope curve |
|---|---|---|
| $< 0{,}75$ | 1,4 | 2,0 |
| $0{,}75 – 1{,}0$ | 0,7 | 1,0 |

### 3.4 Exemplo 4.7 (Envelope curve)

Dados: $W_0=2{,}44$ m, $y_e=1{,}22$ m, $D_{50}=0{,}55$ m, $TW=0{,}85$ m, $V_0=7{,}63$ m/s.

| Grandeza | Valor |
|---|---|
| $D_{mín}$ / $D_{máx}$ | 0,346 / 0,873 m |
| $C_o$ | 2 |
| $D_{50}/y_e$ | 0,451 |
| $Fr_0$ | 2,206 |
| $h_s/D_{50}$ | 2,084 |
| $L_s$ | 11,465 m |
| $L_B$ | 17,197 m |
| $L_A$ | 5,732 m |
| $W_B$ | 13,905 m |
| espessura (HEC‑14) | 1,65 / 1,31 m |

Todos reproduzidos pelo código.

---

## 4. Notas de leitura

1. **Eq. 4.57** (tipo I, $D_2=2D_1$) é a aproximação do manual; o código usa-a só no tipo I. Nos demais tipos usa a conjugada de Bélanger $D_2 = \tfrac{D_1}{2}\left(\sqrt{1+8Fr_1^2}-1\right)$ — o Exemplo 4.6 confirma.
2. **Eq. 4.60**: o texto impresso mostra "$L\cdot D$" no denominador; a leitura coerente (e que bate com o exemplo) é $B\cdot D$ [CALIBRADO].
3. **Corte II/III**: o manual diz "$Fr>4{,}5$ e velocidade próxima a 20 m/s" (II) e "$<20$ m/s" (III); adotei $V_1\ge20$ → II [DEDUZIDO]. $Fr=4{,}5$ exato cai no tipo IV.
4. **Tipo II**: profundidade de saída $1{,}05D_2$ e $L=4{,}3D_2$ são do manual; geometria dos blocos/soleira não é dada [NÃO IMPL.].
5. **$L_A$**: o texto diz $L_A = 15h_s$, mas o exemplo só fecha com $L_A = L_B - L_s$ com $L_B=\max(15h_s,\,4W_0)$ [CALIBRADO].
6. **$W_B$** (largura na saída): $W_B = W_0 + \tfrac{2}{3}L_B$ (abertura em planta) [DEDUZIDO do exemplo].
7. **Espessuras**: $\max(2D_{50},\,1{,}5D_{máx})$ para a camada principal e $3D_{50}$ para a outra; deduzidas do exemplo (1,65 e 1,31) [DEDUZIDO].
8. **$h_s$ não está no manual** — deve vir de FHWA (2006) (profundidade de erosão). O código exige $h_s$ como entrada.
9. **Eq. 4.68** não tem exemplo numérico no manual; implementada por bissecção e verificada só por consistência ($y_3$ reproduz $Q$).
10. A mensagem de erro do manual escreve "$h_s/D_{50}<2$" na lista de validade, mas a condição correta de projeto é $h_s/D_{50}\ge2$ (premissa b).

---

## 5. Mapa equação → código (`bacias_dissipacao.py`)

| Item | Função |
|---|---|
| $V_1$, $Fr_1$ | `froude(V, y)` |
| Conjugada de Bélanger | `conjugada_belanger(D1, Fr1)` |
| Classificação I–IV | `classificar_bacia(Fr1, V1, V_lim=20)` |
| 4.57–4.65 + elementos | `bacia_usbr(Q, B, D1)` → `ResultadoBacia` |
| 4.66–4.67 | `diametros_enrocamento(D50)` |
| $C_o$ | `parametro_Co(TW, ye, curva)` |
| 4.68 | `profundidade_critica_trapezio(Q, WB, z)` |
| Enrocamento completo | `bacia_enrocamento(W0, ye, D50, TW, V0, hs, curva, z)` → `ResultadoEnrocamento` |
| Relatórios | `relatorio_bacia`, `relatorio_enrocamento` |
| Validação (Ex. 4.6 e 4.7) | `validar_exemplos()` |

Uso:

```python
from bacias_dissipacao import bacia_usbr, bacia_enrocamento, relatorio_bacia, relatorio_enrocamento

print(relatorio_bacia(bacia_usbr(Q=10, B=2.5, D1=0.215)))
print(relatorio_enrocamento(
    bacia_enrocamento(W0=2.44, ye=1.22, D50=0.55, TW=0.85, V0=7.63,
                      hs=1.147, curva="envelope", z=2)))
```

---

## 6. Referências

- Peterka, A. J. (1984). *Hydraulic Design of Stilling Basins and Energy Dissipators*. USBR, Engineering Monograph 25.
- FHWA (2006). *Hydraulic Design of Energy Dissipators for Culverts and Channels* (HEC‑14, 3ª ed.).
- Taylor, B. D. (1973). Diâmetros extremos de enrocamento.
- *Manual Técnico do Programa SisCCoH 1.1* — seções 4.3 e 4.4.
