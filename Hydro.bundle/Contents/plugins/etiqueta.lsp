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
;;;      {NOME} {TIPO} {HANDLE}
;;;      {AREA}            area em ha (CARACT)
;;;      {C} {CN} {N}...   qualquer chave de ATRIB; depois qualquer chave de CARACT
;;;                        ({COMP} {DECL} {DESNIVEL}); depois do ULTIMO calculo
;;;                        (grupo VAZAO = saida): {QP} {TR} {TC} {METODO} {QP-PROPRIO}
;;;      {TCP}             tc proprio da bacia (min)
;;;      {E.QP} {E.TC}     ENTRADA (o que veio dos montantes), ultimo calculo
;;;      {H.LAMINA} {H.VELOCIDADE} {H.PERCURSO}   HIDRAULICA do ultimo calculo
;;;    \P quebra a linha. Modelo padrao por tipo: HYDRO.ETIQUETA.MODELO.<tipo>.
;;;
;;; 2) TABELA VIVA = um objeto TABLE na camada HYDRO-TABELA (chave "HYDRO-TBL") com
;;;    todos os objetos cadastrados: nome, tipo, A, L, S, atributos, TR, Q entrada,
;;;    Q saida, tc e destino. As linhas sao refeitas a cada atualizacao.
;;;
;;; ATUALIZACAO: assina os eventos "bacia.calculada", "objeto.calculado",
;;; "bacia.cadastrada", "objeto.cadastrado", "ligacao.criada" e "ligacao.removida".
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

(defun ETQ:_Ultimo (en grupo)
  (last (OBJ:GrupoDe en grupo))
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

;; valor (string) de um campo do modelo para o objeto en, ou nil
(defun ETQ:Campo (en nome / up c par)
  (setq up (strcase nome))
  (setq c (OBJ:CaractDe en))
  (cond
    ((equal up "NOME") (OBJ:Nome en))
    ((equal up "TIPO") (OBJ:_NomeTipo (OBJ:TipoDe en)))
    ((equal up "HANDLE") (HYDRO:Handle en))
    ((equal up "AREA")
      (if (cdr (assoc "AREA" c)) (rtos (/ (cdr (assoc "AREA" c)) 10000.0) 2 3) nil))
    ((equal up "TCP") (ETQ:_Fmt (OBJ:_Val "MIN" (OBJ:GrupoDe en "TC"))))
    ((equal (substr up 1 2) "E.")
      (ETQ:_Fmt (cdr (ETQ:_CI (substr nome 3) (ETQ:_Ultimo en "ENTRADA")))))
    ((equal (substr up 1 2) "H.")
      (ETQ:_Fmt (cdr (ETQ:_CI (substr nome 3) (ETQ:_Ultimo en "HIDRAULICA")))))
    (T
      (setq par (ETQ:_CI nome (OBJ:AtribDe en)))
      (if (not par) (setq par (ETQ:_CI nome c)))
      (if (not par) (setq par (ETQ:_CI nome (ETQ:_Ultimo en "VAZAO"))))
      ;; parametros USADOS no ultimo calculo (C, CN... vindos do padrao do projeto)
      (if (not par)
        (setq par (ETQ:_CI nome (cdr (assoc "PARAMS" (ETQ:_Ultimo en "VAZAO"))))))
      (if (not par)
        (setq par (ETQ:_CI nome (cdr (assoc "PARAMS" (ETQ:_Ultimo en "HIDRAULICA"))))))
      ;; ainda sem calculo: o valor que VALERIA (padrao do projeto)
      (if (not par) (setq par (ETQ:_PadraoDe en nome)))
      (if (and (not par) (equal up "TC"))
        (setq par (cons "TC" (OBJ:_Val "MIN" (OBJ:GrupoDe en "TC"))))
      )
      (if par (ETQ:_Fmt (cdr par)) nil)
    )
  )
)

;; modelo padrao do tipo: o configurado (HYDRO.ETIQUETA.MODELO.<tipo>) ou o de fabrica
(defun ETQ:ModeloPadrao (id / cfg)
  (setq cfg (if id (HYDRO:Get (strcat "HYDRO.ETIQUETA.MODELO." id) nil) nil))
  (cond
    (cfg cfg)
    ((equal id "bacia")
      "{NOME}\\PA = {AREA} ha   tc = {TC} min\\PC = {C}   CN = {CN}\\PQp = {QP} m3/s  (TR {TR})")
    (T
      "{NOME}\\PQ = {E.QP} m3/s   tc = {E.TC} min\\PLamina = {H.LAMINA} m   V = {H.VELOCIDADE} m/s")
  )
)

;; texto de uma etiqueta: relatorio (FIXO) ou modelo preenchido
(defun ETQ:TextoDe (en modo modelo)
  (if (equal modo "FIXO")
    (HYDRO:Join (OBJ:Resumo en) "\\P")
    (ETQ:Substitui (if modelo modelo (ETQ:ModeloPadrao (OBJ:TipoDe en)))
                   (function (lambda (n) (ETQ:Campo en n))))
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

;; Cria a etiqueta do objeto `alvo` em pt (UCS). modo "FIXO" ou "MODELO".
;; Retorna o ename ou nil.
(defun ETQ:CriaEtiqueta (alvo pt modo modelo altura / en)
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
                (cons "MODELO" modelo))))
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
      (setq txt (ETQ:TextoDe en (cdr (assoc "MODO" reg)) (cdr (assoc "MODELO" reg))))
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
  '("Nome" "Tipo" "A (ha)" "L (m)" "S (m/m)" "Atributos" "TR (anos)"
    "Q entrada (m3/s)" "Q saida (m3/s)" "tc (min)" "Destino")
)

(defun ETQ:_S (x)
  (if x x "-")
)

;; linha da tabela (lista de strings, uma por coluna) para o objeto
(defun ETQ:LinhaTabela (en / dest atr p)
  (setq dest (if (HYDRO:Has "ligacao") (LIG:Destino en) nil))
  (foreach p (OBJ:AtribDe en)
    (setq atr (append atr (list (strcat (car p) "=" (ETQ:_Fmt (cdr p))))))
  )
  (list
    (OBJ:Nome en)
    (OBJ:_NomeTipo (OBJ:TipoDe en))
    (ETQ:_S (ETQ:Campo en "AREA"))
    (ETQ:_S (ETQ:Campo en "COMP"))
    (ETQ:_S (ETQ:Campo en "DECL"))
    (if atr (HYDRO:Join atr " ") "-")
    (ETQ:_S (ETQ:Campo en "TR"))
    (ETQ:_S (ETQ:Campo en "E.QP"))
    (ETQ:_S (ETQ:Campo en "QP"))
    (ETQ:_S (ETQ:Campo en "TC"))
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
      (ETQ:_Cel obj 0 0 "Objetos Hydro")
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

(HYDRO:On "bacia.calculada" "etiqueta" 'ETQ:_OnEvento)
(HYDRO:On "objeto.calculado" "etiqueta" 'ETQ:_OnEvento)
(HYDRO:On "bacia.cadastrada" "etiqueta" 'ETQ:_OnEvento)
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
