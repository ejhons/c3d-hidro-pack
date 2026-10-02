;;; ============================================================
;;; relacao.lsp - XDATA E RELACIONAMENTO ENTRE ENTIDADES (XD:)
;;;
;;; API:
;;;   (XD:Register app)
;;;   (XD:Set    en code valor app)   grava/substitui UM valor para o code
;;;   (XD:Get    en code app)         -> valor ou nil
;;;   (XD:GetAll en app)              -> lista de pares (code . valor)
;;;   (XD:Remove en code app)
;;;   (XD:RemoveApp en app)
;;;   (XD:Link   en1 en2 code app)    relacao 1-1 bidirecional (handles)
;;;   (XD:Unlink en code app)         remove a relacao nos dois lados
;;;   (XD:Linked en code app)         -> ename relacionado ou nil
;;;
;;; app = nil  -> usa "DREN-SARJETA" (padrao, igual ao anterior)
;;; code = nil -> usa 1005 em Link/Unlink/Linked
;;;
;;; Limitacao: para cada code existe UM valor por entidade/aplicacao.
;;;
;;; Integracao: este plugin ASSINA o evento "sarjeta.calculada".
;;; O plugin de sarjetas nao sabe que o XData existe.
;;; ============================================================
(vl-load-com)

(defun XD:_App (app)
  (if app app "DREN-SARJETA")
)

(defun XD:Register (app)
  (setq app (XD:_App app))
  (if (not (tblsearch "APPID" app))
    (regapp app)
  )
  app
)

(defun XD:GetAll (en app)
  (setq app (XD:_App app))
  (cdr (assoc app (cdr (assoc -3 (entget en (list app))))))
)

(defun XD:Get (en code app)
  (cdr (assoc code (XD:GetAll en app)))
)

;; Escreve a lista completa de pares da aplicacao
(defun XD:_Write (en pares app / dados)
  (setq dados (entget en (list app)))
  (entmod
    (append
      (vl-remove (assoc -3 dados) dados)
      (list (list -3 (cons app pares)))
    )
  )
  (entupd en)
  T
)

(defun XD:Set (en code valor app / pares)
  (setq app (XD:Register app))
  (setq pares
    (append
      (vl-remove-if
        (function (lambda (x) (= (car x) code)))
        (XD:GetAll en app)
      )
      (list (cons code valor))
    )
  )
  (XD:_Write en pares app)
  valor
)

(defun XD:Remove (en code app / pares)
  (setq app (XD:_App app))
  (setq pares
    (vl-remove-if
      (function (lambda (x) (= (car x) code)))
      (XD:GetAll en app)
    )
  )
  (XD:_Write en pares app)
)

(defun XD:RemoveApp (en app)
  (setq app (XD:_App app))
  (XD:_Write en nil app)
)

;;; ------------------------------------------------------------
;;; RELACIONAMENTO
;;; ------------------------------------------------------------
(defun XD:Linked (en code app / h)
  (setq h (XD:Get en (if code code 1005) app))
  (if h (handent h) nil)
)

(defun XD:Unlink (en code app / code2 h en2)
  (setq code2 (if code code 1005))
  (setq h (XD:Get en code2 app))
  (if h
    (progn
      (setq en2 (handent h))
      (if en2 (XD:Remove en2 code2 app))
    )
  )
  (XD:Remove en code2 app)
)

(defun XD:Link (en1 en2 code app / code2 h1 h2)
  (setq code2 (if code code 1005))
  (setq h1 (HYDRO:Handle en1))
  (setq h2 (HYDRO:Handle en2))
  ;; remove relacoes antigas antes de criar as novas (relacao 1-1)
  (XD:Unlink en1 code2 app)
  (XD:Unlink en2 code2 app)
  (XD:Set en1 code2 h2 app)
  (XD:Set en2 code2 h1 app)
  T
)

;;; ------------------------------------------------------------
;;; INTEGRACAO COM OUTROS PLUGINS (eventos)
;;; ------------------------------------------------------------
;; Quando uma sarjeta e calculada: relaciona bacia <-> talvegue e grava a
;; vazao (1040, m3/s) na polilinha da bacia.
(defun XD:_OnSarjetaCalculada (dados / bacia talv q)
  (setq bacia (cdr (assoc "BACIA" dados)))
  (setq talv  (cdr (assoc "TALVEGUE" dados)))
  (setq q     (cdr (assoc "Q" dados)))
  (if (and bacia talv)
    (progn
      (XD:Link bacia talv nil nil)
      (if q (XD:Set bacia 1040 q nil))
      (princ "\nEntidades relacionadas (XData).")
    )
  )
)

(HYDRO:On "sarjeta.calculada" "xdata" 'XD:_OnSarjetaCalculada)
(HYDRO:Provide "xdata" "2.0")
(princ)
