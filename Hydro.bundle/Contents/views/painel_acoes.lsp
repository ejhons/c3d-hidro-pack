;;; ============================================================
;;; views/painel_acoes.lsp - BOTOES DO PAINEL PARA OS COMANDOS EXISTENTES
;;;
;;; Os plugins e models nao conhecem o painel (cada um funciona sozinho); os
;;; botoes dos comandos deles ficam aqui, na camada de interface. A coluna
;;; "requer" usa a feature que define o comando: model (bacia), view
;;; (bacia-view, idf-view...) ou plugin. Um plugin NOVO cadastra o proprio botao no seu
;;; arquivo, com (PNL:Acao ...), sem mexer neste (principio aberto/fechado).
;;;
;;; (PNL:Acao id grupo ordem-grupo ordem rotulo comando requer)
;;; Rotulos em ASCII e sem aspas, curtos (a largura do botao e a do maior rotulo
;;; do grupo, ate 44 caracteres).
;;; ============================================================

;;; ---- 10: Dados e IDF
(PNL:Acao "idf.calcular"    "Dados e IDF" 10 10 "Equacao IDF (tr, tc, duracao)" "IDF" '("idf-view"))
(PNL:Acao "idf.parametros"  "Dados e IDF" 10 20 "Parametros da IDF"             "ATUALIZAIDF" '("idf-view"))
(PNL:Acao "idf.tr"          "Dados e IDF" 10 30 "Tempo de retorno"              "ATUALIZATR" '("idf-view"))

;;; ---- 20: Bacias
(PNL:Acao "bacia.cadastrar" "Bacias" 20 10 "Cadastrar bacia"             "BACIACAD" '("bacia"))
(PNL:Acao "bacia.calcular"  "Bacias" 20 20 "Calcular vazao da bacia"     "BACIA" '("bacia"))
(PNL:Acao "bacia.calctexto" "Bacias" 20 30 "Calcular e inserir texto"    "CRIARBACIARESULTADO" '("bacia-view"))
(PNL:Acao "bacia.texto"     "Bacias" 20 40 "Inserir texto de resultado"  "TEXTOBACIA" '("bacia-view"))
(PNL:Acao "bacia.info"      "Bacias" 20 50 "Dados da bacia"              "BACIAINFO" '("bacia"))
(PNL:Acao "bacia.zoom"      "Bacias" 20 55 "Localizar bacia (zoom)"      "BACIAZOOM" '("bacia" "objetos-padrao-view"))
(PNL:Acao "bacia.lista"     "Bacias" 20 60 "Listar bacias (texto)"       "BACIAS" '("bacia"))
(PNL:Acao "bacia.tabela"    "Bacias" 20 70 "Tabela de bacias"            "BACIATABELA" '("bacia-tabela"))

;;; ---- 30: Hidrogramas
(PNL:Acao "hid.gerar"       "Hidrogramas" 30 10 "Gerar hidrograma"       "HIDROGRAMA" '("hidrograma-view"))
(PNL:Acao "hid.ver"         "Hidrogramas" 30 20 "Ver hidrogramas da bacia" "HIDROGRAMAVER" '("hidrograma-view"))

;;; ---- 40: Objetos e ligacoes
(PNL:Acao "obj.cadastrar"   "Objetos e ligacoes" 40 10 "Cadastrar objeto hidraulico"  "OBJETO" '("objetos"))
(PNL:Acao "obj.listar"      "Objetos e ligacoes" 40 15 "Listar objetos"               "OBJETOS" '("objetos-padrao-view"))
(PNL:Acao "obj.zoom"        "Objetos e ligacoes" 40 25 "Localizar objeto (zoom)"      "OBJETOZOOM" '("objetos-padrao-view"))
(PNL:Acao "obj.info"        "Objetos e ligacoes" 40 20 "Dados do objeto"              "OBJETOINFO" '("objetos"))
(PNL:Acao "lig.ligar"       "Objetos e ligacoes" 40 30 "Ligar (origem -> destino)"    "LIGAR" '("ligacao"))
(PNL:Acao "lig.desligar"    "Objetos e ligacoes" 40 40 "Desligar origem"              "DESLIGAR" '("ligacao"))
(PNL:Acao "obj.calcular"    "Objetos e ligacoes" 40 50 "Calcular objeto"              "CALCULAOBJETO" '("ligacao"))
(PNL:Acao "lig.tabela"      "Objetos e ligacoes" 40 60 "Tabela de objetos e ligacoes" "LIGACOES" '("objetos-tabela"))
(PNL:Acao "lig.validar"     "Objetos e ligacoes" 40 70 "Validar ligacoes"             "VALIDARLIGACOES" '("ligacao"))
(PNL:Acao "obj.vinculos"    "Objetos e ligacoes" 40 75 "Realcar vinculos (talvegue...)" "OBJETOVINCULOS" '("objetos-padrao-view"))
(PNL:Acao "obj.preserva"    "Objetos e ligacoes" 40 78 "Preservar maior vazao (entrada/saida)" "PRESERVAVAZAO" '("ligacao"))
(PNL:Acao "obj.remover"     "Objetos e ligacoes" 40 80 "Remover cadastro de objeto"   "OBJETOREMOVER" '("objetos"))

;;; ---- 45: Sarjetas
(PNL:Acao "sarjeta.cad"     "Sarjetas" 45 10 "Cadastrar / editar sarjeta"       "SARJETACAD" '("sarjeta-obj" "objetos-padrao-view"))
(PNL:Acao "sarjeta.lista"   "Sarjetas" 45 20 "Listar sarjetas"                  "SARJETAS" '("sarjeta-obj" "objetos-padrao-view"))
(PNL:Acao "sarjeta.info"    "Sarjetas" 45 30 "Dados da sarjeta"                 "SARJETAINFO" '("sarjeta-obj" "objetos-padrao-view"))
(PNL:Acao "sarjeta.zoom"    "Sarjetas" 45 40 "Localizar sarjeta (zoom)"         "SARJETAZOOM" '("sarjeta-obj" "objetos-padrao-view"))

;;; ---- 50: Secoes
(PNL:Acao "secao.criar"     "Secoes" 50 10 "Criar secao de sarjeta"                 "CRIASECAO" '("secao-view"))
(PNL:Acao "secao.editar"    "Secoes" 50 20 "Editar secao de sarjeta"                 "EDITASECAO" '("secao-view"))
(PNL:Acao "secao.remover"   "Secoes" 50 30 "Remover secao de sarjeta"                "REMOVESECAO" '("secao-view"))
(PNL:Acao "secao.ver"       "Secoes" 50 50 "Visualizar secoes"                      "SECAO" '("secao-view"))

;;; ---- 60: Texto e parametros

;;; ---- 90: Sistema
(PNL:Acao "sis.auditoria"   "Sistema" 90 5 "Auditar e corrigir o desenho"    "HYDROAUDIT" '("auditoria-view"))
(PNL:Acao "sis.dados"       "Sistema" 90 10 "Dados persistidos (DB e XData)" "HYDRODADOS" '("visualizador"))
(PNL:Acao "sis.dump"        "Sistema" 90 20 "Dados em texto"                 "HYDRODUMP" '("visualizador"))
(PNL:Acao "sis.plugins"     "Sistema" 90 30 "Plugins ativos"                 "HYDROPLUGINS" nil)
(PNL:Acao "sis.reload"      "Sistema" 90 40 "Recarregar o Hydro"             "HYDRORELOAD" nil)
(PNL:Acao "sis.dir"         "Sistema" 90 50 "Escolher a pasta do Hydro"      "HYDRODIR" nil)
(PNL:Acao "sis.macros"      "Sistema" 90 60 "Exportar macros (ribbon)"       "HYDROMACROS" '("painel"))
(PNL:Acao "sis.macroestilo" "Sistema" 90 65 "Estilo das macros (menu/barras)" "HYDROMACROESTILO" '("painel"))
(PNL:Acao "sis.teste"       "Sistema" 90 70 "Executar testes"                "HYDROTESTE" nil)

;; Comandos do fluxo antigo de sarjetas (CALCULASARJETA..., CRIASECAO, ATUALIZARUNOFF...)
;; pertencem ao plugin plugins/sarjetas, que nao esta nesta arvore; quando ele
;; voltar, cadastre os botoes dele no proprio arquivo com (PNL:Acao ...).

(HYDRO:Provide "painel-acoes" "1.0")
(princ)
