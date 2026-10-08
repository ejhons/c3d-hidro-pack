;;; ============================================================
;;; views/auditoria_view.lsp - COMANDO HYDROAUDIT (AUD:)
;;;
;;; Como o AUDIT do AutoCAD: localiza os problemas, mostra a lista, pergunta se
;;; deve corrigir e corrige. Depois confere de novo e diz o que restou (o que
;;; exige decisao do usuario). As verificacoes vem do catalogo "auditoria"
;;; (plugins/auditoria.lsp). Depende de "auditoria".
;;; ============================================================
(vl-load-com)

(defun AUD:_Mostrar (res / it p total)
  (setq total 0)
  (foreach it res
    (princ
      (strcat "\n" (AUD:Nome (car it)) ": " (itoa (length (cadr it))) " problema(s)"
              (if (AUD:PodeReparar (car it)) "" "  (sem correcao automatica)")))
    (foreach p (cadr it)
      (princ (strcat "\n  - " (AUD:Texto (car it) p)))
    )
    (setq total (+ total (length (cadr it))))
  )
  total
)

(defun c:HYDROAUDIT (/ res total op it n restam)
  (princ "\n=== AUDITORIA DO HYDRO ===")
  (setq res (AUD:Verificar))
  (setq total (AUD:_Mostrar res))
  (if (= total 0)
    (princ "\nNenhum problema encontrado.")
    (progn
      (princ (strcat "\nTotal: " (itoa total) " problema(s)."))
      (initget "Sim Nao")
      (setq op (getkword "\nCorrigir os problemas encontrados? [Sim/Nao] <Nao>: "))
      (if (equal op "Sim")
        (progn
          (foreach it res
            (if (AUD:PodeReparar (car it))
              (progn
                (setq n (AUD:Reparar (car it) (cadr it)))
                (princ (strcat "\n" (AUD:Nome (car it)) ": " (itoa n) " corrigido(s)."))
              )
            )
          )
          (setq res (AUD:Verificar))
          (setq restam (apply '+ (cons 0 (mapcar (function (lambda (x) (length (cadr x)))) res))))
          (if (= restam 0)
            (princ "\nAuditoria concluida: desenho integro.")
            (progn
              (princ (strcat "\nRestam " (itoa restam) " problema(s) que exigem sua decisao:"))
              (AUD:_Mostrar res)
            )
          )
        )
        (princ "\nNada foi alterado.")
      )
    )
  )
  (princ)
)

(HYDRO:Provide "auditoria-view" "1.0")
(princ)
