;;; ============================================================
;;; sarjetas.lsp - PLUGIN DE SARJETAS (SARJ:)
;;;
;;; Dependencias:
;;;   OBRIGATORIA : "precipitacao" (idf.lsp)  -> PREC:Intensidade
;;;   OPCIONAIS   : "persistencia" (via HYDRO:Get/Set)
;;;                 "xdata" (assina o evento "sarjeta.calculada")
;;;
;;; Estrutura:
;;;   - Funcoes SARJ:xxx    sao PURAS (recebem dados, devolvem dados)
;;;   - Funcoes SARJ:_xxx   sao internas
;;;   - Comandos c:xxx      fazem a interacao com o usuario
;;;   - Nenhuma variavel global. Configuracao em HYDRO:Get/Set:
;;;       HYDRO.RUNOFF  HYDRO.TC.MINIMO  HYDRO.TEXT.HEIGHT  HYDRO.TEXT.ROTATION
;;;       HYDRO.SURFACE.HANDLE  HYDRO.SECOES  HYDRO.SECAO.ATUAL
;;; ============================================================
(vl-load-com)

;;; ------------------------------------------------------------
;;; CONSTANTES (funcoes, nao variaveis)
;;; ------------------------------------------------------------
;; Secao: (id ("h" . altura-meio-fio) ("s" . caimento %) ("w" . largura) ("n" . manning))
(defun SARJ:_SecaoPadrao ()
  (list 0 (cons "h" 0.15) (cons "s" 3.0) (cons "w" 3.5) (cons "n" 0.013))
)

;; Casos do calculo multi-TR: (rotulo . TR em anos)
(defun SARJ:_TrsMulti ()
  (list (cons "SARJETA" 2.5) (cons "BLS" 5.0) (cons "REDE" 10.0))
)

;;; ------------------------------------------------------------
;;; CONFIGURACAO
;;; ------------------------------------------------------------
(defun SARJ:Runoff ()       (HYDRO:Get "HYDRO.RUNOFF" nil))
(defun SARJ:TcMinimo ()     (HYDRO:Get "HYDRO.TC.MINIMO" 10.0))
(defun SARJ:TextoAltura ()  (HYDRO:Get "HYDRO.TEXT.HEIGHT" 1.8))
(defun SARJ:TextoRotacao () (HYDRO:Get "HYDRO.TEXT.ROTATION" 0.0))

(defun SARJ:Secoes ()
  (HYDRO:Get "HYDRO.SECOES" (list (SARJ:_SecaoPadrao)))
)
(defun SARJ:SecaoAtualId ()
  (HYDRO:Get "HYDRO.SECAO.ATUAL" 0)
)
(defun SARJ:SecaoAtual ()
  (cdr (assoc (SARJ:SecaoAtualId) (SARJ:Secoes)))
)

;; A superficie e guardada pelo HANDLE (sobrevive ao salvar/reabrir o DWG)
(defun SARJ:Superficie (/ h)
  (setq h (HYDRO:Get "HYDRO.SURFACE.HANDLE" nil))
  (if h (handent h) nil)
)

