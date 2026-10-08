;;; ============================================================
;;; views/painel.lsp - PAINEL DE BOTOES (PNL:)
;;;
;;; Comando:  HYDRO  (ou HYDROPAINEL)
;;;
;;; Abre um dialogo com botoes agrupados que executam os comandos do conjunto.
;;; O painel e GERADO a partir do catalogo "acao-painel" do core: o arquivo
;;; DCL e escrito em um arquivo temporario a cada abertura, com um botao por
;;; acao cadastrada. Logo, um plugin novo ganha botao SEM alterar este arquivo:
;;; basta cadastrar a acao (veja PNL:Acao). Os botoes dos plugins existentes
;;; estao em painel_acoes.lsp.
;;;
;;; COMO FUNCIONA (e limite do DCL)
;;;   O dialogo DCL e MODAL: nao fica aberto enquanto voce desenha. Ao clicar
;;;   num botao, o painel fecha, executa o comando e, se "Manter o painel
;;;   aberto" estiver marcado (padrao), REABRE quando o comando termina.
;;;   Botao de um comando cujo plugin nao esta carregado aparece desabilitado.
;;;   O nome do comando de cada botao esta em docs/painel_e_ribbon.md e no
;;;   arquivo gerado por HYDROMACROS.
;;;   Para botoes SEMPRE visiveis (faixa de opcoes, barra de acesso rapido),
;;;   use HYDROMACROS: ele exporta as macros de todas as acoes para voce
;;;   montar a ribbon no editor de personalizacao (docs/painel_e_ribbon.md).
;;;
;;; CADASTRAR UM BOTAO (em qualquer .lsp, apos painel.lsp no manifesto):
;;;   (PNL:Acao id grupo ordem-grupo ordem rotulo comando requer)
;;;     id           string unica ("bacia.calcular")
;;;     grupo        nome do grupo (caixa) do painel
;;;     ordem-grupo  posicao do grupo (grupos de mesmo nome usam a do 1o item)
;;;     ordem        posicao do botao no grupo
;;;     rotulo       texto do botao (ASCII; sem aspas)
;;;     comando      nome do comando SEM o "c:" ("BACIA")
;;;     requer       lista de funcionalidades obrigatorias ou nil
;;;   Sem painel.lsp carregado, e possivel usar direto:
;;;   (HYDRO:RegAdd "acao-painel" id (list (cons "GRUPO" g) (cons "ORDEM-GRUPO" n)
;;;     (cons "ORDEM" n) (cons "ROTULO" r) (cons "CMD" c) (cons "REQUER" lista)))
;;;
;;; CHAVE: HYDRO.PAINEL.MANTER (1 = manter aberto)
;;; COMANDOS: HYDRO, HYDROPAINEL, HYDROMACROS
;;; ============================================================
(vl-load-com)

;;; ------------------------------------------------------------
;;; CADASTRO DE ACOES
;;; ------------------------------------------------------------
(defun PNL:Acao (id grupo ordem-grupo ordem rotulo comando requer)
  (HYDRO:RegAdd "acao-painel" id
    (list
      (cons "GRUPO" grupo)
      (cons "ORDEM-GRUPO" ordem-grupo)
      (cons "ORDEM" ordem)
      (cons "ROTULO" rotulo)
      (cons "CMD" comando)
      (cons "REQUER" requer)
    )
  )
  id
)

;;; ------------------------------------------------------------
;;; UTILITARIOS (puros)
;;; ------------------------------------------------------------
;; aspas e barras invertidas quebrariam o DCL gerado
(defun PNL:_Sanitiza (s)
  (vl-string-translate "\"\\" "' " s)
)

(defun PNL:_Num (v padrao)
  (if v v padrao)
)

;; ESTILOS DE MACRO (texto que o menu e os botoes das barras executam)
;;   lisp          (c:BACIA)           chama a funcao direto; SEM caractere de controle (padrao)
;;   cancela-lisp  ^C^C(c:BACIA)       cancela um comando ativo e chama a funcao
;;   nome          BACIA<espaco>       digita o nome do comando e Enter
;;   cancela       ^C^CBACIA           formato classico do editor CUI
;;   espaco        ^C^CBACIA<espaco>   idem, com Enter explicito
;; Se um estilo nao funcionar na sua versao, troque com HYDROMACROESTILO.
(defun PNL:_MacroEstilos ()
  '("lisp" "cancela-lisp" "nome" "cancela" "espaco")
)

