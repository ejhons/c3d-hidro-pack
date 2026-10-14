;;; ============================================================
;;; models/bacia.lsp - MODELO BACIA (BAC:)
;;;
;;; Representa a bacia hidrografica no sistema: uma polilinha de CONTORNO
;;; (fechada) + uma polilinha de TALVEGUE. So a funcionalidade do OBJETO:
;;; registro, caracterizacao, tempo de concentracao, calculo de vazao e a
;;; declaracao do tipo "bacia" no catalogo de objetos. Tambem traz os COMANDOS de
;;; linha de comando (BACIACAD, BACIAEDITA, BACIA, BACIAS, BACIAINFO, BACIAZOOM),
;;; para o objeto funcionar com um unico .lsp. Texto inserido no desenho fica em
;;; views/bacia_view.lsp; o dialogo em views/bacia_tabela.lsp.
;;;
;;; ESTRUTURA DO ARQUIVO (padrao dos models; ver .claude/skills/hydro-model)
;;;   1. UTILITARIOS                    funcoes pequenas, sem regra de negocio
;;;   2. GEOMETRIA (CARACTERIZACAO)     o que se le do desenho -> CARACT
;;;   3. LER, GRAVAR, EDITAR, REMOVER   porta de armazenamento do tipo
;;;   4. CAMPOS (CARACT, PARAMS, ATRIB) acessos aos campos do registro
;;;   5. RESULTADOS (RESULT)            acessos e gravacao dos grupos calculados
;;;   6. CALCULOS                       funcoes que PRODUZEM os campos de RESULT
;;;   7. RESUMO E FORMATACAO            linhas de texto e toString (sem desenhar)
;;;   8. TIPO NO CATALOGO               rotulos, eventos e OBJ:RegistrarTipo
;;;   9. COMANDOS E INTERACAO           comandos c: e perguntas da linha de comando
;;;   toString: BAC:ToString (secao 7), tambem a capacidade "TOSTRING" do tipo
;;;
;;; ONDE FICAM OS DADOS
;;;   Dicionario de extensao da polilinha do contorno, chave "HYDRO-OBJ", no
;;;   REGISTRO PADRAO dos objetos (docs/arquitetura.md secao 18). O plugin
;;;   trabalha diretamente com ele ("dados" nas funcoes abaixo):
;;;     (("VERSAO" . 2) ("TIPO" . "bacia") ("NOME" . n) ("DESCRICAO" . txt)
;;;      ("PARAMS" . (("TALVEGUE" . "handle")            ; componente da bacia
;;;                   ("JUSANTE" . ("h1" . T))))         ; destino, opcional; ver ligacao.lsp
;;;      ("ATRIB"  . (("C" . 0.6) ("CN" . 80.0)         ; definidos pelo usuario
;;;                   ("TC-METODO" . id) ("TC-USUARIO" . min)))   ; 0 = calcular pelo metodo
;;;      ("CARACT" . (("AREA" . m2) ("COMP" . m) ("DESNIVEL" . m) ("DECL" . m/m)
;;;                   ("MANUAL" . chaves)))             ; do desenho ou digitado (CARACT-DEFS)
;;;      ("RESULT" . (("TR25" . cenario) ...)))          ; por CENARIO (plano_resultados_cenarios)
;;;     cenario = (("CENARIO" ("TR" . 25.0) ["OBSOLETO" . T])
;;;                ("TC"           ("VALOR" . min) ("METODO" . id | "usuario") ("INPUT" . alist))
;;;                ("PRECIPITACAO" ("VALOR" . mm|mm/h) ("UNIDADE" ..) ("I" ..) ("P" ..) ("PE" ..))
;;;                ("ENTRADA"      ("VALOR" . m3/s) ("TC" . min) ("AREA" . m2))   ; so com montantes
;;;                ("VAZAO"        ("VALOR" . m3/s) ("TC" . min) ("METODO" . id) ("DUR" ..)
;;;                                ("VOLUME" ..) ("INPUT" . alist) ("QP-PROPRIO" ..) ...)
;;;                ("HIDROGRAMA"   ("VALOR" . Qp m3/s) ("TIPO" . id) ("TP" ..) ("TB" ..)
;;;                                ("VOLUME" ..) ("DUR" ..) ("INPUT" ..) ("PONTOS" . ((t . q) ...))))
;;;   O TIPO do hidrograma e definido na bacia (ATRIB HIDROGRAMA-TIPO); o grupo HIDROGRAMA e
;;;   gerado por HIDROGRAMA (plugin hidrograma) e removido quando a vazao do cenario e recalculada.
;;;   Campos planos por grupo; um resultado por grupo em cada cenario (recalcular substitui).
;;;   Adaptadores em formato "plano" (so para texto e menus): BAC:Vazao (lista, um por
;;;   cenario com vazao), BAC:CalcDe dados cenario, BAC:Tc.
;;;   Acompanha a entidade ao copiar, colar e salvar o desenho.
;;;   Armazenamento HERDADO da classe base (objetos.lsp), igual ao da sarjeta: BAC:Ler e
;;;   so a leitura tipada (OBJ:RegistroDe); grava com OBJ:GravaRegistro "bacia".
;;;   Valores nil nao sao gravados.
;;;
;;; TEMPO DE CONCENTRACAO
;;;   Metodos no catalogo "metodo-tc" (registry/tempo_conc). Sem ele, so Kirpich.
;;;   O CADASTRO NAO CALCULA: guarda so o metodo (ATRIB TC-METODO) ou o valor informado
;;;   (TC-USUARIO > 0). O tc nasce em BAC:Preparar (no calculo): rele o desenho
;;;   (OBJ:AtualizaCaract), aplica BAC:TcDe (tc minimo do projeto); o grupo TC do cenario
;;;   e gravado junto com o resto do calculo (BAC:_CalcularEGravar).
;;;   Parametros do metodo de tc: padrao do projeto / ultimo usado (HYDRO.TC.<id>.*).
;;;   TALVEGUE e opcional (PARAMS-DEFS): sem ele, COMP e DECL sao digitados (CARACT-DEFS).
;;;
;;; BACIAS A MONTANTE (PARAMS "JUSANTE" de cada origem, plugin ligacao)
;;;   TALVEGUE e componente da bacia e continua em campo proprio. Os montantes dela sao
;;;   os objetos que citam a bacia em JUSANTE (calculados), com o flag "contribui
;;;   diretamente ao talvegue" gravado na origem.
;;;   A bacia e um mecanismo ENTRADA -> SAIDA (ligacao.lsp). Sem montante so tem SAIDA
;;;   (a propria). Com montantes (BAC:_CalcularEGravar):
;;;     ENTRADA  Q = soma das saidas dos montantes, tc = maior tempo de saida (grupo
;;;              "ENTRADA", gravado)
;;;     tempo de SAIDA = LIG:TcPuro "concentracao" (paralelo se nao contribui ao
;;;              talvegue, serie se contribui); a chuva usa SEMPRE esse maior tempo
;;;     Q_calc   = bacia propria + montantes reavaliados nesse tempo (racional composto)
;;;     Q SAIDA  = max(Q entrada, Q_calc) com a flag geral HYDRO.VAZAO.PRESERVA
;;;   A entrada do grupo "VAZAO" e a SAIDA: QP/VOLUME totais, TC de saida, e acrescenta
;;;   QP-PROPRIO, AREA-TOTAL, TC-PROPRIO, QP-CALC e PRESERVADA (quando preservou).
;;;   Os montantes devem ser calculados antes, com o mesmo METODO e TR.
;;;
;;; EVENTOS EMITIDOS
;;;   "objeto.cadastrado" "OBJETO" "TIPO" ("bacia"), emitido por OBJ:Salvar ao fim do
;;;                      cadastro generico; o talvegue sai de PARAMS (OBJ:ParamsDe)
;;;   "bacia.calculada"  "BACIA" "TALVEGUE" "CENARIO" "NOME" "AREA" "COMP" "DECL" "TC"
;;;                      "METODO" "TR" "DUR" "QP" "PE" "VOLUME"
;;;   "objeto.removido"  "OBJETO" (OBJ:Remover; antes de apagar; gancho AO-REMOVER limpa XData)
;;;
;;; TIPO DE OBJETO
;;;   Ao fim deste arquivo a bacia se declara no catalogo "objeto-hidraulico"
;;;   (se o plugin objetos estiver carregado), sem armazenamento proprio
;;;   (indice HYDRO.OBJETOS, o da classe base) e as capacidades de vazao, area e destino padrao.
;;; ============================================================
(vl-load-com)