;;; ------------------------------------------------------------
;;; GEOMETRIA (sem uso de COMMAND)
;;; ------------------------------------------------------------
(defun SARJ:_Area (en / r)
  (setq r (vl-catch-all-apply 'vla-get-area (list (vlax-ename->vla-object en))))
  (if (vl-catch-all-error-p r) nil r)
)

(defun SARJ:_Comprimento (en / r)
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

(defun SARJ:_ElevSuperficie (surf pt / r)
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
(defun SARJ:_Desnivel (en surf / p1 p2 z1 z2)
  (setq p1 (vlax-curve-getStartPoint en))
  (setq p2 (vlax-curve-getEndPoint en))
  (if surf
    (setq z1 (SARJ:_ElevSuperficie surf p1)
          z2 (SARJ:_ElevSuperficie surf p2))
    (setq z1 (caddr p1)
          z2 (caddr p2))
  )
  (if (and z1 z2) (- z2 z1) nil)
)

;;; ------------------------------------------------------------
;;; HIDROLOGIA E HIDRAULICA (funcoes puras)
;;; ------------------------------------------------------------
;; Kirpich: tc = 57 * (L^3 / H)^0.385   (L em km, H em m, tc em min)
;; comp em m, decl em m/m
(defun SARJ:TcKirpich (comp decl)
  (if (and comp decl (> comp 0.0) (> decl 0.0))
    (* 57.0
       (expt (/ (expt (/ comp 1000.0) 3.0) (* decl comp)) 0.385))
    nil
  )
)

;; Metodo racional: Q [m3/s] = C * i [mm/h] * A [ha] / 360
(defun SARJ:VazaoRacional (c i area_m2)
  (/ (* c i (/ area_m2 10000.0)) 360.0)
)

;; Izzard: Q = 0.375 * (z/n) * y^(8/3) * S^0.5   ->   y
;; z = 100 / caimento(%)
(defun SARJ:LaminaIzzard (q z n s)
  (expt (/ (* q n) (* 0.375 z (expt s 0.5))) (/ 3.0 8.0))
)

;;; ------------------------------------------------------------
;;; CALCULO PRINCIPAL (puro: nao pergunta nada, nao imprime nada)
;;; ------------------------------------------------------------
(defun SARJ:_Erro (msg)
  (list (cons "ERRO" msg))
)

;; casos = lista de (rotulo . tr)
;; Retorna alist de resultados ou (("ERRO" . "mensagem"))
(defun SARJ:Calcular
  (bacia talvegue casos /
   surf area comp desn decl tc secao h-mf cai larg-sec n z
   lista-casos caso i q q1 y larg am vel avisos)

  (setq surf  (SARJ:Superficie))
  (setq area  (SARJ:_Area bacia))
  (setq comp  (SARJ:_Comprimento talvegue))
  (setq desn  (if comp (SARJ:_Desnivel talvegue surf) nil))
  (setq secao (SARJ:SecaoAtual))
  (if (and comp desn (> comp 0.0))
    (setq decl (/ (abs desn) comp))
  )
  (if decl
    (setq tc (SARJ:TcKirpich comp decl))
  )

  (cond
    ((not area)
      (SARJ:_Erro "Nao foi possivel obter a area da bacia.")
    )
    ((not comp)
      (SARJ:_Erro "Nao foi possivel obter o comprimento do talvegue.")
    )
    ((not desn)
      (SARJ:_Erro "Nao foi possivel obter o desnivel (ponto fora da superficie?).")
    )
    ((not secao)
      (SARJ:_Erro "Secao atual inexistente. Use SELECIONASECAO ou CRIASECAO.")
    )
    ((not tc)
      (SARJ:_Erro
        "Declividade nula. Defina a superficie (ATUALIZASUPERFICIE) ou use polilinha 3D."
      )
    )
    (T
      (setq tc (max (SARJ:TcMinimo) tc))

      ;; intensidade e vazao de cada caso
      (foreach caso casos
        (setq i (PREC:Intensidade tc (cdr caso)))
        (setq q (if i (SARJ:VazaoRacional (SARJ:Runoff) i area) nil))
        (setq lista-casos
          (append lista-casos (list (list (car caso) (cdr caso) i q)))
        )
      )

      (if (or (not lista-casos)
              (vl-some (function (lambda (x) (not (nth 3 x)))) lista-casos))
        (SARJ:_Erro "Falha no calculo da intensidade/vazao (verifique IDF e runoff).")
        (progn
          ;; hidraulica da sarjeta com o PRIMEIRO caso
          (setq q1    (nth 3 (car lista-casos)))
          (setq h-mf  (cdr (assoc "h" secao)))
          (setq cai   (cdr (assoc "s" secao)))
          (setq larg-sec (cdr (assoc "w" secao)))
          (setq n     (cdr (assoc "n" secao)))
          (setq z     (/ 100.0 cai))
          (setq y     (SARJ:LaminaIzzard q1 z n decl))
          (setq larg  (* y z))
          (setq am    (/ (* y larg) 2.0))
          (setq vel   (/ q1 am))

          (if (and h-mf (> y h-mf))
            (setq avisos (append avisos (list "lamina maior que a altura do meio-fio")))
          )
          (if (and larg-sec (> larg larg-sec))
            (setq avisos (append avisos (list "largura inundada maior que a largura da secao")))
          )

          (list
            (cons "BACIA" bacia)
            (cons "TALVEGUE" talvegue)
            (cons "AREA" area)
            (cons "COMPRIMENTO" comp)
            (cons "DECLIVIDADE" decl)
            (cons "TC" tc)
            (cons "CASOS" lista-casos)
            (cons "Q" q1)
            (cons "LAMINA" y)
            (cons "LARGURA" larg)
            (cons "AREA-MOLHADA" am)
            (cons "VELOCIDADE" vel)
            (cons "SECAO" secao)
            (cons "SECAO-ID" (SARJ:SecaoAtualId))
            (cons "AVISOS" avisos)
          )
        )
      )
    )
  )
)

;;; ------------------------------------------------------------
;;; FORMATACAO DO RESULTADO
;;; ------------------------------------------------------------
;; sep = "\n" para alert/console, "\\P" para MTEXT
(defun SARJ:Formata (res sep / linhas caso primeiro av)
  (setq linhas
    (list
      (strcat "Area: " (rtos (HYDRO:Val "AREA" res) 2 0) " m2")
      (strcat "Comprimento: " (rtos (HYDRO:Val "COMPRIMENTO" res) 2 2) " m")
      (strcat "Declividade: " (rtos (HYDRO:Val "DECLIVIDADE" res) 2 4) " m/m")
      (strcat "Tempo de concentracao: " (rtos (HYDRO:Val "TC" res) 2 2) " min")
    )
  )
  (setq primeiro T)
  (foreach caso (HYDRO:Val "CASOS" res)
    (setq linhas
      (append
        linhas
        (list
          (strcat "[" (nth 0 caso) " - TR " (HYDRO:FmtNum (nth 1 caso)) "]")
          (strcat "Intensidade: " (rtos (nth 2 caso) 2 2) " mm/h")
          (strcat "Vazao: " (rtos (nth 3 caso) 2 3) " m3/s")
        )
      )
    )
    (if primeiro
      (setq linhas
        (append
          linhas
          (list
            (strcat "Lamina: " (rtos (HYDRO:Val "LAMINA" res) 2 3) " m")
            (strcat "Largura: " (rtos (HYDRO:Val "LARGURA" res) 2 2) " m")
            (strcat "Velocidade: " (rtos (HYDRO:Val "VELOCIDADE" res) 2 2) " m/s")
          )
        )
        primeiro nil
      )
    )
  )
  (foreach av (HYDRO:Val "AVISOS" res)
    (setq linhas (append linhas (list (strcat "ATENCAO: " av))))
  )
  (HYDRO:Join linhas sep)
)

;;; ------------------------------------------------------------
;;; INTERACAO COM O USUARIO
;;; ------------------------------------------------------------
(defun SARJ:_SelecionaLinha (msg / ss)
  (princ msg)
  (if (setq ss (ssget "_:S" '((0 . "LWPOLYLINE,POLYLINE,SPLINE"))))
    (ssname ss 0)
    nil
  )
)

(defun SARJ:_GarantirTr (/ tr)
  (setq tr (PREC:Tr))
  (if (not tr) (setq tr (PREC:AskTr)))
  tr
)

;; Garante IDF e runoff. Retorna T se esta tudo pronto.
(defun SARJ:_PreparaConfig (/ ok)
  (setq ok (HYDRO:Require "precipitacao"))
  (if (and ok (not (PREC:Params)))
    (PREC:AskParams)
  )
  (if (and ok (not (PREC:Params)))
    (progn (alert "Parametros IDF incompletos.") (setq ok nil))
  )
  (if (and ok (not (SARJ:Runoff)))
    (HYDRO:Set "HYDRO.RUNOFF" (getreal "\nDigite o runoff (coeficiente C): "))
  )
  (if (and ok (not (SARJ:Runoff)))
    (progn (alert "Runoff nao definido.") (setq ok nil))
  )
  ok
)

;; Seleciona, calcula, publica o evento e mostra. Retorna o resultado ou nil.
(defun SARJ:_Executar (casos / bacia talvegue res)
  (setq bacia (SARJ:_SelecionaLinha "\nSelecione a polilinha da BACIA: "))
  (if bacia
    (setq talvegue (SARJ:_SelecionaLinha "\nSelecione a polilinha do TALVEGUE: "))
  )
  (if (and bacia talvegue)
    (progn
      (setq res (SARJ:Calcular bacia talvegue casos))
      (if (assoc "ERRO" res)
        (progn
          (alert (strcat "Erro: " (HYDRO:Val "ERRO" res)))
          nil
        )
        (progn
          (HYDRO:Emit "sarjeta.calculada" res)
          (alert (SARJ:Formata res "\n"))
          res
        )
      )
    )
    nil
  )
)

(defun SARJ:_CmdSimples (/ tr)
  (if (and (SARJ:_PreparaConfig) (setq tr (SARJ:_GarantirTr)))
    (SARJ:_Executar (list (cons "SARJETA" tr)))
    nil
  )
)

(defun SARJ:_CmdMulti ()
  (if (SARJ:_PreparaConfig)
    (SARJ:_Executar (SARJ:_TrsMulti))
    nil
  )
)

;; MTEXT criado direto no banco de dados (sem COMMAND)
(defun SARJ:_InsereTexto (res / pt)
  (setq pt (getpoint "\nSelecione o local de insercao do texto: "))
  (if pt
    (entmakex
      (list
        '(0 . "MTEXT")
        '(100 . "AcDbEntity")
        '(100 . "AcDbMText")
        (cons 7 (getvar "TEXTSTYLE"))
        (cons 10 (trans pt 1 0))
        (cons 40 (SARJ:TextoAltura))
        (cons 41 0.0)
        (cons 71 1)
        (cons 50 (* (SARJ:TextoRotacao) (/ pi 180.0)))
        (cons 1 (SARJ:Formata res "\\P"))
      )
    )
  )
)

(defun SARJ:_Fmt (v)
  (if v (vl-prin1-to-string v) "(nao definido)")
)

(defun SARJ:_ListaIds (/ out s)
  (setq out "")
  (foreach s (SARJ:Secoes)
    (setq out (strcat out (if (= out "") "" ", ") (itoa (car s))))
  )
  out
)

;;; ------------------------------------------------------------
;;; COMANDOS
;;; ------------------------------------------------------------
(defun c:CALCULASARJETA ()
  (SARJ:_CmdSimples)
  (princ)
)

(defun c:CALCULASARJETAMULTITR ()
  (SARJ:_CmdMulti)
  (princ)
)

(defun c:CRIARSARJETARESULTADO (/ res)
  (if (setq res (SARJ:_CmdSimples))
    (SARJ:_InsereTexto res)
  )
  (princ)
)

(defun c:CRIARSARJETARESULTADOMULTITR (/ res)
  (if (setq res (SARJ:_CmdMulti))
    (SARJ:_InsereTexto res)
  )
  (princ)
)

(defun c:ATUALIZAROTACAOTEXTO ()
  (HYDRO:Set "HYDRO.TEXT.ROTATION"
    (HYDRO:AskReal "Rotacao do texto de resultado (graus)" (SARJ:TextoRotacao)))
  (princ)
)

(defun c:ATUALIZAALTURATEXTO (/ r)
  (setq r (HYDRO:AskReal "Altura do texto de resultado" (SARJ:TextoAltura)))
  (if (and r (> r 0.0))
    (HYDRO:Set "HYDRO.TEXT.HEIGHT" r)
    (princ "\nAltura invalida; valor anterior mantido.")
  )
  (princ)
)

(defun c:ATUALIZASUPERFICIE (/ ss)
  (princ "\nSelecione a superficie TIN (Enter para limpar): ")
  (setq ss (ssget "_:S" '((0 . "AECC_TIN_SURFACE"))))
  (if ss
    (progn
      (HYDRO:Set "HYDRO.SURFACE.HANDLE" (HYDRO:Handle (ssname ss 0)))
      (princ "\nSuperficie definida.")
    )
    (progn
      (HYDRO:Set "HYDRO.SURFACE.HANDLE" nil)
      (princ "\nSuperficie removida (sera usada a cota da polilinha).")
    )
  )
  (princ)
)

(defun c:ATUALIZARUNOFF ()
  (HYDRO:Set "HYDRO.RUNOFF"
    (HYDRO:AskReal "Digite o runoff (coeficiente C)" (SARJ:Runoff)))
  (princ)
)
;; nome antigo (com typo) mantido por compatibilidade
(defun c:ATUALIZARUNFOFF () (c:ATUALIZARUNOFF))

(defun c:SELECIONASECAO (/ id)
  (setq id
    (HYDRO:AskInt
      (strcat "Codigo da secao (existentes: " (SARJ:_ListaIds) ")")
      (SARJ:SecaoAtualId)
    )
  )
  (if (assoc id (SARJ:Secoes))
    (progn
      (HYDRO:Set "HYDRO.SECAO.ATUAL" id)
      (princ (strcat "\nSecao selecionada: " (itoa id)))
    )
    (princ "\nSecao inexistente.")
  )
  (princ)
)

(defun c:CRIASECAO (/ id h s w n secoes)
  (setq id (getint "\nSECAO - Digite o id (inteiro): "))
  (setq h  (getreal "\nSECAO - Digite a altura do meio-fio (m): "))
  (setq s  (getreal "\nSECAO - Digite o caimento transversal (%): "))
  (setq w  (getreal "\nSECAO - Digite a largura da secao (m): "))
  (setq n  (getreal "\nSECAO - Digite o coeficiente de Manning: "))
  (if (and id h s w n (> s 0.0) (> n 0.0))
    (progn
      (setq secoes (vl-remove (assoc id (SARJ:Secoes)) (SARJ:Secoes)))
      (HYDRO:Set "HYDRO.SECOES"
        (append secoes
                (list (list id (cons "h" h) (cons "s" s) (cons "w" w) (cons "n" n))))
      )
      (alert "Secao salva com sucesso.")
    )
    (alert "Dados invalidos; secao nao criada.")
  )
  (princ)
)

(defun c:PARAMETROSSARJETA (/ par msg)
  (setq par (if (HYDRO:Has "precipitacao") (PREC:Params) nil))
  (setq msg
    (strcat
      "-----------------------"
      "\nIDF"
      "\n-----------------------"
      "\nK: " (SARJ:_Fmt (HYDRO:Get "HYDRO.IDF.K" nil))
      "\na: " (SARJ:_Fmt (HYDRO:Get "HYDRO.IDF.A" nil))
      "\nb: " (SARJ:_Fmt (HYDRO:Get "HYDRO.IDF.B" nil))
      "\nc: " (SARJ:_Fmt (HYDRO:Get "HYDRO.IDF.C" nil))
      "\ns: " (SARJ:_Fmt (HYDRO:Get "HYDRO.IDF.S" nil))
      "\np: " (SARJ:_Fmt (HYDRO:Get "HYDRO.IDF.P" nil))
      "\n\n-----------------------"
      "\nCARACTERISTICAS"
      "\n-----------------------"
      "\nrunoff: " (SARJ:_Fmt (SARJ:Runoff))
      "\ntc minimo: " (SARJ:_Fmt (SARJ:TcMinimo))
      "\ntempo retorno: " (SARJ:_Fmt (HYDRO:Get "HYDRO.TR" nil))
      "\nsuperficie (handle): " (SARJ:_Fmt (HYDRO:Get "HYDRO.SURFACE.HANDLE" nil))
      "\nsecao atual: " (itoa (SARJ:SecaoAtualId)) " (existentes: " (SARJ:_ListaIds) ")"
      "\n\n-----------------------"
      "\nTEXTO"
      "\n-----------------------"
      "\naltura texto: " (SARJ:_Fmt (SARJ:TextoAltura))
      "\nrotacao texto: " (SARJ:_Fmt (SARJ:TextoRotacao))
    )
  )
  (alert msg)
  (princ (strcat "\n" msg))
  (princ)
)

(HYDRO:SetLabel "HYDRO.RUNOFF" "Coeficiente de runoff (C)" "")
(HYDRO:SetLabel "HYDRO.TC.MINIMO" "Tempo de concentracao minimo" "min")
(HYDRO:SetLabel "HYDRO.TEXT.HEIGHT" "Altura do texto de resultado" "un. desenho")
(HYDRO:SetLabel "HYDRO.TEXT.ROTATION" "Rotacao do texto de resultado" "graus")
(HYDRO:SetLabel "HYDRO.SURFACE.HANDLE" "Superficie (handle)" "")
(HYDRO:SetLabel "HYDRO.SECOES" "Secoes de sarjeta cadastradas" "")
(HYDRO:SetLabel "HYDRO.SECAO.ATUAL" "Secao de sarjeta atual (id)" "")

(HYDRO:Provide "sarjetas" "2.0")

(princ
  (strcat
    "\nCOMANDOS DE SARJETAS:"
    "\n  CALCULASARJETA / CALCULASARJETAMULTITR"
    "\n  CRIARSARJETARESULTADO / CRIARSARJETARESULTADOMULTITR"
    "\n  ATUALIZAIDF  ATUALIZATR  ATUALIZARUNOFF  ATUALIZASUPERFICIE"
    "\n  SELECIONASECAO  CRIASECAO  PARAMETROSSARJETA"
    "\n  ATUALIZAROTACAOTEXTO  ATUALIZAALTURATEXTO"
  )
)
(princ)
