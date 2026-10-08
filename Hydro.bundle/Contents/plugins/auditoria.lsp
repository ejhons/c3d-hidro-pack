;;; ============================================================
;;; auditoria.lsp - AUDITORIA DO DESENHO (AUD:)
;;;
;;; Executa as VERIFICACOES cadastradas no catalogo "auditoria" e as correcoes
;;; delas. Cada plugin cadastra as verificacoes do que ele guarda, sem este
;;; arquivo conhecer ninguem (aberto/fechado):
;;;
;;;   (HYDRO:RegAdd "auditoria" "meu-id"
;;;     (list (cons "NOME"     "Nome para exibir")
;;;           (cons "VERIFICA" 'XXX:Verifica)   ; ()           -> lista de problemas
;;;           (cons "TEXTO"    'XXX:Texto)      ; (problema)   -> string
;;;           (cons "REPARA"   'XXX:Repara)))   ; (problemas)  -> quantos corrigiu
;;;
;;;   problema = lista cujo primeiro elemento e uma palavra (tipo do problema) e
;;;              o resto o que a correcao precisa ("PENDENTE" receptor origem...)
;;;   REPARA e opcional: sem ele o problema so e informado (ex.: ciclo de descarga,
;;;   que exige decisao do usuario). REPARA pode perguntar ao usuario.
;;;
;;; Cadastradas hoje
;;;   indice, params, tipo-ausente   plugins/objetos_padrao.lsp
;;;   ligacoes                       plugins/ligacao.lsp
;;;   secao-atual                    plugins/secao.lsp
;;;   secao-sarjeta                  plugins/models/sarjeta.lsp
;;;   superficie                     aqui
;;;
;;; Comando: HYDROAUDIT (views/auditoria_view.lsp)
;;; Uma verificacao que da erro (vl-catch-all-apply) nao derruba as outras: vira o
;;; problema ("ERRO-VERIFICACAO" mensagem).
;;; ============================================================
(vl-load-com)

;; Executa todas as verificacoes. Retorna lista de (id problemas), so as que
;; encontraram problema.
(defun AUD:Verificar (/ out it r)
  (foreach it (HYDRO:RegList "auditoria")
    (setq r (vl-catch-all-apply (cdr (assoc "VERIFICA" (cdr it))) nil))
    (cond
      ((vl-catch-all-error-p r)
        (setq out
          (append out
            (list (list (car it)
                        (list (list "ERRO-VERIFICACAO" (vl-catch-all-error-message r))))))))
      (r (setq out (append out (list (list (car it) r)))))
    )
  )
  out
)

(defun AUD:Nome (id / n)
  (setq n (cdr (assoc "NOME" (HYDRO:RegGet "auditoria" id))))
  (if n n id)
)

(defun AUD:PodeReparar (id)
  (if (cdr (assoc "REPARA" (HYDRO:RegGet "auditoria" id))) T nil)
)

(defun AUD:Texto (id p / fn)
  (setq fn (cdr (assoc "TEXTO" (HYDRO:RegGet "auditoria" id))))
  (cond
    ((equal (car p) "ERRO-VERIFICACAO")
      (strcat "A verificacao falhou: " (cadr p)))
    (fn (apply fn (list p)))
    (T (vl-prin1-to-string p))
  )
)

;; Corrige os problemas de uma verificacao. Retorna quantos foram corrigidos
;; (0 se a verificacao nao tem correcao ou se a correcao falhar).
(defun AUD:Reparar (id problemas / fn r)
  (setq fn (cdr (assoc "REPARA" (HYDRO:RegGet "auditoria" id))))
  (if fn
    (progn
      (setq r
        (vl-catch-all-apply fn
          (list (vl-remove-if
                  (function (lambda (p) (equal (car p) "ERRO-VERIFICACAO")))
                  problemas))))
      (if (and (not (vl-catch-all-error-p r)) (numberp r)) r 0)
    )
    0
  )
)

;;; ------------------------------------------------------------
;;; VERIFICACAO: SUPERFICIE
;;; ------------------------------------------------------------
;; A superficie e guardada pelo handle (HYDRO.SURFACE.HANDLE). Se a entidade foi
;; apagada, bacias e sarjetas ficam sem declividade sem avisar.
(defun AUD:_VerSuperficie (/ h e)
  (setq h (HYDRO:Get "HYDRO.SURFACE.HANDLE" nil))
  (setq e (if h (handent h) nil))
  (if (and h (not (and e (HYDRO:EntValida e))))
    (list (list "SUPERFICIE" h))
    nil
  )
)

(defun AUD:_TxtSuperficie (p)
  (strcat "A superficie definida (handle " (cadr p) ") nao existe mais")
)

(defun AUD:_ReparaSuperficie (problemas)
  (HYDRO:Del "HYDRO.SURFACE.HANDLE")
  (length problemas)
)

(HYDRO:RegAdd "auditoria" "superficie"
  (list (cons "NOME" "Superficie")
        (cons "VERIFICA" 'AUD:_VerSuperficie)
        (cons "TEXTO" 'AUD:_TxtSuperficie)
        (cons "REPARA" 'AUD:_ReparaSuperficie)))

(HYDRO:Provide "auditoria" "1.0")
(princ)