;;; ------------------------------------------------------------
;;; 1. UTILITARIOS
;;; ------------------------------------------------------------
(defun BAC:_Try (fn / r)
  (setq r (vl-catch-all-apply fn nil))
  (if (vl-catch-all-error-p r) nil r)
)

(defun BAC:_Erro (msg)
  (list (cons "ERRO" msg))
)

;; Utilitarios de alist (OBJ:Limpa, OBJ:SetChave; HYDRO:Val vem do core) vem da classe base.

;; alist sem as chaves da lista
(defun BAC:_SemChaves (pares chaves)
  (vl-remove-if (function (lambda (x) (member (car x) chaves))) pares)
)

;; Nome para exibir: o cadastrado ou "B-<handle>"
(defun BAC:NomeExib (dados h)
  (if (BAC:Nome dados) (BAC:Nome dados) (strcat "B-" h))
)

;; Nome do método de cálculo chuva-vazão salvo como default
(defun BAC:NomeMetodo (id / m)
  (setq m (HYDRO:RegGet "metodo-chuva-vazao" id))
  (if m (cdr (assoc "NOME" m)) id)
)

;; Nome do método default de cálculo do tempo de concentração
(defun BAC:NomeTc (id / m)
  (cond
    ((not id) "-")
    ((equal id "usuario") "informado")
    (t
      (setq m (HYDRO:RegGet "metodo-tc" id))
      (if m (cdr (assoc "NOME" m)) id)
    )
  )
)


;;; ------------------------------------------------------------
;;; 2. GEOMETRIA (CARACTERIZACAO)
;;; ------------------------------------------------------------
;; Área da polilinha de contorno da bacia
(defun BAC:_Area (en)
  (BAC:_Try
    (function (lambda () (vla-get-Area (vlax-ename->vla-object en))))
  )
)

;; Comprimento da polilinha usada como talvegue
(defun BAC:_Comprimento (en)
  (BAC:_Try
    (function
      (lambda () (vlax-curve-getDistAtParam en (vlax-curve-getEndParam en)))
    )
  )
)

;; Testa se polilinha do contorno está fechada
(defun BAC:_Fechada (en)
  (BAC:_Try (function (lambda () (vlax-curve-isClosed en))))
)

;; Superficie TIN escolhida com ATUALIZASUPERFICIE (chave compartilhada)
(defun BAC:Superficie (/ h)
  (setq h (HYDRO:Get "HYDRO.SURFACE.HANDLE" nil))
  (if h (handent h) nil)
)

