;;; ============================================================
;;; models/sarjeta.lsp - MODELO SARJETA (SOB:)
;;;
;;; Representa a sarjeta no sistema: comprimento, declividade e secao; calcula
;;; lamina, largura inundada, area molhada e velocidade (Izzard). Uma sarjeta
;;; e um OBJETO QUE RECEBE BACIAS: a mesma polilinha que e o talvegue de uma
;;; bacia pode ser cadastrada como sarjeta (comando OBJETO); as bacias sao
;;; ligadas a ela com LIGAR. So a funcionalidade do objeto fica aqui; comandos
;;; e texto no desenho do fluxo antigo estao em plugins/sarjetas.lsp.
;;;
;;; ESTRUTURA DO ARQUIVO (padrao dos models; ver .claude/skills/hydro-model)
;;;   1. UTILITARIOS
;;;   2. GEOMETRIA (CARACTERIZACAO)
;;;   3. LER, GRAVAR, EDITAR, REMOVER
;;;   4. CAMPOS (CARACT, PARAMS, ATRIB)
;;;   5. RESULTADOS (RESULT)
;;;   6. CALCULOS
;;;   7. RESUMO E FORMATACAO
;;;   8. TIPO NO CATALOGO
;;;   9. COMANDOS E INTERACAO (SARJETACAD, SARJETAS, SARJETAINFO, SARJETAZOOM) e AUDITORIA
;;;   toString: SOB:ToString (secao 7), tambem a capacidade "TOSTRING" do tipo
;;;
;;; REGISTRO (formato padrao, docs/arquitetura.md secao 18)
;;;   ATRIB   SECAO  id de uma secao cadastrada (CRIASECAO)
;;;           N      rugosidade de Manning (0 = usar a da secao)
;;;   CARACT  COMP, DECL   obtidos do desenho (capacidade CARACTERIZA)
;;;   RESULT  grupos com nome; os campos calculados ficam planos na entrada:
;;;           VAZAO      (("METODO" ..) ("TR" ..) ("QP" . m3/s) ("AREA" . m2))
;;;                      vazao afluente (soma dos picos das bacias a montante)
;;;           HIDRAULICA (("METODO" ..) ("TR" ..) ("PARAMS" ..) ("Q" ..) ("TC-ENTRADA" . min)
;;;                       ("PERCURSO" . min) ("SECAO-ID" ..)
;;;                       ("N" ..) ("COMP" ..) ("DECL" ..) ("LAMINA" . m)
;;;                       ("LARGURA" . m) ("AREA-MOLHADA" . m2) ("VELOCIDADE" . m/s)
;;;                       ("AVISOS" . lista))
;;;
;;; SECOES (catalogo HYDRO.SECOES; secao = (id ("h" . m) ("s" . %) ("w" . m) ("n" . manning)))
;;; CALCULO (comando CALCULAOBJETO)
;;;   MONTANTE (PARAMS; ligacao.lsp) pode ter bacias E outras sarjetas. A sarjeta e um
;;;   mecanismo ENTRADA -> SAIDA e PRECISA de montante:
;;;     ENTRADA  Q = soma das saidas dos montantes; tc = maior tempo de saida. Sao os
;;;              parametros de entrada do dimensionamento/verificacao (Izzard abaixo).
;;;     tp       percurso = COMP / VELOCIDADE (min), da hidraulica com a Q de entrada
;;;     SAIDA    tc = tc de entrada + tp (modo "percurso"); Q = bacias a montante
;;;              reavaliadas nesse tc maximo, e com a flag geral HYDRO.VAZAO.PRESERVA
;;;              max(Q entrada, Q calculada). Gravada em VAZAO; a entrada em ENTRADA.
;;;   Por isso as sarjetas devem ser calculadas de montante para jusante, com o mesmo
;;;   METODO e TR.
;;;   Izzard: Q = 0.375 (z/n) y^(8/3) S^0.5, z = 100 / caimento(%)
;;;   avisa se a lamina passa do meio-fio ou a largura da secao.
;;; ============================================================
(vl-load-com)


;;; ------------------------------------------------------------
;;; 1. UTILITARIOS
;;; ------------------------------------------------------------
(defun SOB:_Erro (msg)
  (list (cons "ERRO" msg))
)


