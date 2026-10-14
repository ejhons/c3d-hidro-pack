;;; ============================================================
;;; models/escada.lsp - MODELO ESCADA HIDRAULICA (ESC:)
;;;
;;; Escada hidraulica (calha em degraus): objeto LINEAR como o tubo e a sarjeta (LINE,
;;; LWPOLYLINE ou POLYLINE 3D). So o ponto inicial, o final e o comprimento contam (desnivel e
;;; declividade); linha 2D (cotas iguais) nao tem declividade no desenho: ela e digitada
;;; (CARACT-DEFS; ESCADAEDITA). A largura da calha vem da SECCAO do catalogo de tubo/canal
;;; (plugins/secao_tubo.lsp; SECAOTUBO): hoje so seccao RETANGULAR.
;;;
;;; O QUE ESTE MODEL CALCULA (so o que e consenso; sem equacoes de regime por enquanto)
;;;   GEOMETRIA   NDEG = ceil(desnivel / h), com h a altura MAXIMA do degrau (ATRIB DEGRAU);
;;;               altura real do degrau hr = desnivel / NDEG; comprimento horizontal
;;;               Lh = sqrt(COMP^2 - desnivel^2); piso l = Lh / NDEG; inclinacao teta =
;;;               atan(hr / l). (COMP e o comprimento da curva, 3D numa polilinha 3D.)
;;;   ALTURA CRITICA em calha retangular:  yc = (q^2 / g)^(1/3),  q = Q / b,  g = 9.81
;;;               (Chow, Open-Channel Hydraulics, 1959). Razao yc/hr (entra nos criterios de
;;;               regime da literatura de vertedouros em degraus).
;;; O QUE FICA PARA OS METODOS (catalogo "metodo-escada"; a BRECHA para equacoes)
;;;   regime do escoamento (quedas sucessivas / transicao / deslizante sobre turbilhoes),
;;;   altura da lamina e velocidade ao longo da escada, energia residual no pe, dissipacao,
;;;   tempo de percurso. Um metodo e um arquivo novo: (HYDRO:RegAdd "metodo-escada" id (list
;;;   ("NOME" . ..) ("DESC" . ..) ("FN" . 'funcao))); o ATRIB METODO-ESCADA do objeto escolhe.
;;;   (fn ctx) -> GRUPOS ((grupo . campos) ...) ou (("ERRO" . msg)); ctx = ("Q" ..) ("B" . largura)
;;;   ("YC" ..) ("H" . altura real do degrau) ("L" . piso) ("NDEG" ..) ("TETA" . graus)
;;;   ("YC-H" . yc/hr) ("DESNIVEL" ..) ("COMP" ..) ("CENARIO" ..) ("ENTRADA" ("QP" ..) ("TC" ..)).
;;;   Um grupo "PERCURSO" ("VALOR" . min) devolvido pelo metodo define o tempo proprio (o core de
;;;   ligacao soma ao maior tc dos montantes); sem ele o percurso e 0. Um grupo "AVISOS" do metodo
;;;   se junta ao da escada. Metodo incluido: "siscooh" (registry/escada_siscooh.lsp; regime,
;;;   energia residual e estado final; docs/referencia-escadas-hidraulicas-siscooh.md). O metodo
;;;   tambem pode devolver ALTURA_LAMINA, VELOCIDADE e FROUDE (estado final): a jusante, uma
;;;   estrutura dissipadora os le como montante.
;;;
;;; ESTRUTURA DO ARQUIVO (padrao dos models; ver .claude/skills/hydro-model)
;;;   1. UTILITARIOS
;;;   2. GEOMETRIA (CARACTERIZACAO)
;;;   3. LER, GRAVAR, EDITAR, REMOVER
;;;   4. CAMPOS (CARACT, PARAMS e ATRIB)
;;;   5. RESULTADOS (RESULT)
;;;   6. CALCULOS
;;;   7. RESUMO E FORMATACAO
;;;   8. TIPO NO CATALOGO
;;;   9. COMANDOS E INTERACAO (ESCADACAD, ESCADAEDITA, ESCADAS, ESCADAINFO, ESCADAZOOM) e AUDITORIA
;;;   toString: ESC:ToString (secao 7), tambem a capacidade "TOSTRING" do tipo
;;;
;;; REGISTRO (formato padrao, docs/arquitetura.md secao 18)
;;;   ATRIB   SECAO          id da seccao RETANGULAR do catalogo de tubo/canal
;;;           DEGRAU         altura MAXIMA do degrau h (m, > 0)
;;;           METODO-ESCADA  metodo do catalogo "metodo-escada" ("nenhum" = so geometria e yc)
;;;   CARACT  COMP, DECL (e COTA-INI, COTA-FIM, DESNIVEL) do desenho ou digitados (CARACT-DEFS)
;;;   RESULT  por CENARIO; o core grava ENTRADA e VAZAO. Grupos da escada:
;;;           ALTURA_CRITICA ("VALOR" . m) ("METODO" . "retangular")
;;;           DEGRAUS ("VALOR" . NDEG) ("ALTURA" . m) ("PISO" . m) ("INCLINACAO" . graus)
;;;           YC_H ("VALOR" . yc/hr)    AVISOS ("VALOR" . lista)    + o que o metodo devolver
;;; ============================================================
(vl-load-com)


;;; ------------------------------------------------------------
;;; 1. UTILITARIOS
;;; ------------------------------------------------------------
(defun ESC:_Erro (msg)
  (list (cons "ERRO" msg))
)


;;; ------------------------------------------------------------
;;; 2. GEOMETRIA (CARACTERIZACAO)
;;; ------------------------------------------------------------
;; comprimento da entidade (m), ou nil
(defun ESC:_Comprimento (en / r)
  (setq r
    (vl-catch-all-apply
      (function
        (lambda ()
          (vlax-curve-getDistAtParam en (vlax-curve-getEndParam en))))
      nil))
  (if (vl-catch-all-error-p r) nil r)
)

;; cota (Z) do ponto inicial (fim = nil) ou final (fim = T), ou nil
(defun ESC:_Cota (en fim / p)
  (setq p
    (vl-catch-all-apply
      (function
        (lambda ()
          (if fim (vlax-curve-getEndPoint en) (vlax-curve-getStartPoint en))))
      nil))
  (if (or (vl-catch-all-error-p p) (null p)) nil (caddr p))
)

;; (puro) declividade |z1 - z2| / comp; nil se falta dado, comp <= 0 ou cotas iguais
(defun ESC:_Decl (comp z1 z2)
  (if (and comp z1 z2 (> comp 0.0) (> (abs (- z1 z2)) 1e-9))
    (/ (abs (- z1 z2)) comp)
    nil
  )
)

;; CARACT do desenho: COMP e, se as cotas diferem, DECL, COTA-INI, COTA-FIM e DESNIVEL (m).
;; vinculos: a escada nao tem. O que nao der para ler nao entra (o cadastro pergunta).
(defun ESC:Caracterizar (en vinculos / comp z1 z2 decl)
  (setq comp (ESC:_Comprimento en))
  (setq z1 (ESC:_Cota en nil))
  (setq z2 (ESC:_Cota en T))
  (setq decl (ESC:_Decl comp z1 z2))
  (OBJ:Limpa
    (list
      (cons "COMP" (if (and comp (> comp 0.0)) comp nil))
      (cons "DECL" decl)
      (cons "COTA-INI" (if decl z1 nil))
      (cons "COTA-FIM" (if decl z2 nil))
      (cons "DESNIVEL" (if decl (abs (- z1 z2)) nil))
    )
  )
)


;;; ------------------------------------------------------------
;;; 3. LER, GRAVAR, EDITAR, REMOVER
;;; ------------------------------------------------------------
;; HERDA a porta de armazenamento da classe base (objetos.lsp): ler OBJ:Ler/OBJ:Registro,
;; gravar OBJ:GravaRegistro, cadastro generico (OBJ:CadastrarCom; ESCADACAD) e um campo
;; (ESCADAEDITA), remover OBJ:Remover. Nada proprio a declarar.


;;; ------------------------------------------------------------
;;; 4. CAMPOS (CARACT, PARAMS e ATRIB)
;;; ------------------------------------------------------------
;; ids dos metodos de escada cadastrados, precedidos de "nenhum" (opcoes dinamicas)
(defun ESC:_IdsMetodo ()
  (cons "nenhum" (mapcar 'car (HYDRO:RegList "metodo-escada")))
)

;; ATRIB (o usuario define): (chave rotulo padrao unidade [tipo [opcoes]])
(defun ESC:_AtribDefs ()
  (list
    (list "SECAO" "Id da secao RETANGULAR (SECAOTUBO)" 0 "" "int")
    (list "DEGRAU" "Altura maxima do degrau h" 0.0 "m")
    (list "METODO-ESCADA" "Metodo de regime/dissipacao" "nenhum" "" "opcoes" 'ESC:_IdsMetodo)
  )
)

;; CARACT-DEFS: o que se digita quando o desenho nao informa
(defun ESC:_CaractDefs ()
  (list
    (list "COMP" "Comprimento" 0.0 "m")
    (list "DECL" "Declividade" 0.0 "m/m")
  )
)

;; PADROES de ATRIB: a seccao atual do catalogo de tubo/canal
(defun ESC:_Padroes (en)
  (if (HYDRO:Has "secao-tubo")
    (list (cons "SECAO" (STB:SecaoAtualId)))
    nil
  )
)

;; seccao (id ("k" . v) ...) do catalogo de tubo/canal pelo id, ou nil
(defun ESC:_Secao (id)
  (if (and id (HYDRO:Has "secao-tubo")) (STB:PorId id) nil)
)

;; (puro) desnivel (m) do CARACT: o gravado, ou DECL x COMP se so esses foram digitados
(defun ESC:_Desnivel (cr)
  (cond
    ((cdr (assoc "DESNIVEL" cr)))
    ((and (cdr (assoc "DECL" cr)) (cdr (assoc "COMP" cr)))
      (* (cdr (assoc "DECL" cr)) (cdr (assoc "COMP" cr))))
    (T nil)
  )
)


;;; ------------------------------------------------------------
;;; 5. RESULTADOS (RESULT)
;;; ------------------------------------------------------------
;; "VALOR" de um grupo do cenario (ou nil); para AVISOS, a lista de textos
(defun ESC:_V (en cenario grupo)
  (HYDRO:Val "VALOR" (OBJ:ResultGrupoDe en cenario grupo))
)


;;; ------------------------------------------------------------
;;; 6. CALCULOS
;;; ------------------------------------------------------------
;; (puro) altura critica em calha retangular: yc = (q^2/g)^(1/3), q = Q/b. nil se Q ou b <= 0
(defun ESC:AlturaCritica (q b)
  (if (and q b (> q 0.0) (> b 0.0))
    (expt (/ (* (/ q b) (/ q b)) 9.81) (/ 1.0 3.0))
    nil
  )
)

;; (puro) geometria dos degraus.
;;   dz : desnivel (m, > 0); h : altura MAXIMA do degrau (m, > 0); comp : comprimento (m)
;;   retorno: (("NDEG" . n) ("ALTURA" . hr) ("PISO" . l) ("TETA" . graus) ("LH" . m)) ou (("ERRO" . msg))
(defun ESC:Degraus (dz h comp / n nd hr lh l)
  (cond
    ((or (not dz) (<= dz 0.0)) (ESC:_Erro "Desnivel ausente ou nulo."))
    ((or (not h) (<= h 0.0)) (ESC:_Erro "Informe a altura do degrau (ESCADAEDITA)."))
    ((or (not comp) (<= comp dz)) (ESC:_Erro "Comprimento menor ou igual ao desnivel: geometria impossivel."))
    (T
      (setq n (/ dz h))
      ;; numero inteiro de degraus, com tolerancia para 10.000000000000002
      (setq nd (if (< (- n (fix n)) 1e-6) (fix n) (1+ (fix n))))
      (if (< nd 1) (setq nd 1))
      (setq hr (/ dz nd))
      (setq lh (sqrt (- (* comp comp) (* dz dz))))
      (setq l (/ lh nd))
      (list (cons "NDEG" nd) (cons "ALTURA" hr) (cons "PISO" l)
            (cons "TETA" (* (/ 180.0 pi) (atan (/ hr l)))) (cons "LH" lh))
    )
  )
)

;; Capacidade CALCULA: devolve GRUPOS ((grupo . campos) ...) ou (("ERRO" . msg)). Quem grava
;; e LIG:CalcularCore (junto com ENTRADA e VAZAO).
(defun ESC:Calcular (en ctx params /
                     dados id sec h mid m q cr comp dz b d yc razao grupos r ctx2 avisos)
  (setq dados (OBJ:AtribDe en))
  (setq id (cdr (assoc "SECAO" dados)))
  (setq sec (ESC:_Secao id))
  (setq h (cdr (assoc "DEGRAU" dados)))
  (setq mid (cdr (assoc "METODO-ESCADA" dados)))
  (setq q (cdr (assoc "QP" (cdr (assoc "ENTRADA" ctx)))))
  (setq cr (OBJ:CaractDe en))
  (setq comp (cdr (assoc "COMP" cr)))
  (setq dz (ESC:_Desnivel cr))
  (cond
    ((not (HYDRO:Has "secao-tubo"))
      (ESC:_Erro "Plugin do catalogo de secoes de tubo/canal (secao_tubo.lsp) nao carregado."))
    ((not sec)
      (ESC:_Erro
        (strcat "Secao " (if id (itoa id) "?")
                " nao cadastrada. Edite o objeto (ESCADAEDITA) ou crie a secao (CRIASECAOTUBO).")))
    ((not (equal (STB:Val "forma" sec) "retangular"))
      (ESC:_Erro "A escada exige secao RETANGULAR (a largura da calha)."))
    ((or (not q) (<= q 0.0))
      (ESC:_Erro "Nao ha vazao afluente: ligue bacias ou outros objetos calculados a esta escada (LIGAR)."))
    (T
      (setq b (STB:Val "b" sec))
      (setq d (ESC:Degraus dz h comp))
      (if (assoc "ERRO" d)
        d
        (progn
          (setq yc (ESC:AlturaCritica q b))
          (setq razao (/ yc (cdr (assoc "ALTURA" d))))
          (setq grupos
            (list
              (cons "ALTURA_CRITICA" (list (cons "VALOR" yc) (cons "METODO" "retangular")))
              (cons "DEGRAUS"
                (list (cons "VALOR" (cdr (assoc "NDEG" d)))
                      (cons "ALTURA" (cdr (assoc "ALTURA" d)))
                      (cons "PISO" (cdr (assoc "PISO" d)))
                      (cons "INCLINACAO" (cdr (assoc "TETA" d)))))
              (cons "YC_H" (list (cons "VALOR" razao)))))
          ;; metodo por equacao (brecha): arquivo novo cadastra no catalogo "metodo-escada"
          (if (and mid (/= mid "nenhum"))
            (progn
              (setq m (HYDRO:RegGet "metodo-escada" mid))
              (if m
                (progn
                  (setq ctx2
                    (append
                      (list (cons "Q" q) (cons "B" b) (cons "YC" yc)
                            (cons "H" (cdr (assoc "ALTURA" d))) (cons "L" (cdr (assoc "PISO" d)))
                            (cons "NDEG" (cdr (assoc "NDEG" d))) (cons "TETA" (cdr (assoc "TETA" d)))
                            (cons "YC-H" razao) (cons "DESNIVEL" dz) (cons "COMP" comp))
                      ctx))
                  (setq r (apply (cdr (assoc "FN" m)) (list ctx2)))
                  (if (assoc "ERRO" r)
                    (setq grupos r)
                    (progn
                      ;; os AVISOS do metodo se juntam aos da escada (um grupo AVISOS so)
                      (setq grupos (append grupos (vl-remove (assoc "AVISOS" r) r)))
                      (setq avisos (append avisos (HYDRO:Val "VALOR" (cdr (assoc "AVISOS" r)))))
                    )
                  )
                )
                (setq avisos
                  (list (strcat "metodo de escada nao cadastrado: " mid " (so a geometria e yc foram calculados)")))
              )
            )
          )
          (if (assoc "ERRO" grupos)
            grupos
            (append grupos (list (cons "AVISOS" (list (cons "VALOR" avisos)))))
          )
        )
      )
    )
  )
)


;;; ------------------------------------------------------------
;;; 7. RESUMO E FORMATACAO (linhas de texto; quem desenha e a view)
;;; ------------------------------------------------------------
;; linhas do resultado de um cenario (capacidade FORMATA: (fn en cenario))
(defun ESC:Formata (en cenario / g linhas av)
  (setq g (OBJ:ResultGrupoDe en cenario "DEGRAUS"))
  (setq linhas
    (list
      (strcat "Q = " (rtos (ESC:_V en cenario "VAZAO") 2 3) " m3/s   altura critica yc = "
              (rtos (ESC:_V en cenario "ALTURA_CRITICA") 2 3) " m   yc/h = "
              (rtos (ESC:_V en cenario "YC_H") 2 2))
      (strcat (itoa (HYDRO:Val "VALOR" g)) " degrau(s): altura "
              (rtos (HYDRO:Val "ALTURA" g) 2 3) " m   piso " (rtos (HYDRO:Val "PISO" g) 2 3)
              " m   inclinacao " (rtos (HYDRO:Val "INCLINACAO" g) 2 1) " graus")
    )
  )
  (foreach av (ESC:_V en cenario "AVISOS")
    (setq linhas (append linhas (list (strcat "ATENCAO: " av))))
  )
  linhas
)

(defun ESC:Resumo (en / dados id sec linhas cr c)
  (setq dados (OBJ:AtribDe en))
  (setq id (cdr (assoc "SECAO" dados)))
  (setq sec (ESC:_Secao id))
  (setq cr (OBJ:CaractDe en))
  (setq linhas
    (list
      (strcat "Escada hidraulica: " (OBJ:Nome en))
      (strcat "Handle: " (HYDRO:Handle en))
      (if sec
        (STB:Rotulo sec)
        (strcat "Secao " (if id (itoa id) "?") " (nao cadastrada)"))
      (strcat "Degrau maximo h = " (if (cdr (assoc "DEGRAU" dados)) (rtos (cdr (assoc "DEGRAU" dados)) 2 3) "?")
              " m   metodo: " (if (cdr (assoc "METODO-ESCADA" dados)) (cdr (assoc "METODO-ESCADA" dados)) "nenhum"))
      (if (and (assoc "COMP" cr) (assoc "DECL" cr))
        (strcat "L = " (rtos (cdr (assoc "COMP" cr)) 2 1) " m   S = "
                (rtos (cdr (assoc "DECL" cr)) 2 4) " m/m"
                (if (member "DECL" (cdr (assoc "MANUAL" cr))) "  (manual)" ""))
        "Geometria indisponivel (use ESCADAEDITA para digitar comprimento/declividade)")
      (strcat "Afluentes: " (itoa (length (LIG:Afluentes en))))
    )
  )
  (foreach c (OBJ:CenariosDe en)
    (if (ESC:_V en c "ALTURA_CRITICA")
      (setq linhas
        (append linhas
          (list
            (strcat "Cenario " c (if (OBJ:Obsoleto en c) " (DESATUALIZADO)" "")
                    ":  yc = " (rtos (ESC:_V en c "ALTURA_CRITICA") 2 3) " m   "
                    (itoa (ESC:_V en c "DEGRAUS")) " degrau(s)")))
      )
    )
  )
  linhas
)

;; toString da escada: texto multilinha. Capacidade "TOSTRING" do tipo.
(defun ESC:ToString (en)
  (HYDRO:Join (ESC:Resumo en) "\n")
)


;;; ------------------------------------------------------------
;;; 8. TIPO NO CATALOGO (declaracao)
;;; ------------------------------------------------------------
(if (HYDRO:Has "objetos")
  (OBJ:RegistrarTipo
    "escada"
    "Escada hidraulica"
    "Calha em degraus (linha ou polilinha 3D): geometria dos degraus e altura critica; regime por metodo."
    '("LINE" "LWPOLYLINE" "POLYLINE")
    (ESC:_AtribDefs)
    T
    T
    (list
      (cons "CARACTERIZA" 'ESC:Caracterizar)
      (cons "CARACT-DEFS" (ESC:_CaractDefs))
      (cons "PADROES" 'ESC:_Padroes)
      (cons "RESUMO" 'ESC:Resumo)
      (cons "TOSTRING" 'ESC:ToString)
      (cons "CALCULA" 'ESC:Calcular)
      (cons "TEMPO-MODO" "percurso")
      (cons "FORMATA" 'ESC:Formata)
    )
  )
)


;;; ------------------------------------------------------------
;;; 9. COMANDOS E INTERACAO (linha de comando)
;;; ------------------------------------------------------------
;; Comandos padrao do objeto (docs/arquitetura.md secao 18b): fluxos genericos de
;; views/objetos_padrao_view.lsp. Calculo e ligacoes: CALCULAOBJETO e LIGAR. A seccao vem do
;; catalogo de tubo/canal (CRIASECAOTUBO, SECAOTUBO).
(defun ESC:_Padrao (fn)
  (if (HYDRO:Has "objetos-padrao-view")
    (apply fn (list "escada"))
    (alert "Comandos de objeto indisponiveis: carregue objetos_padrao e a view dele.")
  )
  (princ)
)

(defun c:ESCADACAD ()   (ESC:_Padrao 'OPV:Cadastrar))
(defun c:ESCADAEDITA () (ESC:_Padrao 'OPV:EditaCampo))
(defun c:ESCADAS ()     (ESC:_Padrao 'OPV:Listar))
(defun c:ESCADAINFO ()  (ESC:_Padrao 'OPV:Info))
(defun c:ESCADAZOOM ()  (ESC:_Padrao 'OPV:Zoom))

;;; ------------------------------------------------------------
;;; AUDITORIA (catalogo "auditoria"; ver plugins/auditoria.lsp)
;;; ------------------------------------------------------------
;; problemas: ("SECAO-INVALIDA" ename id) - escada cuja seccao nao existe ou nao e retangular
(defun ESC:_AudSecao (/ out en id sec)
  (if (HYDRO:Has "secao-tubo")
    (foreach en (OBJ:ListaTipo "escada")
      (setq id (cdr (assoc "SECAO" (OBJ:AtribDe en))))
      (setq sec (ESC:_Secao id))
      (if (and id (or (not sec) (not (equal (STB:Val "forma" sec) "retangular"))))
        (setq out (append out (list (list "SECAO-INVALIDA" en id))))
      )
    )
  )
  out
)

(defun ESC:_TxtSecao (p)
  (strcat "Escada " (OBJ:Nome (nth 1 p)) " usa a secao " (itoa (nth 2 p))
          ", que nao esta cadastrada ou nao e retangular")
)

;; Pergunta UMA seccao retangular existente para todas as escadas com problema
(defun ESC:_ReparaSecao (problemas / secs idx id n p en)
  (setq secs
    (vl-remove-if-not
      (function (lambda (s) (equal (STB:Val "forma" s) "retangular")))
      (STB:Secoes)))
  (if secs
    (progn
      (setq idx
        (HYDRO:Escolher
          (strcat "Secao retangular a usar nas " (itoa (length problemas)) " escada(s):")
          (mapcar 'STB:Rotulo secs)
          0))
      (setq id (car (nth idx secs)))
      (setq n 0)
      (foreach p problemas
        (setq en (nth 1 p))
        (if (OBJ:CadastrarCom en "escada" (OBJ:SetChave (OBJ:AtribDe en) "SECAO" id)
              (OBJ:NomeGravado en) nil nil)
          (setq n (1+ n))
        )
      )
      (if (> n 0)
        (princ "\nRode CALCULAOBJETO nessas escadas: os resultados antigos usaram outra secao.")
      )
      n
    )
    (progn (princ "\nNao ha secao retangular cadastrada (CRIASECAOTUBO).") 0)
  )
)

(HYDRO:RegAdd "auditoria" "secao-escada"
  (list (cons "NOME" "Secao das escadas hidraulicas")
        (cons "VERIFICA" 'ESC:_AudSecao)
        (cons "TEXTO" 'ESC:_TxtSecao)
        (cons "REPARA" 'ESC:_ReparaSecao)))

(HYDRO:Provide "escada-obj" "1.0")
(princ)