;; Coleta a elevacao em uma coordenada na superficie
(defun BAC:_ElevSuperficie (surf pt)
  (BAC:_Try
    (function
      (lambda ()
        (vlax-invoke-method
          (vlax-ename->vla-object surf) 'FindElevationAtXY (car pt) (cadr pt))
      )
    )
  )
)

;; Desnivel entre o inicio e o fim do talvegue (com superficie ou pela cota
;; da propria polilinha, util para polilinhas 3D)
(defun BAC:_Desnivel (en surf / p1 p2 z1 z2)
  (setq p1 (vlax-curve-getStartPoint en))
  (setq p2 (vlax-curve-getEndPoint en))
  (if surf
    (setq z1 (BAC:_ElevSuperficie surf p1)
          z2 (BAC:_ElevSuperficie surf p2))
    (setq z1 (caddr p1)
          z2 (caddr p2))
  )
  (if (and z1 z2) (- z2 z1) nil)
)

;; Caracteriza a bacia pelo desenho (capacidade CARACTERIZA; nao pergunta nada).
;;   contorno : ename da polilinha do contorno
;;   vinculos : alist (chave . ename) de PARAMS-DEFS; "TALVEGUE" e opcional
;;   retorno: alist parcial (AREA COMP DESNIVEL DECL). O que nao der para ler (sem
;;            talvegue, ponto fora da superficie) nao entra; o cadastro pergunta
;;            AREA, COMP e DECL (CARACT-DEFS) e o calculo exige os que faltarem.
(defun BAC:Caracterizar (contorno vinculos / talv comp desn)
  (setq talv (cdr (assoc "TALVEGUE" vinculos)))
  (setq comp (if talv (BAC:_Comprimento talv) nil))
  (setq desn
    (if (and comp talv)
      (vl-catch-all-apply 'BAC:_Desnivel (list talv (BAC:Superficie)))
      nil))
  (if (vl-catch-all-error-p desn) (setq desn nil))
  (OBJ:Limpa
    (list
      (cons "AREA" (BAC:_Area contorno))
      (cons "COMP" (if (and comp (> comp 0.0)) comp nil))
      (cons "DESNIVEL" (if desn (abs desn) nil))
      (cons "DECL" (if (and comp desn (> comp 0.0)) (/ (abs desn) comp) nil))
    )
  )
)

;;; ------------------------------------------------------------
;;; 3. LER, GRAVAR, EDITAR, REMOVER
;;; ------------------------------------------------------------
;; A bacia HERDA a porta de armazenamento da classe base (objetos.lsp), como a sarjeta:
;;   ler      OBJ:RegistroDe (BAC:Ler abaixo)   gravar   OBJ:GravaRegistro "bacia"
;;   listar   OBJ:ListaTipo "bacia"             indice   HYDRO.OBJETOS (unico)
;;   remover  OBJ:Remover (emite "objeto.removido"; limpeza propria em BAC:_AoRemover)
;;   cadastro  generico (OBJ:CadastroInterativoTipo / OBJ:CadastrarCom): ATRIB, vinculo do
;;             TALVEGUE (PARAMS-DEFS) e CARACT; nunca calcula (o tc nasce em BAC:Preparar)
;;   editar    BACIACAD (tudo) ou BACIAEDITA (um campo), os fluxos genericos OPV:*
;; Sem ARMAZENAMENTO proprio: nada a declarar na secao 8.

;; Registro padrao se a entidade e uma bacia, senao nil (leitura tipada)
(defun BAC:Ler (en)
  (OBJ:RegistroDe en "bacia")
)

;; Gancho "AO-REMOVER" do tipo (chamado por OBJ:Remover, com o registro ainda
;; gravado): limpa as marcas de XData da bacia e do talvegue, se o plugin existir.
(defun BAC:_AoRemover (en / talv h)
  (if (HYDRO:Has "xdata")
    (progn
      (setq h (BAC:Talvegue (BAC:Ler en)))
      (setq talv (if h (handent h) nil))
      (vl-catch-all-apply 'XD:RemoveApp (list en "DREN-BACIA"))
      (if talv (vl-catch-all-apply 'XD:RemoveApp (list talv "DREN-BACIA")))
    )
  )
  t
)


;;; ------------------------------------------------------------
;;; 4. CAMPOS (CARACT, PARAMS e ATRIB)
;;; ------------------------------------------------------------
;; Acessos ao registro (secao 18 de docs/arquitetura.md)
(defun BAC:Nome (dados)       (HYDRO:Val "NOME" dados))

(defun BAC:Descricao (dados)  (HYDRO:Val "DESCRICAO" dados))

(defun BAC:Params (dados)     (HYDRO:Val "PARAMS" dados))

(defun BAC:Talvegue (dados)   (HYDRO:Val "TALVEGUE" (BAC:Params dados)))

(defun BAC:Atrib (dados)      (HYDRO:Val "ATRIB" dados))

(defun BAC:Caract (dados)     (HYDRO:Val "CARACT" dados))

;; ids dos metodos de tc cadastrados (opcoes dinamicas de TC-METODO); sem o plugin, kirpich
(defun BAC:_IdsTc (/ ids)
  (setq ids (mapcar 'car (HYDRO:RegList "metodo-tc")))
  (if ids ids (list "kirpich"))
)

;; ids dos tipos de hidrograma cadastrados (opcoes dinamicas de HIDROGRAMA-TIPO)
(defun BAC:_IdsHid (/ ids)
  (setq ids (mapcar 'car (HYDRO:RegList "hidrograma-tipo")))
  (if ids ids (list "triangular-scs"))
)

;; ATRIB (o usuario define): (chave rotulo padrao unidade [tipo [opcoes]]). C e CN valem
;; como padrao dos metodos; o tc e escolhido AQUI (metodo ou valor) e calculado so no calculo.
(defun BAC:_AtribDefs ()
  (list
    (list "C" "Coeficiente de escoamento C" 0.6 "")
    (list "CN" "Numero da curva CN (1 a 100)" 75.0 "")
    (list "TC-METODO" "Metodo do tempo de concentracao" "kirpich" "" "opcoes" 'BAC:_IdsTc)
    (list "TC-USUARIO" "tc informado (0 = calcular pelo metodo)" 0.0 "min")
    (list "HIDROGRAMA-TIPO" "Tipo de hidrograma" "triangular-scs" "" "opcoes" 'BAC:_IdsHid)
  )
)

;; PARAMS-DEFS: entidades de apoio pedidas no cadastro (chave rotulo aceita [obrigatorio])
(defun BAC:_VinculosDefs ()
  (list
    (list "TALVEGUE" "a polilinha do TALVEGUE (Enter = pular)"
          '("LWPOLYLINE" "POLYLINE" "SPLINE"))
  )
)

;; CARACT-DEFS: o que se digita quando o desenho nao informa
(defun BAC:_CaractDefs ()
  (list
    (list "AREA" "Area da bacia" 0.0 "m2")
    (list "COMP" "Comprimento do talvegue" 0.0 "m")
    (list "DECL" "Declividade do talvegue" 0.0 "m/m")
  )
)

;; PADROES: C e CN iniciais = padrao do projeto (comando PADROES), se definido
(defun BAC:_Padroes (en / c cn)
  (setq c (HYDRO:Padrao "HYDRO.MET.racional." "C"))
  (setq cn (HYDRO:Padrao "HYDRO.MET.scs-cn." "CN"))
  (OBJ:Limpa (list (cons "C" c) (cons "CN" cn)))
)

;; CARACT para calculo: o gravado, com DESNIVEL = DECL * COMP se so esses foram digitados
(defun BAC:_CaractCalc (dados / c)
  (setq c (BAC:Caract dados))
  (if (and (not (assoc "DESNIVEL" c)) (assoc "DECL" c) (assoc "COMP" c))
    (append c
      (list (cons "DESNIVEL" (* (cdr (assoc "DECL" c)) (cdr (assoc "COMP" c))))))
    c
  )
)

;; Atributos da bacia que coincidem com parametros do metodo viram padrao
;; (ex.: atributo CN preenche o parametro CN do SCS)
(defun BAC:_Sobrescritas (atrib defs / out d)
  (foreach d defs
    (if (assoc (car d) atrib)
      (setq out (append out (list (assoc (car d) atrib))))
    )
  )
  out
)

;; Contexto de calculo da bacia (NAO e o que fica gravado): caracteristicas,
;; "TC", "TC-ORIGEM" e "TC-PARAMS" (de `tc`, resultado de BAC:TcDe), "NOME" e os atributos
(defun BAC:_Ctx (dados tc)
  (append
    (BAC:_CaractCalc dados)
    (OBJ:Limpa
      (list (cons "NOME" (BAC:Nome dados))
            (cons "TC" (HYDRO:Val "MIN" tc))
            (cons "TC-ORIGEM" (HYDRO:Val "ORIGEM" tc))
            (cons "TC-PARAMS" (HYDRO:Val "PARAMS" tc))))
    (BAC:Atrib dados)
  )
)


;;; ------------------------------------------------------------
;;; 5. RESULTADOS (RESULT)
;;; ------------------------------------------------------------
(defun BAC:Result (dados)     (HYDRO:Val "RESULT" dados))

;; tc de UM cenario no formato plano (("MIN" . min) ("ORIGEM" . id | "usuario") ("PARAMS" . alist)),
;; lido do grupo TC do cenario; nil se nao ha
(defun BAC:TcDeCenario (dados cenario / g)
  (setq g (HYDRO:Val "TC" (cdr (assoc cenario (BAC:Result dados)))))
  (if g
    (OBJ:Limpa
      (list (cons "MIN" (HYDRO:Val "VALOR" g))
            (cons "ORIGEM" (HYDRO:Val "METODO" g))
            (cons "PARAMS" (HYDRO:Val "INPUT" g))))
    nil
  )
)

;; tc para exibir: o do cenario em uso; se ele nao tem tc, o do ultimo cenario que tenha
(defun BAC:Tc (dados / atual c r)
  (setq atual (OBJ:CenarioAtual))
  (setq r (if atual (BAC:TcDeCenario dados atual) nil))
  (if (null r)
    (foreach c (BAC:Result dados)
      (if (HYDRO:Val "TC" (cdr c)) (setq r (BAC:TcDeCenario dados (car c))))
    )
  )
  r
)

;; Mapa campo plano da vazao -> campo do grupo VAZAO (QP e o numero principal: VALOR)
(defun BAC:_MapaVazao ()
  '(
    ("QP" . "VALOR") ("TC" . "TC")
    ("METODO" . "METODO") ("DUR" . "DUR")
    ("VOLUME" . "VOLUME") ("QP-PROPRIO" . "QP-PROPRIO")
    ("AREA-TOTAL" . "AREA-TOTAL") ("TC-PROPRIO" . "TC-PROPRIO")
    ("QP-CALC" . "VALOR-CALC") ("PRESERVADA" . "PRESERVADA")
    ("PARAMS" . "INPUT")
    )
)

;; (puro) Grupos PRECIPITACAO e VAZAO a partir da vazao plana `vaz` (formato do calculo
;; e dos textos: METODO TR DUR TC PARAMS I P PE QP VOLUME ...). TR e CENARIO nao entram:
;; vao no grupo CENARIO. Campos desconhecidos ficam em VAZAO.
(defun BAC:_Grupos (vaz / mapa v p x)
  (setq mapa (BAC:_MapaVazao))
  (foreach x vaz
    (cond
      ((member (car x) '("TR" "CENARIO")) nil)
      ((member (car x) '("I" "P" "PE")) (setq p (append p (list x))))
      ((assoc (car x) mapa)
        (setq v (append v (list (cons (cdr (assoc (car x) mapa)) (cdr x)))))
      )
      (t (setq v (append v (list x))))
    )
  )
  (if p
    (setq p
      (append
        (list (cons "VALOR" (if (assoc "P" p) (cdr (assoc "P" p)) (cdr (assoc "I" p))))
              (cons "UNIDADE" (if (assoc "P" p) "mm" "mm/h")))
        p)))
  (list (cons "PRECIPITACAO" p) (cons "VAZAO" v))
)

;; (puro) Vazao plana de um cenario (inverso de BAC:_Grupos), ou nil se nao tem VAZAO.
;; Traz "CENARIO" e "TR" (do grupo CENARIO).
(defun BAC:_CalcFlat (cenario cen / v p c mapa)
  (setq v (HYDRO:Val "VAZAO" cen))
  (setq p (HYDRO:Val "PRECIPITACAO" cen))
  (setq c (HYDRO:Val "CENARIO" cen))
  (setq mapa (BAC:_MapaVazao))
  (if (and v (HYDRO:Val "VALOR" v))
    (OBJ:Limpa
      (append
        (list (cons "CENARIO" cenario) (cons "TR" (HYDRO:Val "TR" c)))
        (mapcar
          (function (lambda (m) (cons (car m) (HYDRO:Val (cdr m) v))))
          mapa)
        (list (cons "I" (HYDRO:Val "I" p)) (cons "P" (HYDRO:Val "P" p))
              (cons "PE" (HYDRO:Val "PE" p)))
        (vl-remove-if
          (function (lambda (x) (member (car x) (mapcar 'cdr mapa))))
          v)))
    nil
  )
)

;; Vazao plana de um cenario do registro `dados`, ou nil
(defun BAC:CalcDe (dados cenario)
  (BAC:_CalcFlat cenario (cdr (assoc cenario (BAC:Result dados))))
)

;; vazoes (formato plano) de todos os cenarios que tem VAZAO, na ordem do registro
(defun BAC:Vazao (dados / out c x)
  (foreach c (BAC:Result dados)
    (setq x (BAC:_CalcFlat (car c) (cdr c)))
    (if x (setq out (append out (list x))))
  )
  out
)

;; (puro) Hidrograma PLANO de um cenario (formato dos textos e do visualizador: TIPO METODO TR
;; DUR PARAMS QP TP TB VOLUME NOTA PONTOS + CENARIO), do grupo HIDROGRAMA; nil se nao tem.
;; METODO e TR vem dos grupos VAZAO e CENARIO (nao sao copiados).
(defun BAC:_HidFlat (cenario cen / h v c)
  (setq h (HYDRO:Val "HIDROGRAMA" cen))
  (setq v (HYDRO:Val "VAZAO" cen))
  (setq c (HYDRO:Val "CENARIO" cen))
  (if (and h (HYDRO:Val "PONTOS" h))
    (OBJ:Limpa
      (list
        (cons "CENARIO" cenario)
        (cons "TIPO" (HYDRO:Val "TIPO" h))
        (cons "METODO" (HYDRO:Val "METODO" v))
        (cons "TR" (HYDRO:Val "TR" c))
        (cons "DUR" (HYDRO:Val "DUR" h))
        (cons "PARAMS" (HYDRO:Val "INPUT" h))
        (cons "QP" (HYDRO:Val "VALOR" h))
        (cons "TP" (HYDRO:Val "TP" h))
        (cons "TB" (HYDRO:Val "TB" h))
        (cons "VOLUME" (HYDRO:Val "VOLUME" h))
        (cons "NOTA" (HYDRO:Val "NOTA" h))
        (cons "PONTOS" (HYDRO:Val "PONTOS" h))))
    nil
  )
)

;; hidrogramas (formato plano) de todos os cenarios que tem, na ordem do registro
(defun BAC:Hidrogramas (dados / out c x)
  (foreach c (BAC:Result dados)
    (setq x (BAC:_HidFlat (car c) (cdr c)))
    (if x (setq out (append out (list x))))
  )
  out
)

;; maior vazao de pico entre as vazoes calculadas (0.0 se nao ha)
(defun BAC:MaxQp (dados / q c)
  (setq q 0.0)
  (foreach c (BAC:Vazao dados)
    (if (and (HYDRO:Val "QP" c) (> (HYDRO:Val "QP" c) q))
      (setq q (HYDRO:Val "QP" c))
    )
  )
  q
)

;; Contexto de uma vazao para quem for gerar hidrogramas: TR, DUR, METODO e
;; o TC usado no calculo vem PRIMEIRO (assoc acha o primeiro), depois as
;; caracteristicas da bacia e os campos calculados (QP, PE, VOLUME...).
(defun BAC:Contexto (dados vaz)
  (append
    (OBJ:Limpa
      (list (cons "TR" (HYDRO:Val "TR" vaz))
            (cons "DUR" (HYDRO:Val "DUR" vaz))
            (cons "METODO" (HYDRO:Val "METODO" vaz))
            (cons "TC" (HYDRO:Val "TC" vaz))))
    (BAC:Caract dados)
    (BAC:_SemChaves vaz '("METODO" "TR" "DUR" "TC" "PARAMS"))
  )
)


;;; ------------------------------------------------------------
;;; 6. CALCULOS
;;; ------------------------------------------------------------
;; Kirpich / California Culverts: tc = 57 * (L^3 / H)^0.385
;; (L em km, H em m, tc em min). comp em m, decl em m/m
;; Usado apenas quando o plugin de metodos nao esta carregado.
(defun BAC:TcKirpich (comp decl)
  (if (and comp decl (> comp 0.0) (> decl 0.0))
    (* 57.0
       (expt (/ (expt (/ comp 1000.0) 3.0) (* decl comp)) 0.385))
    nil
  )
)

;; tc por um metodo do catalogo "metodo-tc". Sem o plugin tempo_conc, so
;; "kirpich". Retorna (("TC" . min)) ou (("ERRO" . msg)).
(defun BAC:CalcularTc (id caract params / r)
  (cond
    ((HYDRO:Has "tempo-conc")
      (TCM:Calcular id caract params)
    )
    ((equal id "kirpich")
      (setq r (BAC:TcKirpich (HYDRO:Val "COMP" caract) (HYDRO:Val "DECL" caract)))
      (if r (list (cons "TC" r)) (BAC:_Erro "Declividade nula."))
    )
    (t
      (BAC:_Erro "Plugin tempo_conc nao carregado: so o metodo kirpich esta disponivel.")
    )
  )
)

;; Verifica se método está cadastrado ou é default (kirpich)
(defun BAC:_MetodoTcOk (id)
  (if (or (HYDRO:RegGet "metodo-tc" id) (equal id "kirpich")) t nil)
)

;; ultimos parametros usados (ou padroes) de um metodo de tc
(defun BAC:_ParamsTc (id / m out d v)
  (setq m (HYDRO:RegGet "metodo-tc" id))
  (foreach d (cdr (assoc "PARAMS" m))
    (setq v (HYDRO:Get (strcat "HYDRO.TC." id "." (car d)) nil))
    (setq out (append out (list (cons (car d) (if v v (nth 2 d))))))
  )
  out
)

;; tc da bacia a partir do que esta gravado (puro; nao grava).
;;   dados   : registro da bacia
;;   retorno: (("MIN" . min) ("ORIGEM" . id | "usuario") ("PARAMS" . alist)) ou (("ERRO" . msg))
;; ATRIB TC-USUARIO > 0 vale como esta; senao o metodo de TC-METODO (kirpich se ausente),
;; com os parametros do projeto / ultimo usado (BAC:_ParamsTc) e o tc minimo do projeto.
(defun BAC:TcDe (dados / atrib usr id params r)
  (setq atrib (BAC:Atrib dados))
  (setq usr (HYDRO:Val "TC-USUARIO" atrib))
  (if (and usr (> usr 0.0))
    (list (cons "MIN" usr) (cons "ORIGEM" "usuario"))
    (progn
      (setq id (HYDRO:Val "TC-METODO" atrib))
      (if (not (and id (BAC:_MetodoTcOk id))) (setq id "kirpich"))
      (setq params (BAC:_ParamsTc id))
      (setq r (BAC:CalcularTc id (BAC:_CaractCalc dados) params))
      (if (assoc "ERRO" r)
        r
        (list (cons "MIN" (max (HYDRO:Val "TC" r) (HYDRO:Get "HYDRO.TC.MINIMO" 10.0)))
              (cons "ORIGEM" id)
              (cons "PARAMS" params))
      )
    )
  )
)

;; Prepara a bacia para calcular: rele o desenho (OBJ:AtualizaCaract, flag
;; HYDRO.CARACT.AUTO) e calcula o tc (BAC:TcDe). NAO grava: o grupo TC do cenario vai
;; junto com o calculo (BAC:_CalcularEGravar).
;;   retorno: contexto de calculo (BAC:_Ctx) ou (("ERRO" . msg))
;; E o unico lugar onde o tc nasce; cadastrar e editar nao calculam.
(defun BAC:Preparar (contorno / dados tc)
  (setq dados (BAC:Ler contorno))
  (cond
    ((not dados) (BAC:_Erro "Bacia nao cadastrada. Use BACIACAD."))
    (t
      (OBJ:AtualizaCaract contorno)
      (setq dados (BAC:Ler contorno))
      (setq tc (BAC:TcDe dados))
      (if (assoc "ERRO" tc) tc (BAC:_Ctx dados tc))
    )
  )
)

;; Executa um metodo do catalogo (puro). Retorna o resultado do metodo ou
;; (("ERRO" . msg)).
(defun BAC:ExecutarMetodo (id ctx params / m falta r)
  (setq m (HYDRO:RegGet "metodo-chuva-vazao" id))
  (cond
    ((not m)
      (BAC:_Erro (strcat "Metodo nao cadastrado: " id))
    )
    (t
      (foreach r (cdr (assoc "REQUER" m))
        (if (and (not falta) (not (HYDRO:Has r)))
          (setq falta r)
        )
      )
      (if falta
        (BAC:_Erro (strcat "Plugin requerido nao carregado: " falta))
        (apply (cdr (assoc "FN" m)) (list ctx params))
      )
    )
  )
)

;; Executa o metodo, grava o CENARIO (grupos TC, PRECIPITACAO, ENTRADA, VAZAO; uma
;; gravacao) e emite o evento. `perg` = (TR ID DUR PARAMS CENARIO).
;; Retorna a vazao PLANA do calculo (para texto) ou (("ERRO" . msg)).
(defun BAC:_CalcularEGravar (contorno talv cad perg /
                             ctx res vaz id tr dur ent m tcprop tcout comp pr cenario
                             grupos g)
  (setq id  (HYDRO:Val "ID" perg))
  (setq tr  (HYDRO:Val "TR" perg))
  (setq dur (HYDRO:Val "DUR" perg))
  (setq cenario (HYDRO:Val "CENARIO" perg))
  (setq ent (BAC:_Entrada contorno cenario))
  (cond
    ;; ha montantes mas falta o calculo de algum deles
    ((and ent (or (HYDRO:Val "FALTAM" ent) (null (HYDRO:Val "QP" ent))))
      (BAC:_Erro
        (strcat "Montantes sem calculo no cenario " cenario ": "
                (HYDRO:Join (HYDRO:Val "FALTAM" ent) ", ")
                ". Calcule-os antes, de montante para jusante."))
    )
    (t
      ;; tempo de saida: com montantes, o maior (paralelo ou serie, ver ligacao.lsp)
      (setq tcprop (HYDRO:Val "TC" cad))
      (if ent
        (progn
          (setq tcout (LIG:TcPuro "concentracao" tcprop (HYDRO:Val "CHEGADAS" ent)))
          (setq m (HYDRO:RegGet "metodo-chuva-vazao" id))
          (setq cad (cons (cons "TC" tcout) cad))
          (if (not (and m (cdr (assoc "USA-DUR" m))))
            (setq dur tcout)
          )
        )
      )
      (setq ctx (append (list (cons "TR" tr) (cons "DUR" dur)) cad))
      (setq res (BAC:ExecutarMetodo id ctx (HYDRO:Val "PARAMS" perg)))
      (cond
        ((assoc "ERRO" res) res)
        (t
          (if ent
            (progn
              ;; montantes reavaliados no mesmo tempo maximo; soma com a propria
              (setq comp (LIG:VazaoMontante contorno cenario tcout))
              (setq res (BAC:_Compoe res comp (HYDRO:Val "AREA" cad) tcprop))
              ;; flag geral: nao deixar o tempo maior reduzir abaixo da entrada
              (setq pr
                (LIG:Preserva (HYDRO:Val "QP" ent) (HYDRO:Val "QP" res) (LIG:PreservaAtiva)))
              (if (cadr pr)
                (setq res
                  (OBJ:SetChave
                    (OBJ:SetChave
                      (OBJ:SetChave res "QP-CALC" (HYDRO:Val "QP" res))
                      "QP" (car pr))
                    "PRESERVADA" t))
              )
            )
          )
          ;; vazao PLANA do calculo (formato dos textos); o que vai gravado sao os GRUPOS
          (setq vaz
            (OBJ:Limpa
              (append
                (list
                  (cons "CENARIO" cenario)
                  (cons "METODO" id)
                  (cons "TR" tr)
                  (cons "DUR" (if (HYDRO:Val "DUR" res) (HYDRO:Val "DUR" res) dur))
                  (cons "TC" (HYDRO:Val "TC" cad))
                  (cons "PARAMS" (HYDRO:Val "PARAMS" perg))
                )
                (BAC:_SemChaves res '("METODO" "TR" "DUR" "TC" "PARAMS"))
              )
            )
          )
          (setq grupos
            (append
              (list
                (cons "TC"
                  (list (cons "VALOR" tcprop)
                        (cons "METODO" (HYDRO:Val "TC-ORIGEM" cad))
                        (cons "INPUT" (HYDRO:Val "TC-PARAMS" cad)))))
              (if ent
                (list
                  (cons "ENTRADA"
                    (list (cons "VALOR" (HYDRO:Val "QP" ent))
                          (cons "TC" (HYDRO:Val "TC" ent))
                          (cons "AREA" (HYDRO:Val "AREA" ent)))))
              )
              (BAC:_Grupos vaz)
              ;; vazao recalculada: o hidrograma antigo deste cenario nao vale mais
              (list (cons "HIDROGRAMA" nil))))
          ;; uma gravacao so: cenario com TR, sem OBSOLETO, todos os grupos
          (OBJ:GravarCalculo contorno cenario tr grupos)
          (HYDRO:Emit "bacia.calculada"
            (OBJ:Limpa
              (list
                (cons "BACIA" contorno)
                (cons "TALVEGUE" talv)
                (cons "CENARIO" cenario)
                (cons "NOME" (HYDRO:Val "NOME" cad))
                (cons "AREA" (HYDRO:Val "AREA" cad))
                (cons "COMP" (HYDRO:Val "COMP" cad))
                (cons "DECL" (HYDRO:Val "DECL" cad))
                (cons "TC" (HYDRO:Val "TC" cad))
                (cons "METODO" id)
                (cons "TR" tr)
                (cons "DUR" (HYDRO:Val "DUR" vaz))
                (cons "QP" (HYDRO:Val "QP" res))
                (cons "PE" (HYDRO:Val "PE" res))
                (cons "VOLUME" (HYDRO:Val "VOLUME" res))
              )
            )
          )
          vaz
        )
      )
    )
  )
)

;; ENTRADA da bacia (LIG:Entrada) se ela tem montante e o plugin ligacao esta carregado
(defun BAC:_Entrada (contorno cenario)
  (if (and (HYDRO:Has "ligacao") (LIG:Afluentes contorno))
    (LIG:Entrada contorno cenario)
    nil
  )
)

;; Montantes da bacia compostos para METODO e TR (LIG:VazaoMontante), ou nil
;; se a bacia nao tem montante ou o plugin ligacao nao esta carregado
;; Soma o que vem dos montantes ao resultado proprio do metodo (puro).
;;   res = resultado do metodo da propria bacia (ja no tc acumulado)
;;   mont = LIG:VazaoMontante (QP, VOLUME, opcional AREA)   area = area propria (m2)
;;   tcprop = tc proprio (min)
;; QP e VOLUME passam a ser os TOTAIS no exutorio; o proprio fica em QP-PROPRIO.
;; Sem VOLUME nos dois lados o volume e descartado (nao seria o total).
(defun BAC:_Compoe (res mont area tcprop / r qm)
  (setq qm (if (HYDRO:Val "QP" mont) (HYDRO:Val "QP" mont) 0.0))
  (setq r (OBJ:SetChave res "QP-PROPRIO" (HYDRO:Val "QP" res)))
  (setq r (OBJ:SetChave r "QP" (+ (HYDRO:Val "QP" res) qm)))
  (setq r
    (OBJ:SetChave r "VOLUME"
      (if (and (HYDRO:Val "VOLUME" res) (HYDRO:Val "VOLUME" mont))
        (+ (HYDRO:Val "VOLUME" res) (HYDRO:Val "VOLUME" mont))
        nil)))
  (setq r
    (OBJ:SetChave r "AREA-TOTAL"
      (+ (if area area 0.0) (if (HYDRO:Val "AREA" mont) (HYDRO:Val "AREA" mont) 0.0))))
  (OBJ:SetChave r "TC-PROPRIO" tcprop)
)


;;; ------------------------------------------------------------
;;; 7. RESUMO E FORMATACAO (linhas de texto; quem desenha e a view)
;;; ------------------------------------------------------------
;; Texto curto de uma vazao para menus
(defun BAC:RotuloVazao (vaz / qp)
  (setq qp (HYDRO:Val "QP" vaz))
  (strcat (if (HYDRO:Val "CENARIO" vaz) (strcat (HYDRO:Val "CENARIO" vaz) "  |  ") "")
          (BAC:NomeMetodo (HYDRO:Val "METODO" vaz))
          "  |  TR " (HYDRO:FmtReal (HYDRO:Val "TR" vaz)) " anos"
          "  |  dur. " (HYDRO:FmtReal (HYDRO:Val "DUR" vaz)) " min"
          (if qp (strcat "  |  Qp " (rtos qp 2 3) " m3/s") ""))
)

;; Valor de um atributo (C, CN) para texto: o da bacia; senao o padrao do projeto
;; (PADROES) ou o ultimo usado, com a origem entre parenteses; senao "nao definido".
(defun BAC:_FmtAtrib (chave atrib prefixo / v p u)
  (setq v (HYDRO:Val chave atrib))
  (setq p (HYDRO:Padrao prefixo chave))
  (setq u (HYDRO:Get (strcat prefixo chave) nil))
  (cond
    (v (BAC:_FmtP v))
    (p (strcat (BAC:_FmtP p) " (padrao do projeto)"))
    (u (strcat (BAC:_FmtP u) " (ultimo usado)"))
    (t "nao definido")
  )
)

;; valor de parametro para texto (numero ou texto)
(defun BAC:_FmtP (v)
  (if (numberp v) (HYDRO:FmtReal v) (vl-princ-to-string v))
)

;; Linhas de identificacao e caracteristicas
(defun BAC:LinhasCadastro (dados h / c atrib tc)
  (setq c (BAC:Caract dados))
  (setq tc (BAC:Tc dados))
  (setq atrib (BAC:Atrib dados))
  (append
    (list (strcat "BACIA " (BAC:NomeExib dados h)))
    (if (HYDRO:Val "AREA" c)
      (list (strcat "Area: " (rtos (/ (HYDRO:Val "AREA" c) 10000.0) 2 3) " ha"))
    )
    (if (and (HYDRO:Val "COMP" c) (HYDRO:Val "DECL" c))
      (list (strcat "L = " (rtos (HYDRO:Val "COMP" c) 2 1) " m   S = "
                    (rtos (HYDRO:Val "DECL" c) 2 4) " m/m"))
    )
    (if (HYDRO:Val "MIN" tc)
      (list (strcat "tc = " (rtos (HYDRO:Val "MIN" tc) 2 2) " min ("
                    (BAC:NomeTc (HYDRO:Val "ORIGEM" tc)) ")"))
    )
    ;; sempre mostra C e CN com o valor que vale (da bacia, ou do projeto/ultimo usado)
    (list
      (strcat "Atributos: C = " (BAC:_FmtAtrib "C" atrib "HYDRO.MET.racional.")
              "   CN = " (BAC:_FmtAtrib "CN" atrib "HYDRO.MET.scs-cn.")
              (HYDRO:Join
                (cons ""
                  (mapcar
                    (function (lambda (p) (strcat (car p) " = " (BAC:_FmtP (cdr p)))))
                    (vl-remove-if
                      (function (lambda (p) (member (car p) '("C" "CN"))))
                      atrib)))
                "   ")))
  )
)

;; Linhas de uma vazao calculada
(defun BAC:LinhasVazao (vaz)
  (append
    (list (strcat "[" (BAC:NomeMetodo (HYDRO:Val "METODO" vaz))
                  " - TR " (HYDRO:FmtReal (HYDRO:Val "TR" vaz)) " anos"
                  (if (and (HYDRO:Val "CENARIO" vaz)
                           (not (equal (HYDRO:Val "CENARIO" vaz)
                                       (OBJ:CenarioPadrao (HYDRO:Val "TR" vaz)))))
                    (strcat " - cenario " (HYDRO:Val "CENARIO" vaz))
                    "")
                  "]"))
    (if (HYDRO:Val "PARAMS" vaz)
      (list
        (strcat "Parametros: "
          (HYDRO:Join
            (mapcar
              (function (lambda (p) (strcat (car p) " = " (BAC:_FmtP (cdr p)))))
              (HYDRO:Val "PARAMS" vaz))
            "   ")))
    )
    (if (HYDRO:Val "I" vaz)
      (list (strcat "i = " (rtos (HYDRO:Val "I" vaz) 2 2) " mm/h"
                    (if (HYDRO:Val "P" vaz)
                      (strcat "   P = " (rtos (HYDRO:Val "P" vaz) 2 2) " mm") "")))
    )
    (if (HYDRO:Val "PE" vaz)
      (list (strcat "Pe = " (rtos (HYDRO:Val "PE" vaz) 2 2) " mm"))
    )
    (if (HYDRO:Val "QP" vaz)
      (list (strcat "Qp = " (rtos (HYDRO:Val "QP" vaz) 2 3) " m3/s"))
    )
    (if (HYDRO:Val "QP-PROPRIO" vaz)
      (list (strcat "  composta: propria " (rtos (HYDRO:Val "QP-PROPRIO" vaz) 2 3)
                    " + montantes " (rtos (- (HYDRO:Val "QP" vaz) (HYDRO:Val "QP-PROPRIO" vaz)) 2 3)
                    " m3/s   tc de saida = " (rtos (HYDRO:Val "TC" vaz) 2 1) " min"
                    (if (HYDRO:Val "AREA-TOTAL" vaz)
                      (strcat "   A total = " (rtos (/ (HYDRO:Val "AREA-TOTAL" vaz) 10000.0) 2 3) " ha")
                      "")))
    )
    (if (HYDRO:Val "PRESERVADA" vaz)
      (list (strcat "  vazao de entrada preservada (calculada no tc maximo: "
                    (rtos (HYDRO:Val "QP-CALC" vaz) 2 3) " m3/s)"))
    )
    (if (HYDRO:Val "VOLUME" vaz)
      (list (strcat "Volume = " (rtos (HYDRO:Val "VOLUME" vaz) 2 0) " m3"))
    )
  )
)


;; Linhas de texto da bacia com os calculos dados (cadastro + vazoes)
(defun BAC:LinhasTexto (dados h calcs / out c)
  (setq out (BAC:LinhasCadastro dados h))
  (foreach c calcs
    (setq out (append out (BAC:LinhasVazao c)))
  )
  out
)

;; toString da bacia: texto multilinha (linhas separadas por newline) com
;; cadastro, vazoes e quantidade de hidrogramas. Usado por alert e listagens.
(defun BAC:ToString (en)
  (HYDRO:Join (BAC:_ObjResumo en) "\n")
)

;;; ------------------------------------------------------------
;;; 8. TIPO NO CATALOGO (rotulos, eventos e declaracao)
;;; ------------------------------------------------------------
(HYDRO:SetLabel "HYDRO.BACIA.METODO" "Ultimo metodo chuva-vazao usado" "")
(HYDRO:SetLabel "xdata:DREN-BACIA:1005" "Talvegue relacionado" "")
(HYDRO:SetLabel "xdata:DREN-BACIA:1040" "Vazao de pico Qp" "m3/s")

(defun BAC:_ObjNome (en)
  (BAC:NomeExib (BAC:Ler en) (HYDRO:Handle en))
)

(defun BAC:_ObjResumo (en / dados linhas c)
  (setq dados (BAC:Ler en))
  (setq linhas (BAC:LinhasCadastro dados (HYDRO:Handle en)))
  (setq linhas (append linhas (list "" (strcat "Vazoes: " (itoa (length (BAC:Vazao dados)))))))
  (foreach c (BAC:Vazao dados)
    (setq linhas (append linhas (list (strcat "  " (BAC:RotuloVazao c)))))
  )
  (append linhas
    (list "" (strcat "Hidrogramas: " (itoa (length (BAC:Hidrogramas dados))))))
)

;; resultado do metodo desta bacia, reavaliado no tc dado (capacidade "VAZAO-EM",
;; (fn en cenario tc)): usa o metodo e o INPUT do calculo gravado no cenario; nil se nao ha
(defun BAC:_ObjVazaoEm (en cenario tc / dados vaz m ctx res)
  (setq dados (BAC:Ler en))
  (setq vaz (BAC:CalcDe dados cenario))
  (setq m (if vaz (HYDRO:RegGet "metodo-chuva-vazao" (HYDRO:Val "METODO" vaz)) nil))
  (if (and vaz m)
    (progn
      ;; reavalia SO esta bacia no tc dado, com o metodo e o INPUT do calculo dela
      (setq ctx
        (append
          (list (cons "TC" tc)
                (cons "TR" (HYDRO:Val "TR" vaz))
                (cons "DUR" (if (cdr (assoc "USA-DUR" m)) (HYDRO:Val "DUR" vaz) tc)))
          (BAC:_CaractCalc dados)))
      (setq res (BAC:ExecutarMetodo (HYDRO:Val "METODO" vaz) ctx (HYDRO:Val "PARAMS" vaz)))
      (if (assoc "ERRO" res) nil res)
    )
    nil
  )
)

(defun BAC:_ObjArea (en)
  (HYDRO:Val "AREA" (BAC:Caract (BAC:Ler en)))
)

;; destino padrao da bacia: o proprio talvegue
(defun BAC:_ObjTalvegue (en / h)
  (setq h (BAC:Talvegue (BAC:Ler en)))
  (if h (handent h) nil)
)

;; regra da bacia sobre si mesma: so bacias descarregam em bacias
(defun BAC:_ObjRegra (tipo-origem tipo-destino)
  (if (and (equal tipo-destino "bacia") (not (equal tipo-origem "bacia")))
    "Somente bacias descarregam em bacias."
    nil
  )
)

(if (HYDRO:Has "objetos")
  (OBJ:RegistrarTipo
    "bacia"
    "Bacia"
    "Bacia hidrografica (contorno + talvegue opcional). Cadastre com BACIACAD."
    '("LWPOLYLINE" "POLYLINE" "SPLINE");aceita
    (BAC:_AtribDefs);params (ATRIB)
    t;recebe
    t;emite
    (list
      (cons "CARACTERIZA" 'BAC:Caracterizar)
      (cons "PARAMS-DEFS" (BAC:_VinculosDefs))
      (cons "CARACT-DEFS" (BAC:_CaractDefs))
      (cons "PADROES" 'BAC:_Padroes)
      (cons "AO-REMOVER" 'BAC:_AoRemover)
      (cons "NOME-FN" 'BAC:_ObjNome)
      (cons "RESUMO" 'BAC:_ObjResumo)
      (cons "TOSTRING" 'BAC:ToString)
      (cons "VAZAO-EM" 'BAC:_ObjVazaoEm)
      (cons "RECALCULA" 'BAC:_ObjRecalcula)
      (cons "TEMPO-MODO" "concentracao")
      (cons "AREA-PROPRIA" 'BAC:_ObjArea)
      (cons "DESTINO-PADRAO" 'BAC:_ObjTalvegue)
      (cons "REGRA" 'BAC:_ObjRegra)
    );extras
  )
)

;;; ------------------------------------------------------------
;;; 9. COMANDOS E INTERACAO (linha de comando)
;;; ------------------------------------------------------------
;; Comandos c: de linha de comando e as perguntas que eles fazem. Ficam aqui
;; para o objeto funcionar carregando so este arquivo. Texto inserido no
;; desenho fica em views/bacia_view.lsp e o dialogo em views/bacia_tabela.lsp.
;;
;; COMANDOS
;;   BACIACAD   cadastra/atualiza a bacia (fluxo generico; nao calcula nada)
;;   BACIAEDITA altera UM campo (ATRIB, talvegue ou CARACT manual)
;;   BACIA      calcula a vazao por um metodo cadastrado
;;   BACIAS     lista as bacias do desenho (a tabela esta em BACIATABELA)
;;   BACIAINFO  mostra a bacia (BAC:ToString)

;; Pede uma polilinha (contorno ou talvegue). Retorna o ename ou nil.
(defun BAC:SelLinha (msg / ss)
  (princ msg)
  (if (setq ss (ssget "_:S" '((0 . "LWPOLYLINE,POLYLINE,SPLINE"))))
    (ssname ss 0)
    nil
  )
)

(defun BAC:_IdxMetodoPadrao (lista / ult i pos m)
  (setq ult (HYDRO:Get "HYDRO.BACIA.METODO" nil))
  (setq i 0 pos 0)
  (foreach m lista
    (if (equal (car m) ult) (setq pos i))
    (setq i (1+ i))
  )
  pos
)

;; Menu dos metodos chuva-vazao cadastrados. Retorna o id ou nil.
(defun BAC:_EscolheMetodo (/ lista itens idx)
  (setq lista (HYDRO:RegList "metodo-chuva-vazao"))
  (if lista
    (progn
      (setq itens
        (mapcar
          (function
            (lambda (m)
              (strcat (cdr (assoc "NOME" (cdr m))) "  -  "
                      (cdr (assoc "DESC" (cdr m))))
            )
          )
          lista
        )
      )
      (setq idx
        (HYDRO:Escolher "Metodos chuva-vazao cadastrados:" itens
                        (BAC:_IdxMetodoPadrao lista))
      )
      (car (nth idx lista))
    )
    nil
  )
)

;; Pergunta TR, metodo, duracao e parametros. Retorna alist
;; (TR ID DUR PARAMS CENARIO) ou nil. O cenario e o TR (+ o nome dado em CENARIO).
(defun BAC:_PerguntasCalculo (cad / tr id m dur params auto)
  (setq id (HYDRO:Get "HYDRO.BACIA.METODO" nil))
  ;; modo automatico (CALCAUTO): ultimo TR e metodo, sem perguntas
  (setq auto
    (if (and (HYDRO:CalcAuto)
             (HYDRO:Get "HYDRO.TR" nil)
             id
             (HYDRO:RegGet "metodo-chuva-vazao" id))
      t
      nil))
  (if auto
    (princ (strcat "\nModo automatico: TR " (HYDRO:FmtReal (HYDRO:Get "HYDRO.TR" nil))
                   " anos, metodo " (BAC:NomeMetodo id)))
  )
  (setq tr
    (if auto
      (HYDRO:Get "HYDRO.TR" nil)
      (HYDRO:AskReal "Tempo de retorno (anos)" (HYDRO:Get "HYDRO.TR" nil))))
  (cond
    ((or (not tr) (<= tr 0.0))
      (alert "Tempo de retorno nao informado.")
      nil
    )
    (t
      (if (not auto) (setq id (BAC:_EscolheMetodo)))
      (if (not id)
        (progn (alert "Metodo nao escolhido.") nil)
        (progn
          (setq m (HYDRO:RegGet "metodo-chuva-vazao" id))
          (HYDRO:Set "HYDRO.TR" tr)
          (HYDRO:Set "HYDRO.BACIA.METODO" id)
          (setq dur
            (if (and (cdr (assoc "USA-DUR" m)) (not auto))
              (HYDRO:AskReal "Duracao da chuva (min)" (HYDRO:Val "TC" cad))
              (HYDRO:Val "TC" cad)
            )
          )
          (setq params
            (if auto
              (HYDRO:ParamsPadrao
                (cdr (assoc "PARAMS" m))
                (strcat "HYDRO.MET." id ".")
                (BAC:_Sobrescritas cad (cdr (assoc "PARAMS" m))))
              (HYDRO:AskParams
                (cdr (assoc "PARAMS" m))
                (strcat "HYDRO.MET." id ".")
                (BAC:_Sobrescritas cad (cdr (assoc "PARAMS" m))))
            )
          )
          (list (cons "TR" tr) (cons "ID" id) (cons "DUR" dur) (cons "PARAMS" params)
                (cons "CENARIO" (OBJ:CenarioNome tr (OBJ:NomeCenario))))
        )
      )
    )
  )
)

;; Recalcula os montantes da bacia (em ordem) antes de calcula-la. nil = ok, ou o erro.
(defun BAC:_RecalcMontantes (contorno perg)
  (if (and (HYDRO:Has "ligacao") (LIG:Afluentes contorno))
    (LIG:RecalcularMontantes contorno (HYDRO:Val "CENARIO" perg)
                             (HYDRO:Val "ID" perg) (HYDRO:Val "TR" perg))
    nil
  )
)

;; Capacidade "RECALCULA" (fn en cenario metodo tr): recalcula a bacia SEM perguntas neste
;; cenario, com o INPUT do ultimo calculo dele (ou os padroes do projeto). Retorna nil ou o erro (texto).
;; Os montantes dela ja devem ter sido recalculados (quem chama ordena).
(defun BAC:_ObjRecalcula (en cenario metodo tr / dados h talv cad m ant params dur calc)
  (setq dados (BAC:Ler en))
  (setq h (BAC:Talvegue dados))
  (setq talv (if (OBJ:HandleOk h) (handent h) nil))   ; talvegue e opcional
  (setq m (HYDRO:RegGet "metodo-chuva-vazao" metodo))
  (cond
    ((not dados) "Bacia nao cadastrada (use BACIACAD).")
    ((not m) (strcat "Metodo nao cadastrado: " metodo))
    (t
      (setq cad (BAC:Preparar en))
      (if (assoc "ERRO" cad)
        (HYDRO:Val "ERRO" cad)
        (progn
          ;; calculo anterior neste cenario (so vale se foi do mesmo metodo)
          (setq ant (BAC:CalcDe (BAC:Ler en) cenario))
          (if (and ant (not (equal (HYDRO:Val "METODO" ant) metodo))) (setq ant nil))
          (setq params
            (if ant
              (HYDRO:Val "PARAMS" ant)
              (HYDRO:ParamsPadrao
                (cdr (assoc "PARAMS" m))
                (strcat "HYDRO.MET." metodo ".")
                (BAC:_Sobrescritas cad (cdr (assoc "PARAMS" m))))))
          (setq dur
            (if (and ant (cdr (assoc "USA-DUR" m)) (HYDRO:Val "DUR" ant))
              (HYDRO:Val "DUR" ant)
              (HYDRO:Val "TC" cad)))
          (setq calc
            (BAC:_CalcularEGravar en talv cad
              (list (cons "TR" tr) (cons "ID" metodo) (cons "DUR" dur)
                    (cons "PARAMS" params) (cons "CENARIO" cenario))))
          (if (assoc "ERRO" calc) (HYDRO:Val "ERRO" calc) nil)
        )
      )
    )
  )
)

;; Fluxo completo: contorno, talvegue, cadastro (se preciso), perguntas e
;; calculo. Retorna (contorno . calculo) ou nil.
;; Fluxo completo: contorno, cadastro (se preciso, o generico), preparo (tc), perguntas
;; e calculo. Retorna (contorno . calculo) ou nil.
(defun BAC:_FluxoCalculo (/ contorno dados talv cad perg calc erro h)
  (setq contorno (BAC:SelLinha "\nSelecione a polilinha do CONTORNO da bacia: "))
  (cond
    ((not contorno) nil)
    (t
      (if (not (BAC:_Fechada contorno))
        (princ "\nAviso: o contorno nao esta fechado; a area sera a da figura fechada pela corda.")
      )
      (setq dados (BAC:Ler contorno))
      (if (not dados)
        (progn
          (OBJ:CadastroInterativoTipo contorno "bacia")
          (setq dados (BAC:Ler contorno))
        )
      )
      (cond
        ((not dados) (princ "\nBacia nao cadastrada.") nil)
        ((not (HYDRO:RegList "metodo-chuva-vazao"))
          (alert "Nenhum metodo chuva-vazao cadastrado (plugin 'metodos-chuva-vazao').")
          nil
        )
        (t
          (setq cad (BAC:Preparar contorno))
          (cond
            ((assoc "ERRO" cad)
              (alert (strcat "Erro: " (HYDRO:Val "ERRO" cad)))
              nil
            )
            (t
              (setq h (BAC:Talvegue (BAC:Ler contorno)))
              (setq talv (if (OBJ:HandleOk h) (handent h) nil))
              (princ
                (strcat "\nUsando tc = " (rtos (HYDRO:Val "TC" cad) 2 2) " min ("
                        (BAC:NomeTc (HYDRO:Val "TC-ORIGEM" cad))
                        "). Para alterar: BACIAEDITA."))
              (setq perg (BAC:_PerguntasCalculo cad))
              (if perg (princ (strcat "\nCenario: " (HYDRO:Val "CENARIO" perg))))
              (if perg
                (progn
                  ;; montantes recalculados antes, em ordem, sem o usuario precisar
                  (setq erro (BAC:_RecalcMontantes contorno perg))
                  (setq calc
                    (if erro
                      (BAC:_Erro (strcat "Montante: " erro))
                      (BAC:_CalcularEGravar contorno talv cad perg)))
                  (cond
                    ((assoc "ERRO" calc)
                      (alert (strcat "Erro: " (HYDRO:Val "ERRO" calc)))
                      nil
                    )
                    (t (cons contorno calc))
                  )
                )
                nil
              )
            )
          )
        )
      )
    )
  )
)

;; Texto do alert apos um calculo: cadastro + o calculo recem feito
(defun BAC:_Resumo (contorno calc)
  (HYDRO:Join
    (BAC:LinhasTexto (BAC:Ler contorno) (HYDRO:Handle contorno) (list calc))
    "\n")
)

;; Mostra o resumo: alert, ou so a linha de comando no modo automatico (CALCAUTO)
(defun BAC:_Mostra (texto)
  (if (HYDRO:CalcAuto)
    (princ (strcat "\n" texto))
    (alert texto)
  )
)

;; Comandos padrao do objeto (docs/arquitetura.md secao 18b): os fluxos sao os genericos
;; de views/objetos_padrao_view.lsp; aqui so se diz de que tipo e.
(defun BAC:_Padrao (fn)
  (if (HYDRO:Has "objetos-padrao-view")
    (apply fn (list "bacia"))
    (alert "Comandos de objeto indisponiveis: carregue objetos_padrao e a view dele.")
  )
  (princ)
)

(defun c:BACIACAD ()   (BAC:_Padrao 'OPV:Cadastrar))
(defun c:BACIAEDITA () (BAC:_Padrao 'OPV:EditaCampo))
(defun c:BACIAS ()     (BAC:_Padrao 'OPV:Listar))
(defun c:BACIAINFO ()  (BAC:_Padrao 'OPV:Info))
(defun c:BACIAZOOM ()  (BAC:_Padrao 'OPV:Zoom))

(defun c:BACIA (/ r)
  (setq r (BAC:_FluxoCalculo))
  (if r (BAC:_Mostra (BAC:_Resumo (car r) (cdr r))))
  (princ)
)

;; Escolhe quais calculos entram no texto: um ou todos
(defun BAC:_EscolheCalculos (dados / calcs idx)
  (setq calcs (BAC:Vazao dados))
  (cond
    ((null calcs) nil)
    ((= (length calcs) 1) calcs)
    (t
      (setq idx
        (HYDRO:Escolher "Calculos da bacia:"
          (cons "Todos os calculos" (mapcar 'BAC:RotuloVazao calcs))
          (length calcs)))
      (if (= idx 0) calcs (list (nth (1- idx) calcs)))
    )
  )
)

;; Seleciona um contorno que ja tem cadastro
(defun BAC:_SelBaciaCad (/ en)
  (setq en (BAC:SelLinha "\nSelecione o CONTORNO da bacia: "))
  (cond
    ((not en) nil)
    ((not (BAC:Ler en))
      (alert "Esta entidade nao tem cadastro de bacia. Use BACIACAD ou BACIA.")
      nil
    )
    (t en)
  )
)

(HYDRO:Provide "bacia" "3.0")
(princ)
