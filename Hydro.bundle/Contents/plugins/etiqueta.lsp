;;; ============================================================
;;; etiqueta.lsp - ETIQUETAS DINAMICAS E TABELA VIVA (ETQ:)
;;;
;;; Deixa o Hydro "visivel" no desenho. Dois elementos que se ATUALIZAM sozinhos
;;; quando o objeto e cadastrado, recalculado ou ligado:
;;;
;;; 1) ETIQUETA = um MTEXT na camada HYDRO-ETIQUETA, ligado a um objeto
;;;    (chave "HYDRO-ETQ" na etiqueta: ALVO = handle, MODO, MODELO).
;;;      MODO "FIXO"    relatorio do objeto (o mesmo texto de OBJ:Resumo)
;;;      MODO "MODELO"  texto com campos {CAMPO}, editavel por etiqueta
;;;    Campos (sem diferenciar maiusculas; "?" se o campo nao existe):
;;;      {NOME} {TIPO} {HANDLE} {CENARIO}
;;;      {AREA}            area em ha (CARACT)
;;;      {C} {CN} {N}...   qualquer chave de ATRIB; depois de CARACT ({COMP} {DECL} {DESNIVEL});
;;;                        depois dos campos do CENARIO (grupos VAZAO e PRECIPITACAO: {QP-PROPRIO}
;;;                        {I} {P} {PE}; e o INPUT da vazao)
;;;      {GRUPO.CAMPO}     qualquer campo de qualquer grupo do cenario: {VAZAO.VALOR} {TC.METODO}
;;;                        {ALTURA_LAMINA.VALOR}; {GRUPO} sozinho = {GRUPO.VALOR}
;;;      atalhos:          {QP}=VAZAO.VALOR {TC}=VAZAO.TC (tc de saida) {TCP}=TC.VALOR (tc proprio)
;;;                        {TR}=CENARIO.TR {METODO}=VAZAO.METODO {E.QP}=ENTRADA.VALOR {E.TC}
;;;                        {H.LAMINA}=ALTURA_LAMINA {H.VELOCIDADE} {H.LARGURA} {H.PERCURSO}
;;;    CENARIO: a etiqueta pode fixar um cenario (HYDRO-ETQ "CENARIO"); sem ele, segue o cenario em
;;;    uso (OBJ:CenarioAtual) e, se o objeto nao o tem, o ultimo cenario calculado. Resultado
;;;    desatualizado (OBSOLETO) acrescenta "(resultado desatualizado)" ao texto.
;;;    \P quebra a linha. Modelo padrao por tipo: HYDRO.ETIQUETA.MODELO.<tipo>.
;;;
;;; 2) TABELA VIVA = um objeto TABLE na camada HYDRO-TABELA (chave "HYDRO-TBL") com
;;;    todos os objetos cadastrados: nome, tipo, A, L, S, atributos, cenario, Q entrada,
;;;    Q saida (com "*" se desatualizado), tc e destino. As linhas sao refeitas a cada atualizacao.
;;;
;;; ATUALIZACAO: assina "bacia.calculada", "objeto.calculado", "objeto.cadastrado", "ligacao.criada" e
;;; "ligacao.removida" (etiquetas do objeto e tabelas); "objeto.obsoleto" (so as etiquetas do objeto) e
;;; "objetos.obsoletos" (so as tabelas, uma vez por edicao: evita refazer a tabela a cada objeto da cadeia).
;;; Mostra o que esta GRAVADO: mover a geometria sem recalcular nao muda o resultado.
;;; Comandos e perguntas: views/etiqueta_view.lsp.
;;; Auditoria: "etiquetas" (etiqueta cujo objeto nao existe mais; corrige apagando-a).
;;; Sem variaveis globais.
;;; ============================================================
(vl-load-com)

