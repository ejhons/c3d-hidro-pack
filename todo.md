# Plugin Hydra

## Bacias

- [X] Estabelecer contorno
- [X] Estabelecer talvegue e permitir que sua declividade seja calculada com base em uma superfície
- [X] Caracterizar: runoff, cn, etc.
- [X] Calcular tempo de concentração (escolher método)
- [X] Transformação chuva-vazão (Escolher método)
- [X] Calcular hidrograma (Escolher método)

## Precipitação

- [X] Definir IDF, TR, Tempo de concentração e duração
- [X] Visualizar IDF
- [ ] Calcular hietograma (Escolher método)

## Sarjetas

- [ ] Criar seções de sarjeta (permitir o uso de diferentes tipos como simplificada, com duas declividades transversais, circular, etc)
- [ ] Definir seção de sarjeta
- [ ] Visualizar seção de sarjeta
- [ ] Calcular sarjeta com base em método
- [ ] Calcular sarjeta em intervalos e gerar lâmina d'água

## Rede

- [ ] Definir seções de rede/galeria/canal
- [ ] Definir tubos (links) onde definimos cotas de fundo, declividade, comprimento e material
- [ ] Definir structures/nodes como pontos de comunicação entre os links (mas ainda em avaliação se é necessário)
- [ ] Calcular seção usando manning e atribuir propriedades (raio hidráulico, lâmina, vazão e velocidade)

## Reservatório

- [ ] Definir superfície com referência
- [ ] Definir área do reservatório (boundary para a superfície)
- [ ] Extrair CAV com base na superfície
- [ ] Caracterizar reservatório:
  - [ ] vertedouro, amortecimento, cotas
- [ ] Associar objetos de contribuição responsáveis por fornecer um hidrograma de entrada
- [ ] Calcular com Puls
