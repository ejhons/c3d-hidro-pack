;;; ============================================================
;;; views/padroes_view.lsp - PADROES DO PROJETO (PAD:)
;;;
;;; Comando PADROES: define, UMA vez por projeto (desenho), os valores que o Hydro
;;; sugere em vez de pedir de novo: tempo de retorno, tc minimo, metodo chuva-vazao
;;; e os parametros de cada metodo (C do racional, CN e lambda do SCS-CN...) e de cada
;;; tipo de objeto (n de Manning da sarjeta, diametro do trecho...).
;;;
;;; Gravacao: HYDRO.PADRAO.<resto da chave do parametro>, por ex.
;;;   HYDRO.PADRAO.MET.racional.C   HYDRO.PADRAO.MET.scs-cn.CN
;;; Prioridade ao sugerir (HYDRO:AskParams / HYDRO:ParamsPadrao):
;;;   atributo da bacia (C, CN) > padrao do projeto > ultimo valor usado > padrao do metodo
;;; Para um objeto/bacia usar outro valor, cadastre o atributo nele (BACIACAD, OBJETO).
;;;
;;; Tambem aqui: o modo automatico dos calculos esta em CALCAUTO (plugins/ligacao.lsp).
;;; ============================================================
(vl-load-com)

;; Pergunta cada parametro de defs (chave rotulo padrao unidade [tipo [opcoes]]) e
;; grava o padrao do projeto. Enter mantem o valor mostrado.
(defun PAD:_PedeDefs (defs prefixo / d chave atual v)
  (foreach d defs
    (if (not (equal (nth 4 d) "arquivo"))
      (progn
        (setq chave (nth 0 d))
        (setq atual (cdr (car (HYDRO:ParamsPadrao (list d) prefixo nil))))
        (setq v
          (HYDRO:AskUm (nth 1 d) (nth 3 d) (if (nth 4 d) (nth 4 d) "real") (nth 5 d) atual))
        (if v (HYDRO:Set (HYDRO:PadraoKey prefixo chave) v))
      )
    )
  )
)

(defun c:PADROES (/ tr tcmin lista ult i pos m idx t1 defs)
  (princ "\n=== PADROES DO PROJETO (Enter mantem o valor mostrado) ===")
  (setq tr (HYDRO:AskReal "Tempo de retorno padrao (anos)" (HYDRO:Get "HYDRO.TR" nil)))
  (if (and tr (> tr 0.0)) (HYDRO:Set "HYDRO.TR" tr))
  (setq tcmin (HYDRO:AskReal "tc minimo (min)" (HYDRO:Get "HYDRO.TC.MINIMO" 10.0)))
  (if (and tcmin (> tcmin 0.0)) (HYDRO:Set "HYDRO.TC.MINIMO" tcmin))
  (setq lista (HYDRO:RegList "metodo-chuva-vazao"))
  (if lista
    (progn
      (setq ult (HYDRO:Get "HYDRO.BACIA.METODO" nil))
      (setq i 0 pos 0)
      (foreach m lista
        (if (equal (car m) ult) (setq pos i))
        (setq i (1+ i))
      )
      (setq idx
        (HYDRO:Escolher "Metodo chuva-vazao padrao:"
          (mapcar (function (lambda (x) (cdr (assoc "NOME" (cdr x))))) lista)
          pos))
      (HYDRO:Set "HYDRO.BACIA.METODO" (car (nth idx lista)))
    )
  )
  (foreach m lista
    (setq defs (cdr (assoc "PARAMS" (cdr m))))
    (if defs
      (progn
        (princ (strcat "\n-- " (cdr (assoc "NOME" (cdr m))) " --"))
        (PAD:_PedeDefs defs (strcat "HYDRO.MET." (car m) "."))
      )
    )
  )
  (if (HYDRO:Has "objetos")
    (foreach t1 (OBJ:Tipos)
      (setq defs (cdr (assoc "ATRIB-DEFS" (cdr t1))))
      (if defs
        (progn
          (princ (strcat "\n-- " (cdr (assoc "NOME" (cdr t1))) " --"))
          (PAD:_PedeDefs defs (strcat "HYDRO.OBJ." (car t1) "."))
        )
      )
    )
  )
  (princ "\nPadroes gravados no projeto.")
  (princ)
)

(HYDRO:Provide "padroes-view" "1.0")
(princ)