(defun PNL:_MacroEstilo ()
  (HYDRO:Get "HYDRO.MACRO.ESTILO" "lisp")
)

(defun PNL:_MacroDe (cmd estilo)
  (cond
    ((equal estilo "cancela-lisp") (strcat "^C^C(c:" cmd ")"))
    ((equal estilo "nome") (strcat cmd " "))
    ((equal estilo "cancela") (strcat "^C^C" cmd))
    ((equal estilo "espaco") (strcat "^C^C" cmd " "))
    (T (strcat "(c:" cmd ")"))
  )
)

;; macro no estilo configurado
(defun PNL:_Macro (cmd)
  (PNL:_MacroDe cmd (PNL:_MacroEstilo))
)

(defun PNL:_Rotulo (item)
  (PNL:_Sanitiza (cdr (assoc "ROTULO" (cdr item))))
)

;; divide a lista em pedacos de n elementos
(defun PNL:_Fatia (lista n / out atual x)
  (foreach x lista
    (setq atual (append atual (list x)))
    (if (= (length atual) n)
      (setq out (append out (list atual)) atual nil)
    )
  )
  (if atual (setq out (append out (list atual))))
  out
)

;; itens = ((id . dados) ...) na ordem de cadastro.
;; Retorna ((grupo item item ...) ...) ordenado por grupo e por botao.
(defun PNL:_Grupos (itens / i it nome g novo lista)
  (setq i 0)
  (foreach it itens
    (setq i (1+ i))
    (setq nome (cdr (assoc "GRUPO" (cdr it))))
    (setq g (assoc nome lista))
    (if (not g)
      (setq g
        (list nome
              (PNL:_Num (cdr (assoc "ORDEM-GRUPO" (cdr it))) 100)
              i
              nil)
            lista (append lista (list g)))
    )
    (setq novo
      (list (car g) (cadr g) (caddr g)
            (append (cadddr g)
                    (list (list (PNL:_Num (cdr (assoc "ORDEM" (cdr it))) 100) i it)))))
    (setq lista (subst novo g lista))
  )
  (mapcar
    (function
      (lambda (g)
        (cons
          (car g)
          (mapcar
            'caddr
            (vl-sort
              (cadddr g)
              (function
                (lambda (a b)
                  (if (= (car a) (car b))
                    (< (cadr a) (cadr b))
                    (< (car a) (car b))))))))))
    (vl-sort
      lista
      (function
        (lambda (a b)
          (if (= (cadr a) (cadr b))
            (< (caddr a) (caddr b))
            (< (cadr a) (cadr b))))))
  )
)

;; largura (caracteres) dos botoes de um grupo: o maior rotulo do grupo,
;; entre 24 e 44
(defun PNL:_LarguraGrupo (g / w it)
  (setq w 24)
  (foreach it (cdr g)
    (setq w (max w (+ (strlen (PNL:_Rotulo it)) 2)))
  )
  (min w 44)
)