;;; ------------------------------------------------------------
;;; 2. GEOMETRIA (CARACTERIZACAO)
;;; ------------------------------------------------------------
;; A superficie e guardada pelo HANDLE (sobrevive ao salvar/reabrir o DWG)
(defun SOB:Superficie (/ h)
  (setq h (HYDRO:Get "HYDRO.SURFACE.HANDLE" nil))
  (if h (handent h) nil)
)

(defun SOB:_Comprimento (en / r)
  (setq r
    (vl-catch-all-apply
      (function
        (lambda ()
          (vlax-curve-getDistAtParam en (vlax-curve-getEndParam en))
        )
      )
      nil
    )
  )
  (if (vl-catch-all-error-p r) nil r)
)

(defun SOB:_ElevSuperficie (surf pt / r)
  (setq r
    (vl-catch-all-apply
      'vlax-invoke-method
      (list (vlax-ename->vla-object surf) 'FindElevationAtXY (car pt) (cadr pt))
    )
  )
  (if (vl-catch-all-error-p r) nil r)
)

;; Desnivel entre inicio e fim da polilinha.
;; Com superficie: cotas lidas da superficie. Sem: cotas da propria
;; polilinha (util para polilinhas 3D).
(defun SOB:_Desnivel (en surf / p1 p2 z1 z2)
  (setq p1 (vlax-curve-getStartPoint en))
  (setq p2 (vlax-curve-getEndPoint en))
  (if surf
    (setq z1 (SOB:_ElevSuperficie surf p1)
          z2 (SOB:_ElevSuperficie surf p2))
    (setq z1 (caddr p1)
          z2 (caddr p2))
  )
  (if (and z1 z2) (- z2 z1) nil)
)

;; (declividade . comprimento) da polilinha, ou nil
(defun SOB:_Geometria (en / comp desn)
  (setq comp (SOB:_Comprimento en))
  (setq desn (if comp (SOB:_Desnivel en (SOB:Superficie)) nil))
  (if (and comp desn (> comp 0.0))
    (cons (/ (abs desn) comp) comp)
    nil
  )
)

;; Caracteristicas obtidas do desenho (gravadas em CARACT ao cadastrar)
(defun SOB:Caracterizar (en / geo)
  (setq geo (SOB:_Geometria en))
  (if geo
    (list (cons "DECL" (car geo)) (cons "COMP" (cdr geo)))
    nil
  )
)


;;; ------------------------------------------------------------
;;; 3. LER, GRAVAR, EDITAR, REMOVER
;;; ------------------------------------------------------------
;; A sarjeta HERDA a porta de armazenamento da classe base (objetos.lsp):
;;   ler      OBJ:Ler / OBJ:Registro      gravar   OBJ:GravaRegistro
;;   editar   OBJ:Cadastrar (comando OBJETO; ATRIB e CARACT)
;;   remover  OBJ:Remover (emite "objeto.removido" antes de apagar)
;; Nada proprio a declarar: sem indice nem evento especiais. Se um dia precisar,
;; declare ("ARMAZENAMENTO" . ...) com as cinco operacoes na secao 8.


;;; ------------------------------------------------------------
;;; 4. CAMPOS (CARACT, PARAMS e ATRIB)
;;; ------------------------------------------------------------
;; Secao: (id ("h" . altura-meio-fio) ("s" . caimento %) ("w" . largura) ("n" . manning))
(defun SOB:_SecaoPadrao ()
  (list 0 (cons "h" 0.15) (cons "s" 3.0) (cons "w" 3.5) (cons "n" 0.013))
)

(defun SOB:Secoes ()
  (HYDRO:Get "HYDRO.SECOES" (list (SOB:_SecaoPadrao)))
)

(defun SOB:SecaoAtualId ()
  (HYDRO:Get "HYDRO.SECAO.ATUAL" 0)
)

(defun SOB:SecaoAtual ()
  (cdr (assoc (SOB:SecaoAtualId) (SOB:Secoes)))
)

;; secao cadastrada (alist h/s/w/n) pelo id, ou nil
(defun SOB:_Secao (id)
  (cdr (assoc id (SOB:Secoes)))
)

;; padroes de ATRIB na hora de cadastrar: a secao atual do plugin sarjetas
(defun SOB:_Padroes (en)
  (list (cons "SECAO" (SOB:SecaoAtualId)))
)

;; rugosidade efetiva: a do objeto (se > 0) ou a da secao
(defun SOB:_N (dados secao / n)
  (setq n (cdr (assoc "N" dados)))
  (if (and n (> n 0.0)) n (cdr (assoc "n" secao)))
)


;;; ------------------------------------------------------------
;;; 5. RESULTADOS (RESULT)
;;; ------------------------------------------------------------
;; entradas do grupo VAZAO (afluente) e HIDRAULICA (lamina, velocidade...)
(defun SOB:Vazao (en)       (OBJ:GrupoDe en "VAZAO"))

(defun SOB:Hidraulica (en)  (OBJ:GrupoDe en "HIDRAULICA"))

;;; ------------------------------------------------------------
;;; 6. CALCULOS
;;; ------------------------------------------------------------
;; Izzard: Q = 0.375 * (z/n) * y^(8/3) * S^0.5   ->   y
;; z = 100 / caimento(%)
(defun SOB:LaminaIzzard (q z n s)
  (expt (/ (* q n) (* 0.375 z (expt s 0.5))) (/ 3.0 8.0))
)

;; Devolve os campos de HIDRAULICA (planos) ou (("ERRO" . msg)).
;; Quem grava e o CALCULAOBJETO (OBJ:GravarResultado en "HIDRAULICA" ...).
(defun SOB:Calcular (en ctx params /
                     dados id sec q geo decl comp n h cai w z y larg am vel avisos tcin)
  (setq dados (OBJ:AtribDe en))
  (setq id (cdr (assoc "SECAO" dados)))
  (setq sec (if id (SOB:_Secao id) nil))
  (setq q (cdr (assoc "QP" (cdr (assoc "VAZAO" ctx)))))
  (setq tcin (cdr (assoc "TC" (cdr (assoc "VAZAO" ctx)))))
  (setq geo (SOB:_Geometria en))
  (setq decl (if geo (car geo) nil))
  (setq comp (if geo (cdr geo) nil))
  (cond
    ((not sec)
      (SOB:_Erro
        (strcat "Secao " (if id (itoa id) "?")
                " nao cadastrada. Edite o objeto (OBJETO) ou crie a secao (CRIASECAO)."))
    )
    ((or (not q) (<= q 0.0))
      (SOB:_Erro "Nao ha vazao afluente: ligue bacias ou sarjetas calculadas a esta sarjeta (LIGAR).")
    )
    ((or (not decl) (<= decl 0.0))
      (SOB:_Erro
        "Declividade nula. Defina a superficie (ATUALIZASUPERFICIE) ou use polilinha 3D.")
    )
    (T
      (setq n   (SOB:_N dados sec))
      (setq h   (cdr (assoc "h" sec)))
      (setq cai (cdr (assoc "s" sec)))
      (setq w   (cdr (assoc "w" sec)))
      (setq z   (/ 100.0 cai))
      (setq y   (SOB:LaminaIzzard q z n decl))
      (setq larg (* y z))
      (setq am  (/ (* y larg) 2.0))
      (setq vel (/ q am))
      (if (and h (> y h))
        (setq avisos (append avisos (list "lamina maior que a altura do meio-fio")))
      )
      (if (and w (> larg w))
        (setq avisos (append avisos (list "largura inundada maior que a largura da secao")))
      )
      (list
        (cons "Q" q)
        (cons "TC-ENTRADA" tcin)
        (cons "PERCURSO" (/ comp vel 60.0))
        (cons "SECAO-ID" id)
        (cons "N" n)
        (cons "COMP" comp)
        (cons "DECL" decl)
        (cons "LAMINA" y)
        (cons "LARGURA" larg)
        (cons "AREA-MOLHADA" am)
        (cons "VELOCIDADE" vel)
        (cons "AVISOS" avisos)
      )
    )
  )
)


;;; ------------------------------------------------------------
;;; 7. RESUMO E FORMATACAO (linhas de texto; quem desenha e a view)
;;; ------------------------------------------------------------
(defun SOB:Formata (res / linhas av)
  (setq linhas
    (list
      (strcat "Q = " (rtos (cdr (assoc "Q" res)) 2 3) " m3/s   "
              "Secao " (itoa (cdr (assoc "SECAO-ID" res)))
              "   n = " (rtos (cdr (assoc "N" res)) 2 4))
      (strcat "L = " (rtos (cdr (assoc "COMP" res)) 2 1) " m   "
              "S = " (rtos (cdr (assoc "DECL" res)) 2 4) " m/m")
      (strcat "Lamina: " (rtos (cdr (assoc "LAMINA" res)) 2 3) " m   "
              "Largura: " (rtos (cdr (assoc "LARGURA" res)) 2 2) " m")
      (strcat "Velocidade: " (rtos (cdr (assoc "VELOCIDADE" res)) 2 2) " m/s")
      (strcat "Percurso: " (rtos (cdr (assoc "PERCURSO" res)) 2 2) " min"
              (if (cdr (assoc "TC-ENTRADA" res))
                (strcat "   tc de chegada: " (rtos (cdr (assoc "TC-ENTRADA" res)) 2 1) " min")
                ""))
    )
  )
  (foreach av (cdr (assoc "AVISOS" res))
    (setq linhas (append linhas (list (strcat "ATENCAO: " av))))
  )
  linhas
)

(defun SOB:Resumo (en / dados id sec linhas geo r)
  (setq dados (OBJ:AtribDe en))
  (setq id (cdr (assoc "SECAO" dados)))
  (setq sec (if id (SOB:_Secao id) nil))
  (setq geo (SOB:_Geometria en))
  (setq linhas
    (list
      (strcat "Sarjeta: " (OBJ:Nome en))
      (strcat "Handle: " (HYDRO:Handle en))
      (if sec
        (strcat "Secao " (itoa id) ":  h = " (rtos (cdr (assoc "h" sec)) 2 3)
                " m   s = " (rtos (cdr (assoc "s" sec)) 2 2) " %   w = "
                (rtos (cdr (assoc "w" sec)) 2 3) " m   n = "
                (rtos (SOB:_N dados sec) 2 4))
        (strcat "Secao " (if id (itoa id) "?") " (nao cadastrada)")
      )
      (if geo
        (strcat "L = " (rtos (cdr geo) 2 1) " m   S = " (rtos (car geo) 2 4) " m/m")
        "Geometria indisponivel (declividade nula ou fora da superficie)"
      )
      (strcat "Afluentes: " (itoa (length (LIG:Afluentes en))))
    )
  )
  (foreach r (SOB:Hidraulica en)
    (setq linhas
      (append linhas
        (list
          (strcat "Calculo TR " (HYDRO:FmtReal (cdr (assoc "TR" r)))
                  ":  y = " (rtos (cdr (assoc "LAMINA" r)) 2 3)
                  " m   T = " (rtos (cdr (assoc "LARGURA" r)) 2 2) " m")))
    )
  )
  linhas
)

;; toString da sarjeta: texto multilinha (separador newline) com secao,
;; geometria, afluentes e calculos. Capacidade "TOSTRING" do tipo.
(defun SOB:ToString (en)
  (HYDRO:Join (SOB:Resumo en) "\n")
)


;;; ------------------------------------------------------------
;;; 8. TIPO NO CATALOGO (declaracao e rotulos)
;;; ------------------------------------------------------------
(HYDRO:SetLabel "HYDRO.SURFACE.HANDLE" "Superficie (handle)" "")
(HYDRO:SetLabel "HYDRO.SECOES" "Secoes de sarjeta cadastradas" "")
(HYDRO:SetLabel "HYDRO.SECAO.ATUAL" "Secao de sarjeta atual (id)" "")


(if (HYDRO:Has "objetos")
  (OBJ:RegistrarTipo
    ;;id
    "sarjeta"
    ; Nome
    "Sarjeta"
    ;Descrição:
    "Recebe bacias; tem secao e rugosidade. A mesma linha do talvegue pode ser a sarjeta."
    ; Aceita:
    '("LINE" "LWPOLYLINE" "POLYLINE" "SPLINE")
    ; Params
    (list (list "SECAO" "Id da secao" 0 "" "int")
          (list "N" "Rugosidade de Manning (0 = a da secao)" 0.0 ""))
    ; Recebe
    T
    ; Emite
    T
    ; Extras
    (list
      (cons "PADROES" 'SOB:_Padroes)
      (cons "CARACTERIZA" 'SOB:Caracterizar)
      (cons "RESUMO" 'SOB:Resumo)
      (cons "TOSTRING" 'SOB:ToString)
      (cons "CALCULA" 'SOB:Calcular)
      (cons "TEMPO-MODO" "percurso")
      (cons "FORMATA" 'SOB:Formata)
    )
  )
)

;;; ------------------------------------------------------------
;;; 9. COMANDOS E INTERACAO (linha de comando)
;;; ------------------------------------------------------------
;; Comandos padrao do objeto (docs/arquitetura.md secao 18b). Os fluxos sao os
;; genericos de views/objetos_padrao_view.lsp; aqui so se diz de que tipo e.
;; O calculo e as ligacoes usam os comandos genericos (CALCULAOBJETO, LIGAR...).
(defun SOB:_Padrao (fn)
  (if (HYDRO:Has "objetos-padrao-view")
    (apply fn (list "sarjeta"))
    (alert "Comandos de objeto indisponiveis: carregue objetos_padrao e a view dele.")
  )
  (princ)
)

(defun c:SARJETACAD ()  (SOB:_Padrao 'OPV:Cadastrar))
(defun c:SARJETAS ()    (SOB:_Padrao 'OPV:Listar))
(defun c:SARJETAINFO () (SOB:_Padrao 'OPV:Info))
(defun c:SARJETAZOOM () (SOB:_Padrao 'OPV:Zoom))

;;; ------------------------------------------------------------
;;; AUDITORIA (catalogo "auditoria"; ver plugins/auditoria.lsp)
;;; ------------------------------------------------------------
;; problemas: ("SECAO-INEXISTENTE" ename id) - sarjeta cuja secao nao esta cadastrada
(defun SOB:_AudSecao (/ out en id)
  (foreach en (OBJ:ListaTipo "sarjeta")
    (setq id (cdr (assoc "SECAO" (OBJ:AtribDe en))))
    (if (and id (not (SOB:_Secao id)))
      (setq out (append out (list (list "SECAO-INEXISTENTE" en id))))
    )
  )
  out
)

(defun SOB:_TxtSecao (p)
  (strcat "Sarjeta " (OBJ:Nome (nth 1 p)) " usa a secao " (itoa (nth 2 p))
          ", que nao esta cadastrada")
)

;; Pergunta UMA secao existente para todas as sarjetas com problema
(defun SOB:_ReparaSecao (problemas / secs idx id n p en)
  (setq secs (SOB:Secoes))
  (setq idx
    (HYDRO:Escolher
      (strcat "Secao a usar nas " (itoa (length problemas)) " sarjeta(s) com secao inexistente:")
      (mapcar
        (function
          (lambda (x)
            (strcat "Secao " (itoa (car x))
                    "  h=" (rtos (cdr (assoc "h" (cdr x))) 2 2)
                    "  s=" (rtos (cdr (assoc "s" (cdr x))) 2 1) "%"
                    "  w=" (rtos (cdr (assoc "w" (cdr x))) 2 2))))
        secs)
      0))
  (setq id (car (nth idx secs)))
  (setq n 0)
  (foreach p problemas
    (setq en (nth 1 p))
    (if (OBJ:Cadastrar en "sarjeta"
          (OBJ:_SetChave (OBJ:AtribDe en) "SECAO" id)
          (OBJ:NomeGravado en))
      (setq n (1+ n))
    )
  )
  (if (> n 0)
    (princ "
Rode CALCULAOBJETO nessas sarjetas: os resultados antigos usaram outra secao.")
  )
  n
)

(HYDRO:RegAdd "auditoria" "secao-sarjeta"
  (list (cons "NOME" "Secao das sarjetas")
        (cons "VERIFICA" 'SOB:_AudSecao)
        (cons "TEXTO" 'SOB:_TxtSecao)
        (cons "REPARA" 'SOB:_ReparaSecao)))

(HYDRO:Provide "sarjeta-obj" "2.0")
(princ)
