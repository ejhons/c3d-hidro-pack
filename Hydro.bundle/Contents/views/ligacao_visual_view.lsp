;;; ============================================================
;;; views/ligacao_visual_view.lsp - LIGACOES TEMPORARIAS NA TELA (LVW:)
;;;
;;;   LIGACOESVER   mostra, na tela, uma linha TRACEJADA e fraca com seta de cada origem ate o
;;;                 destino dela (JUSANTE). Objetos selecionados: suas ligacoes (a que sai de cada
;;;                 um e as que chegam nele); Enter = todos os objetos do desenho.
;;;
;;; A linha e TEMPORARIA: desenhada com GRVECS (vetores de tela), nao e entidade do desenho, nao
;;; entra em DWG nem em plotagem e some no primeiro REDRAW, REGEN ou zoom/pan que redesenhe a tela.
;;; Depois do LIGAR as ligacoes novas aparecem sozinhas (se esta view esta carregada).
;;;
;;; ONDE A LINHA SAI E ENTRA
;;;   Contorno FECHADO sem talvegue (bacia sem talvegue): sai do CENTRO e entra no CENTRO.
;;;   Entidade com CURVA (bacia com talvegue, usando o talvegue; sarjeta, tubo...): SAI do FIM da
;;;   curva e ENTRA no INICIO da curva de destino. Sem curva (bloco, estrutura, ponto): o centro.
;;;   Centro = centro da caixa envolvente. Talvegue = PARAMS "TALVEGUE" do objeto.
;;; Tamanho dos tracos e da seta: proporcional a altura da vista (VIEWSIZE), entao acompanham o
;;; zoom no momento do comando. Cor: HYDRO.LIGACAO.VER.COR (indice AutoCAD, padrao 8 = cinza).
;;; Depende de "ligacao". Sem variaveis globais.
;;; ============================================================
(vl-load-com)

;;; ------------------------------------------------------------
;;; PONTOS DE REFERENCIA
;;; ------------------------------------------------------------
;; centro da caixa envolvente (WCS) ou nil
(defun LVW:_Centro (en / mn mx r)
  (setq r
    (vl-catch-all-apply
      (function
        (lambda ()
          (vla-getboundingbox (vlax-ename->vla-object en) 'mn 'mx)
          (mapcar
            (function (lambda (a b) (/ (+ a b) 2.0)))
            (vlax-safearray->list mn) (vlax-safearray->list mx))))
      nil))
  (if (vl-catch-all-error-p r) nil r)
)

;; T se a entidade e uma curva ABERTA (linha, polilinha aberta, arco...)
(defun LVW:_CurvaAberta (en / r)
  (setq r
    (vl-catch-all-apply
      (function (lambda () (if (vlax-curve-isClosed en) nil T)))
      nil))
  (if (vl-catch-all-error-p r) nil r)
)

;; Curva que representa o objeto: o TALVEGUE (PARAMS "TALVEGUE", se existe), senao a propria
;; entidade se for curva aberta, senao nil (contorno fechado, bloco, estrutura...)
(defun LVW:_Curva (en / h talv)
  (setq h (cdr (assoc "TALVEGUE" (OBJ:ParamsDe en))))
  (setq talv (if (and h (OBJ:_HandleOk h)) (handent h) nil))
  (cond
    (talv talv)
    ((LVW:_CurvaAberta en) en)
    (T nil)
  )
)