;; Gera o texto do DCL. Retorna (linhas . itens-na-ordem-das-chaves):
;; o botao de chave "b<k>" corresponde ao k-esimo item da lista.
(defun PNL:_GerarDcl (grupos ncol / linhas ordem k w linha g it)
  (setq k 0)
  (setq linhas
    (list
      "// gerado por painel.lsp - nao edite (e recriado a cada abertura)"
      "hydro_painel : dialog {"
      "  label = \"HYDRO - Painel de comandos\";"
    )
  )
  (foreach linha (PNL:_Fatia grupos ncol)
    (setq linhas (append linhas (list "  : row {")))
    (foreach g linha
      (setq w (PNL:_LarguraGrupo g))
      (setq linhas
        (append linhas
          (list "    : boxed_column {"
                (strcat "      label = \"" (PNL:_Sanitiza (car g)) "\";"))))
      (foreach it (cdr g)
        (setq linhas
          (append linhas
            (list
              (strcat "      : button { key = \"b" (itoa k) "\"; label = \""
                      (PNL:_Rotulo it) "\"; width = " (itoa w)
                      "; fixed_width = true; }"))))
        (setq ordem (append ordem (list it)))
        (setq k (1+ k))
      )
      (setq linhas (append linhas (list "    }")))
    )
    (setq linhas (append linhas (list "  }")))
  )
  (setq linhas
    (append linhas
      (list
        "  spacer;"
        "  : row {"
        "    : toggle { key = \"manter\"; label = \"Manter o painel aberto depois de executar\"; }"
        "    : spacer { width = 4; }"
        "    : button { key = \"cancel\"; label = \"Fechar\"; is_cancel = true; is_default = true; width = 12; fixed_width = true; }"
        "  }"
        "}"
      )
    )
  )
  (cons linhas ordem)
)

;; O botao esta disponivel? Comando definido e funcionalidades carregadas.
(defun PNL:Disponivel (dados / cmd ok f)
  (setq cmd (cdr (assoc "CMD" dados)))
  (setq ok (if (boundp (read (strcat "c:" cmd))) T nil))
  (foreach f (cdr (assoc "REQUER" dados))
    (if (not (HYDRO:Has f)) (setq ok nil))
  )
  ok
)

