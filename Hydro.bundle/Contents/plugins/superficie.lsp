;;; ============================================================
;;; superficie.lsp - SUPERFICIE DO PROJETO (SUP:)
;;;
;;; Define a superficie TIN do Civil 3D usada pelos objetos para obter cotas
;;; (declividade da bacia e da sarjeta). Sem superficie, vale a cota da polilinha.
;;;
;;; Dado gravado: HYDRO.SURFACE.HANDLE (handle, string). Lido por models/bacia.lsp
;;; e models/sarjeta.lsp; a auditoria (HYDROAUDIT) confere se ela ainda existe.
;;;
;;; COMANDO
;;;   ATUALIZASUPERFICIE   seleciona a superficie (Enter sem selecionar = limpar)
;;; ============================================================
(vl-load-com)

(defun SUP:Atual (/ h e)
  (setq h (HYDRO:Get "HYDRO.SURFACE.HANDLE" nil))
  (setq e (if h (handent h) nil))
  (if (and e (HYDRO:EntValida e)) e nil)
)

(defun c:ATUALIZASUPERFICIE (/ ss)
  (princ
    (if (SUP:Atual)
      (strcat "\nSuperficie atual: handle " (HYDRO:Get "HYDRO.SURFACE.HANDLE" nil))
      "\nNenhuma superficie definida."))
  (princ "\nSelecione a superficie TIN (Enter para limpar): ")
  (setq ss (ssget "_:S" '((0 . "AECC_TIN_SURFACE"))))
  (if ss
    (progn
      (HYDRO:Set "HYDRO.SURFACE.HANDLE" (HYDRO:Handle (ssname ss 0)))
      (princ "\nSuperficie definida.")
    )
    (progn
      (HYDRO:Del "HYDRO.SURFACE.HANDLE")
      (princ "\nSuperficie removida (sera usada a cota da polilinha).")
    )
  )
  (princ)
)

(HYDRO:SetLabel "HYDRO.SURFACE.HANDLE" "Superficie (handle)" "")

(HYDRO:Provide "superficie" "1.0")
(princ)