;;; ------------------------------------------------------------
;;; SUBSTITUICAO DE CAMPOS (pura)
;;; ------------------------------------------------------------
;; Troca cada {NOME} do modelo por (fn "NOME") (string) ou "?" se fn devolver nil.
;; Chave sem fechar "}" fica como esta.
(defun ETQ:Substitui (modelo fn / out i n j nome v)
  (setq out "" i 1 n (strlen modelo))
  (while (<= i n)
    (setq j (if (equal (substr modelo i 1) "{") (vl-string-search "}" modelo i) nil))
    (if j
      (progn
        (setq nome (substr modelo (1+ i) (- j i)))
        (setq v (apply fn (list nome)))
        (setq out (strcat out (if (= (type v) 'STR) v "?")))
        (setq i (+ j 2))
      )
      (progn
        (setq out (strcat out (substr modelo i 1)))
        (setq i (1+ i))
      )
    )
  )
  out
)

;; par (chave . valor) cuja chave e igual sem diferenciar maiusculas, ou nil
(defun ETQ:_CI (chave alist / out p)
  (foreach p alist
    (if (and (not out) (equal (strcase (car p)) (strcase chave)))
      (setq out p)
    )
  )
  out
)

;; valor para texto: reais com 3 casas (4 se menores que 1), inteiros, textos, T = "sim"
(defun ETQ:_Fmt (v)
  (cond
    ((null v) nil)
    ((= (type v) 'REAL) (if (< (abs v) 1.0) (rtos v 2 4) (rtos v 2 3)))
    ((= (type v) 'INT) (itoa v))
    ((= (type v) 'STR) v)
    ((equal v T) "sim")
    (T (vl-prin1-to-string v))
  )
)

;; (puro) cenario a usar para `result`: o `pref` (da etiqueta) se o objeto o tem; senao o cenario em
;; uso (OBJ:CenarioAtual) se o objeto o tem; senao o ultimo cenario do objeto; nil se sem resultado
(defun ETQ:_CenarioR (result pref / atual)
  (setq atual (OBJ:CenarioAtual))
  (cond
    ((null result) nil)
    ((and pref (assoc pref result)) pref)
    ((and atual (assoc atual result)) atual)
    (T (car (last result)))
  )
)

;; (puro) campo `spec` = "GRUPO" ou "GRUPO.CAMPO" dos grupos do cenario (sem diferenciar maiusculas);
;; "E" vale ENTRADA; sem campo, VALOR. nil se nao existe.
(defun ETQ:_GC (grupos spec / j g campo)
  (setq j (vl-string-search "." spec))
  (setq g (if j (substr spec 1 j) spec))
  (setq campo (if j (substr spec (+ j 2)) "VALOR"))
  (if (equal (strcase g) "E") (setq g "ENTRADA"))
  (setq g (ETQ:_CI g grupos))
  (if g (cdr (ETQ:_CI campo (cdr g))) nil)
)

;; atalhos (campos antigos) -> GRUPO.CAMPO
(defun ETQ:_Aliases ()
  '(("QP" . "VAZAO.VALOR") ("TC" . "VAZAO.TC") ("TCP" . "TC.VALOR") ("TR" . "CENARIO.TR")
    ("METODO" . "VAZAO.METODO") ("H.LAMINA" . "ALTURA_LAMINA.VALOR")
    ("H.LARGURA" . "LARGURA_INUNDADA.VALOR") ("H.VELOCIDADE" . "VELOCIDADE.VALOR")
    ("H.PERCURSO" . "PERCURSO.VALOR") ("H.AREA_MOLHADA" . "AREA_MOLHADA.VALOR"))
)

;; Valor padrao do projeto (PADROES) de um parametro: primeiro nos ATRIB do tipo do
;; objeto, depois nos parametros dos metodos chuva-vazao. Retorna (CHAVE . valor) ou nil.
(defun ETQ:_PadraoDe (en nome / id d m v out)
  (setq id (OBJ:TipoDe en))
  (foreach d (if id (OBJ:Cap id "ATRIB-DEFS") nil)
    (if (and (not out) (equal (strcase (car d)) (strcase nome)))
      (setq v (HYDRO:Padrao (strcat "HYDRO.OBJ." id ".") (car d)))
    )
    (if (and v (not out)) (setq out (cons nome v)))
  )
  (foreach m (HYDRO:RegList "metodo-chuva-vazao")
    (foreach d (cdr (assoc "PARAMS" (cdr m)))
      (if (and (not out) (equal (strcase (car d)) (strcase nome)))
        (progn
          (setq v (HYDRO:Padrao (strcat "HYDRO.MET." (car m) ".") (car d)))
          (if v (setq out (cons nome v)))
        )
      )
    )
  )
  out
)

;; (puro, dado o registro) valor (string) de um campo do modelo, ou nil. `en` so e usado para
;; HANDLE, nome automatico e padrao do projeto (pode ser nil em testes).
(defun ETQ:_CampoR (en reg nome pref / up res cen grupos c atrib alias par g v)
  (setq up (strcase nome))
  (setq res (OBJ:_Val "RESULT" reg))
  (setq cen (ETQ:_CenarioR res pref))
  (setq grupos (if cen (cdr (assoc cen res)) nil))
  (setq c (OBJ:_Val "CARACT" reg))
  (setq atrib (OBJ:_Val "ATRIB" reg))
  (setq alias (cdr (assoc up (ETQ:_Aliases))))
  (cond
    ((equal up "NOME") (if (OBJ:_Val "NOME" reg) (OBJ:_Val "NOME" reg) (OBJ:Nome en)))
    ((equal up "TIPO") (OBJ:_NomeTipo (OBJ:_Val "TIPO" reg)))
    ((equal up "HANDLE") (if en (HYDRO:Handle en) nil))
    ((equal up "CENARIO") cen)
    ((equal up "AREA")
      (if (cdr (assoc "AREA" c)) (rtos (/ (cdr (assoc "AREA" c)) 10000.0) 2 3) nil))
    (alias
      (setq v (ETQ:_GC grupos alias))
      ;; sem VAZAO ainda, o tc e o proprio
      (if (and (null v) (equal up "TC")) (setq v (ETQ:_GC grupos "TC.VALOR")))
      (ETQ:_Fmt v)
    )
    ((vl-string-search "." nome) (ETQ:_Fmt (ETQ:_GC grupos nome)))
    (T
      (setq par (ETQ:_CI nome atrib))
      (if (not par) (setq par (ETQ:_CI nome c)))
      ;; campos do cenario: vazao, precipitacao e o INPUT usado (C, CN... do padrao do projeto)
      (if (not par) (setq par (ETQ:_CI nome (cdr (assoc "VAZAO" grupos)))))
      (if (not par) (setq par (ETQ:_CI nome (cdr (assoc "PRECIPITACAO" grupos)))))
      (if (not par)
        (setq par (ETQ:_CI nome (OBJ:_Val "INPUT" (cdr (assoc "VAZAO" grupos))))))
      ;; {GRUPO} sozinho = o VALOR dele
      (if (not par)
        (progn
          (setq g (ETQ:_CI nome grupos))
          (if g (setq par (cons nome (OBJ:_Val "VALOR" (cdr g)))))
        )
      )
      ;; ainda sem calculo: o valor que VALERIA (padrao do projeto)
      (if (and (not par) en) (setq par (ETQ:_PadraoDe en nome)))
      (if par (ETQ:_Fmt (cdr par)) nil)
    )
  )
)

;; valor (string) de um campo do modelo para o objeto en, ou nil. pref = cenario fixado (ou nil)
(defun ETQ:Campo (en nome pref)
  (ETQ:_CampoR en (OBJ:Registro en) nome pref)
)

;; modelo padrao do tipo: o configurado (HYDRO.ETIQUETA.MODELO.<tipo>) ou o de fabrica
(defun ETQ:ModeloPadrao (id / cfg)
  (setq cfg (if id (HYDRO:Get (strcat "HYDRO.ETIQUETA.MODELO." id) nil) nil))
  (cond
    (cfg cfg)
    ((equal id "bacia")
      "{NOME}\\PA = {AREA} ha   tc = {TC} min\\PC = {C}   CN = {CN}\\PQp = {QP} m3/s  ({CENARIO})")
    (T
      "{NOME}\\PQ = {ENTRADA.VALOR} m3/s   tc = {ENTRADA.TC} min\\PLamina = {ALTURA_LAMINA} m   V = {VELOCIDADE} m/s")
  )
)

;; texto de uma etiqueta: relatorio (FIXO) ou modelo preenchido; pref = cenario fixado ou nil
;; (o registro do objeto e lido UMA vez por etiqueta)
(defun ETQ:TextoDe (en modo modelo pref / reg cen txt)
  (setq reg (OBJ:Registro en))
  (setq cen (ETQ:_CenarioR (OBJ:_Val "RESULT" reg) pref))
  (setq txt
    (if (equal modo "FIXO")
      (HYDRO:Join (OBJ:Resumo en) "\\P")
      (ETQ:Substitui (if modelo modelo (ETQ:ModeloPadrao (OBJ:_Val "TIPO" reg)))
                     (function (lambda (n) (ETQ:_CampoR en reg n pref))))
    )
  )
  (if (and cen (OBJ:_ObsoletoR (OBJ:_Val "RESULT" reg) cen))
    (strcat txt "\\P(resultado desatualizado)")
    txt
  )
)

;;; ------------------------------------------------------------
;;; ETIQUETAS NO DESENHO
;;; ------------------------------------------------------------
(defun ETQ:_Camada (nome cor)
  (if (not (tblsearch "LAYER" nome))
    (entmakex
      (list '(0 . "LAYER")
            '(100 . "AcDbSymbolTableRecord")
            '(100 . "AcDbLayerTableRecord")
            (cons 2 nome)
            '(70 . 0)
            (cons 62 cor)
            '(6 . "Continuous"))
    )
  )
)

;; enames das entidades de uma camada e tipo DXF que tem a chave dada gravada
(defun ETQ:_Procura (dxf camada chave / ss i en out)
  (setq ss (ssget "_X" (list (cons 0 dxf) (cons 8 camada))))
  (if ss
    (progn
      (setq i (sslength ss))
      (while (> i 0)
        (setq i (1- i))
        (setq en (ssname ss i))
        (if (HYDRO:DadoLer en chave)
          (setq out (cons en out))
        )
      )
    )
  )
  out
)

(defun ETQ:Etiquetas ()
  (ETQ:_Procura "MTEXT" "HYDRO-ETIQUETA" "HYDRO-ETQ")
)

;; Cria a etiqueta do objeto `alvo` em pt (UCS). modo "FIXO" ou "MODELO". cenario = nome fixado
;; (ou nil: segue o cenario em uso).
;; Retorna o ename ou nil.
(defun ETQ:CriaEtiqueta (alvo pt modo modelo altura cenario / en)
  (ETQ:_Camada "HYDRO-ETIQUETA" 3)
  (setq en (HYDRO:Mtext pt "." altura 0.0))
  (if en
    (progn
      (vl-catch-all-apply 'vla-put-layer (list (vlax-ename->vla-object en) "HYDRO-ETIQUETA"))
      (HYDRO:DadoGravar en "HYDRO-ETQ"
        (OBJ:_Limpa
          (list (cons "VERSAO" 1)
                (cons "ALVO" (HYDRO:Handle alvo))
                (cons "MODO" modo)
                (cons "MODELO" modelo)
                (cons "CENARIO" cenario))))
      (ETQ:Atualiza en)
      en
    )
    nil
  )
)

;; Reescreve o texto de uma etiqueta se o objeto existir e o texto mudou.
;; Retorna T se a etiqueta tem objeto valido.
(defun ETQ:Atualiza (lab / reg alvo en txt obj atual)
  (setq reg (HYDRO:DadoLer lab "HYDRO-ETQ"))
  (setq alvo (cdr (assoc "ALVO" reg)))
  (setq en (if alvo (handent alvo) nil))
  (if (and reg en (HYDRO:EntValida en) (HYDRO:EntValida lab) (OBJ:TipoDe en))
    (progn
      (setq txt (ETQ:TextoDe en (cdr (assoc "MODO" reg)) (cdr (assoc "MODELO" reg))
                         (cdr (assoc "CENARIO" reg))))
      (setq obj (vlax-ename->vla-object lab))
      (setq atual (vl-catch-all-apply 'vla-get-textstring (list obj)))
      (if (and (not (vl-catch-all-error-p atual)) (not (equal atual txt)))
        (vl-catch-all-apply 'vla-put-textstring (list obj txt))
      )
      T
    )
    nil
  )
)

;; atualiza as etiquetas que apontam para o objeto en. Retorna quantas.
(defun ETQ:AtualizaDe (en / h lab reg n)
  (setq h (HYDRO:Handle en))
  (setq n 0)
  (foreach lab (ETQ:Etiquetas)
    (setq reg (HYDRO:DadoLer lab "HYDRO-ETQ"))
    (if (equal (cdr (assoc "ALVO" reg)) h)
      (if (ETQ:Atualiza lab) (setq n (1+ n)))
    )
  )
  n
)

;;; ------------------------------------------------------------
;;; TABELA VIVA
;;; ------------------------------------------------------------
(defun ETQ:Cabecalho ()
  '("Nome" "Tipo" "A (ha)" "L (m)" "S (m/m)" "Atributos" "Cenario"
    "Q entrada (m3/s)" "Q saida (m3/s)" "tc (min)" "Destino")
)

(defun ETQ:_S (x)
  (if x x "-")
)

;; linha da tabela (lista de strings, uma por coluna) para o objeto
(defun ETQ:LinhaTabela (en / reg dest atr p obs)
  (setq reg (OBJ:Registro en))
  (setq dest (if (HYDRO:Has "ligacao") (LIG:Destino en) nil))
  (foreach p (OBJ:_Val "ATRIB" reg)
    (setq atr (append atr (list (strcat (car p) "=" (ETQ:_Fmt (cdr p))))))
  )
  (setq obs
    (OBJ:_ObsoletoR (OBJ:_Val "RESULT" reg)
                    (ETQ:_CenarioR (OBJ:_Val "RESULT" reg) nil)))
  (list
    (OBJ:Nome en)
    (OBJ:_NomeTipo (OBJ:_Val "TIPO" reg))
    (ETQ:_S (ETQ:_CampoR en reg "AREA" nil))
    (ETQ:_S (ETQ:_CampoR en reg "COMP" nil))
    (ETQ:_S (ETQ:_CampoR en reg "DECL" nil))
    (if atr (HYDRO:Join atr " ") "-")
    (ETQ:_S (ETQ:_CampoR en reg "CENARIO" nil))
    (ETQ:_S (ETQ:_CampoR en reg "E.QP" nil))
    (ETQ:_S
      (if (ETQ:_CampoR en reg "QP" nil)
        (strcat (ETQ:_CampoR en reg "QP" nil) (if obs "*" ""))
        nil))
    (ETQ:_S (ETQ:_CampoR en reg "TC" nil))
    (if dest (OBJ:Nome dest) "-")
  )
)

(defun ETQ:Tabelas ()
  (ETQ:_Procura "ACAD_TABLE" "HYDRO-TABELA" "HYDRO-TBL")
)

;; escreve o texto da celula so se mudou
(defun ETQ:_Cel (obj r c txt / atual)
  (setq atual (vl-catch-all-apply 'vla-gettext (list obj r c)))
  (if (or (vl-catch-all-error-p atual) (not (equal atual txt)))
    (vl-catch-all-apply 'vla-settext (list obj r c txt))
  )
)

;; refaz as linhas da tabela viva: titulo, cabecalho e um objeto por linha
(defun ETQ:AtualizaTabela (tb / obj objs need rows r c lin cab en h)
  (setq obj (vlax-ename->vla-object tb))
  (setq objs
    (vl-sort (OBJ:Listar)
      (function (lambda (a b) (< (strcase (OBJ:Nome a)) (strcase (OBJ:Nome b)))))))
  (setq need (+ 2 (max 1 (length objs))))
  (setq rows (vl-catch-all-apply 'vla-get-rows (list obj)))
  (if (not (vl-catch-all-error-p rows))
    (progn
      ;; ajusta a quantidade de linhas (o conteudo e todo reescrito depois)
      (cond
        ((< rows need)
          (setq h (vl-catch-all-apply 'vla-getrowheight (list obj (1- rows))))
          (if (vl-catch-all-error-p h) (setq h 1.0))
          (vl-catch-all-apply 'vla-insertrows (list obj (1- rows) h (- need rows))))
        ((> rows need)
          (vl-catch-all-apply 'vla-deleterows (list obj 2 (- rows need))))
      )
      (ETQ:_Cel obj 0 0 "Objetos Hydro  (* = resultado desatualizado)")
      (setq c 0)
      (foreach cab (ETQ:Cabecalho)
        (ETQ:_Cel obj 1 c cab)
        (setq c (1+ c))
      )
      (setq r 2)
      (if objs
        (foreach en objs
          (setq c 0)
          (foreach lin (ETQ:LinhaTabela en)
            (ETQ:_Cel obj r c lin)
            (setq c (1+ c))
          )
          (setq r (1+ r))
        )
        (progn
          (ETQ:_Cel obj 2 0 "(nenhum objeto cadastrado)")
          (setq c 1)
          (while (< c (length (ETQ:Cabecalho)))
            (ETQ:_Cel obj 2 c "")
            (setq c (1+ c))
          )
        )
      )
      T
    )
    nil
  )
)

;; Cria a tabela viva em pt (UCS) e a preenche. Retorna o ename ou nil.
(defun ETQ:CriaTabela (pt altura / ms tbl en cols w c x)
  (ETQ:_Camada "HYDRO-TABELA" 3)
  (setq cols (length (ETQ:Cabecalho)))
  (setq ms (vla-get-modelspace (vla-get-activedocument (vlax-get-acad-object))))
  (setq tbl
    (vl-catch-all-apply 'vla-addtable
      (list ms (vlax-3d-point (trans pt 1 0)) 4 cols (* 2.4 altura) (* 12.0 altura))))
  (if (vl-catch-all-error-p tbl)
    nil
    (progn
      (vl-catch-all-apply 'vla-put-layer (list tbl "HYDRO-TABELA"))
      (foreach c '(1 2 4)
        (vl-catch-all-apply 'vla-settextheight (list tbl c altura))
      )
      (setq w '(10 9 8 8 9 20 9 12 12 8 10))
      (setq c 0)
      (foreach x w
        (vl-catch-all-apply 'vla-setcolumnwidth (list tbl c (* x altura)))
        (setq c (1+ c))
      )
      (setq en (vlax-vla-object->ename tbl))
      (HYDRO:DadoGravar en "HYDRO-TBL" (list (cons "VERSAO" 1)))
      (ETQ:AtualizaTabela en)
      en
    )
  )
)

;;; ------------------------------------------------------------
;;; ATUALIZACAO
;;; ------------------------------------------------------------
;; atualiza etiquetas e tabelas. Retorna (n-etiquetas . n-tabelas).
(defun ETQ:AtualizaTudo (/ n m lab tb)
  (setq n 0 m 0)
  (foreach lab (ETQ:Etiquetas)
    (if (ETQ:Atualiza lab) (setq n (1+ n)))
  )
  (foreach tb (ETQ:Tabelas)
    (if (ETQ:AtualizaTabela tb) (setq m (1+ m)))
  )
  (cons n m)
)

;; reacao aos eventos: nunca pode atrapalhar o calculo (tudo protegido)
(defun ETQ:_Reage (dados / en lab tb)
  (foreach lab '("OBJETO" "BACIA" "ORIGEM" "DESTINO")
    (setq en (cdr (assoc lab dados)))
    (if (and en (= (type en) 'ENAME) (HYDRO:EntValida en))
      (ETQ:AtualizaDe en)
    )
  )
  (foreach tb (ETQ:Tabelas)
    (ETQ:AtualizaTabela tb)
  )
)

(defun ETQ:_OnEvento (dados)
  (vl-catch-all-apply 'ETQ:_Reage (list dados))
)

;; objeto marcado como desatualizado: so as etiquetas dele; as tabelas, uma vez, em "objetos.obsoletos"
(defun ETQ:_OnObsoleto (dados / en)
  (setq en (cdr (assoc "OBJETO" dados)))
  (if (and en (= (type en) 'ENAME) (HYDRO:EntValida en))
    (vl-catch-all-apply 'ETQ:AtualizaDe (list en))
  )
)

(defun ETQ:_OnObsoletos (dados / tb)
  (foreach tb (ETQ:Tabelas)
    (vl-catch-all-apply 'ETQ:AtualizaTabela (list tb))
  )
)

(HYDRO:On "objeto.obsoleto" "etiqueta" 'ETQ:_OnObsoleto)
(HYDRO:On "objetos.obsoletos" "etiqueta" 'ETQ:_OnObsoletos)
(HYDRO:On "bacia.calculada" "etiqueta" 'ETQ:_OnEvento)
(HYDRO:On "objeto.calculado" "etiqueta" 'ETQ:_OnEvento)
(HYDRO:On "objeto.cadastrado" "etiqueta" 'ETQ:_OnEvento)
(HYDRO:On "ligacao.criada" "etiqueta" 'ETQ:_OnEvento)
(HYDRO:On "ligacao.removida" "etiqueta" 'ETQ:_OnEvento)

;;; ------------------------------------------------------------
;;; AUDITORIA: etiqueta cujo objeto nao existe mais
;;; ------------------------------------------------------------
(defun ETQ:_AudEtiquetas (/ out lab reg alvo en)
  (foreach lab (ETQ:Etiquetas)
    (setq reg (HYDRO:DadoLer lab "HYDRO-ETQ"))
    (setq alvo (cdr (assoc "ALVO" reg)))
    (setq en (if alvo (handent alvo) nil))
    (if (not (and en (HYDRO:EntValida en) (OBJ:TipoDe en)))
      (setq out (append out (list (list "ETIQUETA-ORFA" lab alvo))))
    )
  )
  out
)

(defun ETQ:_TxtEtiquetas (p)
  (strcat "Etiqueta " (HYDRO:Handle (nth 1 p)) " aponta para o objeto "
          (if (nth 2 p) (nth 2 p) "?") ", que nao existe mais ou nao e objeto")
)

(defun ETQ:_ReparaEtiquetas (problemas / n p)
  (setq n 0)
  (foreach p problemas
    (if (not (vl-catch-all-error-p (vl-catch-all-apply 'entdel (list (nth 1 p)))))
      (setq n (1+ n))
    )
  )
  n
)

(HYDRO:RegAdd "auditoria" "etiquetas"
  (list (cons "NOME" "Etiquetas dinamicas")
        (cons "VERIFICA" 'ETQ:_AudEtiquetas)
        (cons "TEXTO" 'ETQ:_TxtEtiquetas)
        (cons "REPARA" 'ETQ:_ReparaEtiquetas)))

(HYDRO:Provide "etiqueta" "1.0")
(princ)
