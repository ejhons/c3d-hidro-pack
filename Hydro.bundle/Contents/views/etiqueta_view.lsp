;;; ============================================================
;;; views/etiqueta_view.lsp - COMANDOS DE ETIQUETA E TABELA VIVA (ETQ:)
;;;
;;;   ETIQUETA            insere uma etiqueta dinamica em um objeto (relatorio ou modelo)
;;;   ETIQUETAEDITA       muda o tipo/modelo de uma etiqueta (e pode gravar como padrao)
;;;   TABELAVIVA          insere a tabela viva com todos os objetos
;;;   ATUALIZAETIQUETAS   atualiza todas as etiquetas e tabelas agora
;;; A logica, os campos do modelo e a atualizacao automatica estao em plugins/etiqueta.lsp.
;;; Depende de "etiqueta".
;;; ============================================================
(vl-load-com)

(defun c:ETIQUETA (/ sel en id op modelo padrao pt novo cen)
  (setq sel (entsel "\nSelecione o objeto a etiquetar: "))
  (setq en (if sel (car sel) nil))
  (cond
    ((not en) nil)
    ((not (setq id (OBJ:TipoDe en)))
      (alert "Esta entidade nao e um objeto hidraulico. Use OBJETO ou BACIACAD."))
    (T
      (initget "Relatorio Modelo")
      (setq op (getkword "\nTipo de etiqueta [Relatorio/Modelo] <Modelo>: "))
      (if (not op) (setq op "Modelo"))
      (if (equal op "Modelo")
        (progn
          (setq padrao (ETQ:ModeloPadrao id))
          (princ (strcat "\nModelo padrao: " padrao))
          (princ "\nCampos: {NOME} {TIPO} {AREA} {C} {CN} {COMP} {DECL} {QP} {TR} {TC} {CENARIO} {GRUPO.CAMPO} ({VAZAO.VALOR}, {ENTRADA.TC}, {ALTURA_LAMINA}...)  \\P = nova linha")
          (setq modelo (getstring T "\nModelo (Enter = padrao): "))
          (if (or (not modelo) (equal modelo "")) (setq modelo padrao))
        )
        (setq modelo nil)
      )
      (setq cen
        (getstring T
          (strcat "\nCenario da etiqueta (Enter = segue o cenario em uso"
                  (if (OBJ:CenarioAtual) (strcat ", agora " (OBJ:CenarioAtual)) "") "): ")))
      (if (equal cen "") (setq cen nil))
      (setq pt (getpoint "\nPonto de insercao da etiqueta: "))
      (if pt
        (progn
          (setq novo
            (ETQ:CriaEtiqueta en pt (if (equal op "Modelo") "MODELO" "FIXO") modelo
                              (HYDRO:Get "HYDRO.TEXT.HEIGHT" 1.8) cen))
          (princ
            (if novo
              "\nEtiqueta criada. Ela se atualiza sozinha quando o objeto e calculado ou ligado."
              "\nNao foi possivel criar a etiqueta."))
        )
      )
    )
  )
  (princ)
)

(defun c:ETIQUETAEDITA (/ sel lab reg alvo en id op fixo atual modelo cen)
  (setq sel (entsel "\nSelecione a etiqueta do Hydro: "))
  (setq lab (if sel (car sel) nil))
  (setq reg (if lab (HYDRO:DadoLer lab "HYDRO-ETQ") nil))
  (cond
    ((not lab) nil)
    ((not reg) (alert "Esta entidade nao e uma etiqueta do Hydro."))
    (T
      (setq alvo (cdr (assoc "ALVO" reg)))
      (setq en (if alvo (handent alvo) nil))
      (setq id (if (and en (HYDRO:EntValida en)) (OBJ:TipoDe en) nil))
      (setq fixo (equal (cdr (assoc "MODO" reg)) "FIXO"))
      (initget "Relatorio Modelo")
      (setq op
        (getkword (strcat "\nTipo [Relatorio/Modelo] <" (if fixo "Relatorio" "Modelo") ">: ")))
      (if (not op) (setq op (if fixo "Relatorio" "Modelo")))
      (if (equal op "Modelo")
        (progn
          (setq atual (cdr (assoc "MODELO" reg)))
          (if (not atual) (setq atual (ETQ:ModeloPadrao id)))
          (princ (strcat "\nModelo atual: " atual))
          (setq modelo (getstring T "\nNovo modelo (Enter = manter): "))
          (if (or (not modelo) (equal modelo "")) (setq modelo atual))
          (if id
            (progn
              (initget "Sim Nao")
              (if (equal (getkword "\nUsar como padrao dos novos do tipo? [Sim/Nao] <Nao>: ") "Sim")
                (HYDRO:Set (strcat "HYDRO.ETIQUETA.MODELO." id) modelo)
              )
            )
          )
        )
        (setq modelo nil)
      )
      ;; cenario fixado: Enter mantem o atual da etiqueta; "-" volta a seguir o cenario em uso
      (setq cen (cdr (assoc "CENARIO" reg)))
      (setq atual
        (getstring T
          (strcat "\nCenario da etiqueta <" (if cen cen "segue o em uso") "> (Enter = manter, - = seguir o em uso): ")))
      (cond
        ((equal atual "-") (setq cen nil))
        ((and atual (/= atual "")) (setq cen atual))
      )
      (HYDRO:DadoGravar lab "HYDRO-ETQ"
        (OBJ:_Limpa
          (list (cons "VERSAO" 1)
                (cons "ALVO" alvo)
                (cons "MODO" (if (equal op "Modelo") "MODELO" "FIXO"))
                (cons "MODELO" modelo)
                (cons "CENARIO" cen))))
      (if (ETQ:Atualiza lab)
        (princ "\nEtiqueta atualizada.")
        (princ "\nO objeto desta etiqueta nao existe mais (rode HYDROAUDIT).")
      )
    )
  )
  (princ)
)

(defun c:TABELAVIVA (/ pt)
  (setq pt (getpoint "\nPonto de insercao da tabela viva: "))
  (if pt
    (if (ETQ:CriaTabela pt (HYDRO:Get "HYDRO.TEXT.HEIGHT" 1.8))
      (princ "\nTabela criada. Ela se atualiza sozinha quando os objetos mudam.")
      (princ "\nNao foi possivel criar a tabela (API de tabelas indisponivel?).")
    )
  )
  (princ)
)

(defun c:ATUALIZAETIQUETAS (/ r)
  (setq r (ETQ:AtualizaTudo))
  (princ (strcat "\n" (itoa (car r)) " etiqueta(s) e " (itoa (cdr r)) " tabela(s) atualizada(s)."))
  (princ)
)

(HYDRO:Provide "etiqueta-view" "1.0")
(princ)