;; ponto (WCS) de onde a ligacao SAI: fim da curva do objeto; sem curva, o centro
(defun LVW:PontoSaida (en / c r)
  (setq c (LVW:_Curva en))
  (setq r (if c (vl-catch-all-apply 'vlax-curve-getEndPoint (list c)) nil))
  (if (or (null r) (vl-catch-all-error-p r)) (LVW:_Centro en) r)
)

;; ponto (WCS) em que a ligacao ENTRA: inicio da curva do objeto; sem curva, o centro
(defun LVW:PontoEntrada (en / c r)
  (setq c (LVW:_Curva en))
  (setq r (if c (vl-catch-all-apply 'vlax-curve-getStartPoint (list c)) nil))
  (if (or (null r) (vl-catch-all-error-p r)) (LVW:_Centro en) r)
)

;;; ------------------------------------------------------------
;;; TRACOS (puro)
;;; ------------------------------------------------------------
;; (puro) trechos de traco ao longo de um comprimento d: lista de (inicio . fim), com traco `dash`
;; e vazio `gap`. Mais de `maxn` tracos: aumenta os dois proporcionalmente (nao trava em linhas
;; muito longas). d <= 0: nil. Linha mais curta que o traco: um traco so.
(defun LVW:_Tracos (d dash gap maxn / n f pos out)
  (if (> d 0.0)
    (progn
      (setq n (/ d (+ dash gap)))
      (if (> n maxn)
        (setq f (/ n maxn) dash (* dash f) gap (* gap f))
      )
      (setq pos 0.0)
      (while (< pos d)
        (setq out (append out (list (cons pos (min d (+ pos dash))))))
        (setq pos (+ pos dash gap))
      )
      out
    )
    nil
  )
)

;; (puro) pontas da seta em p2 (UCS), vinda de p1, com tamanho `tam` e abertura de 25 graus:
;; lista de 2 pontos (x y z)
(defun LVW:_Seta (p1 p2 tam / dx dy d ux uy a c s)
  (setq dx (- (car p2) (car p1)))
  (setq dy (- (cadr p2) (cadr p1)))
  (setq d (sqrt (+ (* dx dx) (* dy dy))))
  (if (> d 1e-12)
    (progn
      (setq ux (/ (- dx) d) uy (/ (- dy) d))        ; da ponta para tras
      (setq a (* 25.0 (/ pi 180.0)))
      (setq c (cos a) s (sin a))
      (list
        (list (+ (car p2) (* tam (- (* ux c) (* uy s))))
              (+ (cadr p2) (* tam (+ (* ux s) (* uy c)))) (caddr p2))
        (list (+ (car p2) (* tam (+ (* ux c) (* uy s))))
              (+ (cadr p2) (* tam (- (* uy c) (* ux s)))) (caddr p2)))
    )
    nil
  )
)

;;; ------------------------------------------------------------
;;; DESENHO TEMPORARIO
;;; ------------------------------------------------------------
;; vetores (pares de pontos UCS, na forma do GRVECS) de uma ligacao p1 -> p2 (UCS)
(defun LVW:_Vetores (p1 p2 dash gap tam / d ux uy tr out seta pt)
  (setq d (distance p1 p2))
  (if (> d 1e-9)
    (progn
      (setq ux (/ (- (car p2) (car p1)) d))
      (setq uy (/ (- (cadr p2) (cadr p1)) d))
      (foreach tr (LVW:_Tracos d dash gap 300)
        (setq out
          (append out
            (list
              (list (+ (car p1) (* ux (car tr))) (+ (cadr p1) (* uy (car tr))) (caddr p1))
              (list (+ (car p1) (* ux (cdr tr))) (+ (cadr p1) (* uy (cdr tr))) (caddr p1)))))
      )
      (setq seta (LVW:_Seta p1 p2 tam))
      (foreach pt seta
        (setq out (append out (list p2 pt)))
      )
      out
    )
    nil
  )
)

;; Desenha na tela as ligacoes `pares` = ((ename-origem ename-destino) ...). Retorna quantas.
(defun LVW:Desenha (pares / vs dash gap tam cor lista par p1 p2 n)
  (setq vs (getvar "VIEWSIZE"))
  (setq dash (* vs 0.012) gap (* vs 0.010) tam (* vs 0.030))
  (setq cor (HYDRO:Get "HYDRO.LIGACAO.VER.COR" 8))
  (setq n 0)
  (foreach par pares
    (setq p1 (LVW:PontoSaida (car par)))
    (setq p2 (LVW:PontoEntrada (cadr par)))
    (if (and p1 p2)
      (progn
        (setq lista
          (append lista
            (LVW:_Vetores (trans p1 0 1) (trans p2 0 1) dash gap tam)))
        (setq n (1+ n))
      )
    )
  )
  (if lista
    (vl-catch-all-apply 'grvecs (list (cons cor lista)))
  )
  n
)

;;; ------------------------------------------------------------
;;; LIGACOES A MOSTRAR
;;; ------------------------------------------------------------
;; Ligacoes (origem destino) dos objetos `conjunto`: a que sai de cada um e as que chegam nele.
;; Sem repetir a mesma origem.
(defun LVW:Pares (conjunto / out vistas en dest m h)
  (foreach en conjunto
    (setq dest (LIG:Destino en))
    (setq h (HYDRO:Handle en))
    (if (and dest (not (member h vistas)))
      (setq vistas (cons h vistas) out (append out (list (list en dest))))
    )
    (foreach m (LIG:Afluentes en)
      (setq h (HYDRO:Handle m))
      (if (not (member h vistas))
        (setq vistas (cons h vistas) out (append out (list (list m en))))
      )
    )
  )
  out
)

;; Mostra as ligacoes de `objetos` (lista de enames). Retorna quantas desenhou.
(defun LVW:Mostra (objetos)
  (LVW:Desenha (LVW:Pares objetos))
)

(defun c:LIGACOESVER (/ ss i conjunto n)
  (princ "\nSelecione objetos (Enter = todos os do desenho): ")
  (setq ss (ssget))
  (if ss
    (progn
      (setq i (sslength ss))
      (while (> i 0)
        (setq i (1- i))
        (if (OBJ:TipoDe (ssname ss i))
          (setq conjunto (cons (ssname ss i) conjunto))
        )
      )
    )
    (setq conjunto (OBJ:Listar))
  )
  (setq n (LVW:Mostra conjunto))
  (princ
    (if (> n 0)
      (strcat "\n" (itoa n) " ligacao(oes) mostrada(s) (temporaria: some com REDRAW/REGEN).")
      "\nNenhuma ligacao a mostrar."))
  (princ)
)

(HYDRO:SetLabel "HYDRO.LIGACAO.VER.COR" "Cor (indice AutoCAD) das ligacoes temporarias" "")

(HYDRO:Provide "ligacao-visual-view" "1.0")
(princ)