;;; ------------------------------------------------------------
;;; EXECUCAO
;;; ------------------------------------------------------------
;; comandos que recarregam o conjunto: o painel fecha depois deles
(defun PNL:_FechaPainel (cmd)
  (if (member (strcase cmd) '("HYDRORELOAD" "HYDRODIR")) T nil)
)

;; Executa o comando (funcao c:XXX). Erro ou ESC nao derrubam o painel.
(defun PNL:_Executa (cmd / r)
  (setq r (vl-catch-all-apply (read (strcat "c:" cmd)) nil))
  (if (vl-catch-all-error-p r)
    (princ
      (strcat "\n[HYDRO] " cmd " interrompido: " (vl-catch-all-error-message r)))
  )
  (princ)
)

;;; ------------------------------------------------------------
;;; DIALOGO
;;; ------------------------------------------------------------
(defun PNL:Abrir (/ itens gerado ordem arq f dcl_id manter ok cod it i cmd l)
  (setq itens (HYDRO:RegList "acao-painel"))
  (cond
    ((not itens)
      (alert "Nenhuma acao cadastrada no painel (painel_acoes.lsp).")
      nil
    )
    (T
      (setq gerado (PNL:_GerarDcl (PNL:_Grupos itens) 3))
      (setq ordem (cdr gerado))
      (setq arq (vl-filename-mktemp "hydro_painel" nil ".dcl"))
      (setq f (open arq "w"))
      (if (not f)
        (alert "Nao foi possivel criar o arquivo temporario do painel.")
        (progn
          (foreach l (car gerado) (write-line l f))
          (close f)
          (setq dcl_id (load_dialog arq))
          (if (< dcl_id 0)
            (alert "Nao foi possivel carregar o DCL do painel.")
            (progn
              (setq manter (= (HYDRO:Get "HYDRO.PAINEL.MANTER" 1) 1))
              (setq ok T)
              (while ok
                (if (not (new_dialog "hydro_painel" dcl_id))
                  (progn
                    (alert "Nao foi possivel abrir o painel.")
                    (setq ok nil)
                  )
                  (progn
                    (set_tile "manter" (if manter "1" "0"))
                    (setq i 0)
                    (foreach it ordem
                      (mode_tile (strcat "b" (itoa i)) (if (PNL:Disponivel (cdr it)) 0 1))
                      (action_tile (strcat "b" (itoa i))
                                   (strcat "(done_dialog " (itoa (+ i 10)) ")"))
                      (setq i (1+ i))
                    )
                    (action_tile "manter" "(setq manter (= $value \"1\"))")
                    (action_tile "cancel" "(done_dialog 0)")
                    (setq cod (start_dialog))
                    (if (>= cod 10)
                      (progn
                        (setq it (nth (- cod 10) ordem))
                        (setq cmd (cdr (assoc "CMD" (cdr it))))
                        (HYDRO:Set "HYDRO.PAINEL.MANTER" (if manter 1 0))
                        (PNL:_Executa cmd)
                        (if (or (not manter) (PNL:_FechaPainel cmd))
                          (setq ok nil)
                        )
                      )
                      (setq ok nil)
                    )
                  )
                )
              )
              (HYDRO:Set "HYDRO.PAINEL.MANTER" (if manter 1 0))
              (unload_dialog dcl_id)
            )
          )
          (vl-file-delete arq)
        )
      )
    )
  )
  (princ)
)

;;; ------------------------------------------------------------
;;; COMANDOS
;;; ------------------------------------------------------------
(defun c:HYDRO ()
  (PNL:Abrir)
  (princ)
)

(defun c:HYDROPAINEL ()
  (PNL:Abrir)
  (princ)
)

;; Exporta as macros (texto, separado por TAB) de todas as acoes, para montar
;; a ribbon/barra no editor de personalizacao (CUI). Sempre em dia com o
;; catalogo de acoes.
(defun c:HYDROMACROS (/ grupos arq f g it cmd)
  (setq grupos (PNL:_Grupos (HYDRO:RegList "acao-painel")))
  (if (not grupos)
    (alert "Nenhuma acao cadastrada no painel.")
    (progn
      (setq arq
        (getfiled "Salvar macros (texto)"
          (strcat (getvar "DWGPREFIX") "hydro_macros.txt") "txt" 1))
      (if arq
        (progn
          (setq f (open arq "w"))
          (if f
            (progn
              (write-line "Grupo\tRotulo\tComando\tMacro (estilo atual)\tMacro para o editor CUI" f)
              (foreach g grupos
                (foreach it (cdr g)
                  (setq cmd (cdr (assoc "CMD" (cdr it))))
                  (write-line
                    (strcat (car g) "\t" (cdr (assoc "ROTULO" (cdr it))) "\t"
                            cmd "\t" (PNL:_Macro cmd) "\t" (PNL:_MacroDe cmd "cancela"))
                    f)
                )
              )
              (close f)
              (alert (strcat "Macros salvas em:\n" arq
                             "\n\nUse-as no editor CUI (veja docs/painel_e_ribbon.md)."))
            )
            (alert "Nao foi possivel gravar o arquivo.")
          )
        )
      )
    )
  )
  (princ)
)

;; Troca o estilo de macro e reconstroi menu e barras (se existirem)
(defun c:HYDROMACROESTILO (/ atual novo i itens)
  (setq atual (PNL:_MacroEstilo))
  (princ "\nEstilos de macro (o que o menu e os botoes das barras executam):")
  (foreach i (PNL:_MacroEstilos)
    (princ (strcat "\n  " (if (equal i atual) "* " "  ") (strcat i)
                   "   ->   " (PNL:_MacroDe "BACIA" i)))
  )
  (setq itens (PNL:_MacroEstilos))
  (setq novo
    (nth (HYDRO:Escolher "Escolha o estilo:" itens
           (if (vl-position atual itens) (vl-position atual itens) 0))
         itens))
  (HYDRO:Set "HYDRO.MACRO.ESTILO" novo)
  (princ (strcat "\n[HYDRO] Estilo de macro: " novo))
  (if (HYDRO:Has "menu") (MNU:Criar))
  (if (HYDRO:Has "toolbar") (TLB:Criar))
  (princ "\n[HYDRO] Menu e barras reconstruidos. Teste um botao.")
  (princ)
)

(HYDRO:SetLabel "HYDRO.MACRO.ESTILO" "Estilo das macros de menu/barras (lisp, cancela-lisp, nome, cancela, espaco)" "")
(HYDRO:SetLabel "HYDRO.PAINEL.MANTER" "Painel: manter aberto depois de executar (1 = sim)" "")

(HYDRO:Provide "painel" "1.0")
(princ)
