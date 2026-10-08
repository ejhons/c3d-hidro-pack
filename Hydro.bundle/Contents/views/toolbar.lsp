;;; ============================================================
;;; views/toolbar.lsp - BARRAS DE FERRAMENTAS "HYDRO" (TLB:)
;;;
;;; Cria barras de ferramentas (AcadToolbars, API ActiveX do Visual LISP):
;;; UMA BARRA POR GRUPO ("Hydro - Bacias", "Hydro - Hidrogramas"...), com um
;;; botao por acao. Os botoes vem do MESMO catalogo "acao-painel" do painel e
;;; do menu: comando novo com PNL:Acao = botao novo, sem alterar este arquivo.
;;;
;;; ICONES (resources/icons/)
;;;   Cada botao procura, nesta ordem:
;;;     1. <id>_16.bmp  e  <id>_24.bmp    ("." do id vira "_": bacia_cadastrar_16.bmp)
;;;     2. _grupo_<ordem-do-grupo>_16/24.bmp
;;;     3. _padrao_16/24.bmp
;;;   Os icones incluidos sao gerados por build/gerar_icones.py (quadrado
;;;   colorido por grupo com um codigo de ate 3 letras). Para usar os seus,
;;;   coloque arquivos com o MESMO NOME na pasta: nenhum codigo muda.
;;;   Formato: HYDRO.TOOLBAR.EXT ("bmp" padrao; "png" se a sua versao preferir).
;;;
;;; QUANDO E CRIADO
;;;   Automaticamente depois que TODOS os plugins carregaram (evento
;;;   "hydro.carregado"), se HYDRO.TOOLBAR.AUTO = 1 (padrao). So entram acoes
;;;   disponiveis. HYDRORELOAD reconstroi.
;;;
;;; SEM DUPLICAR NEM MEXER NO SEU LAYOUT
;;;   Barras que ja existem (mesmo nome) sao REAPROVEITADAS: botoes recriados,
;;;   posicao e visibilidade mantidas (so tornadas visiveis). Posicao inicial
;;;   de uma barra NOVA: HYDRO.TOOLBAR.DOCK = "left" (padrao), "top", "bottom",
;;;   "right" ou "float". Barras de grupos que deixaram de existir sao apagadas.
;;;   Nada e salvo no arquivo de personalizacao (nao chama Save).
;;;
;;; COMANDOS
;;;   HYDROBARRAS          cria/atualiza e mostra as barras
;;;   HYDROBARRASREMOVER   apaga as barras "Hydro - *"
;;; CHAVES: HYDRO.TOOLBAR.AUTO  HYDRO.TOOLBAR.DOCK  HYDRO.TOOLBAR.EXT
;;; ============================================================
(vl-load-com)

;;; ------------------------------------------------------------
;;; ICONES (nomes de arquivo; puros)
;;; ------------------------------------------------------------
;; "bacia.cadastrar" -> "bacia_cadastrar"
(defun TLB:_Base (id)
  (vl-string-translate ". " "__" id)
)

(defun TLB:_Ext ()
  (HYDRO:Get "HYDRO.TOOLBAR.EXT" "bmp")
)

(defun TLB:_Arquivo (base tam ext)
  (strcat base "_" (itoa tam) "." ext)
)

;; caminho do icone (tam = 16 ou 24): da acao, do grupo ou o padrao; nil se
;; nem o padrao existir
(defun TLB:_Icone (id og tam / ext r)
  (setq ext (TLB:_Ext))
  (setq r (HYDRO:FindFile (TLB:_Arquivo (TLB:_Base id) tam ext)))
  (if (not r)
    (setq r (HYDRO:FindFile (TLB:_Arquivo (strcat "_grupo_" (itoa og)) tam ext)))
  )
  (if (not r)
    (setq r (HYDRO:FindFile (TLB:_Arquivo "_padrao" tam ext)))
  )
  (if r (vl-string-translate "/" "\\" r) nil)
)

;;; ------------------------------------------------------------
;;; ESTRUTURA DAS BARRAS (pura)
;;; ------------------------------------------------------------
;; grupos = saida de PNL:_Grupos; disp-fn = funcao dados -> T/nil.
;; Retorna ((nome-da-barra ordem-grupo ((id rotulo comando macro) ...)) ...)
;; sem grupos vazios.
(defun TLB:_Estrutura (grupos disp-fn / g it itens out cmd og)
  (foreach g grupos
    (setq itens nil)
    (foreach it (cdr g)
      (if (apply disp-fn (list (cdr it)))
        (progn
          (setq cmd (cdr (assoc "CMD" (cdr it))))
          (setq itens
            (append itens
              (list (list (car it) (PNL:_Rotulo it) cmd (PNL:_Macro cmd)))))
        )
      )
    )
    (if itens
      (progn
        (setq og (PNL:_Num (cdr (assoc "ORDEM-GRUPO" (cdr (cadr g)))) 100))
        (setq out
          (append out
            (list (list (strcat "Hydro - " (PNL:_Sanitiza (car g))) og itens))))
      )
    )
  )
  out
)

;;; ------------------------------------------------------------
;;; API ACTIVEX DE BARRAS
;;; ------------------------------------------------------------
;; Grupo de menus principal: "ACAD" se existir; senao o primeiro.
(defun TLB:_GrupoPrincipal (acad / g achou primeiro)
  (vlax-for g (vla-get-menugroups acad)
    (if (not primeiro) (setq primeiro g))
    (if (and (not achou) (equal (strcase (vla-get-name g)) "ACAD"))
      (setq achou g)
    )
  )
  (if achou achou primeiro)
)

;; barras "Hydro - *" que ja existem
(defun TLB:_Existentes (toolbars / tb out)
  (vlax-for tb toolbars
    (if (wcmatch (vla-get-name tb) "Hydro - *")
      (setq out (append out (list tb)))
    )
  )
  out
)

(defun TLB:_Acha (lista nome / tb out)
  (foreach tb lista
    (if (and (not out) (equal (vla-get-name tb) nome))
      (setq out tb)
    )
  )
  out
)

;; apaga todos os botoes da barra (de tras para frente)
(defun TLB:_Limpa (tb / i)
  (setq i (1- (vla-get-count tb)))
  (while (>= i 0)
    (vla-delete (vla-item tb i))
    (setq i (1- i))
  )
)

;; define os icones do botao (falha de icone nao derruba a barra)
(defun TLB:_Icones (botao id og / p16 p24)
  (setq p16 (TLB:_Icone id og 16))
  (setq p24 (TLB:_Icone id og 24))
  (if (or p16 p24)
    (vl-catch-all-apply
      'vla-setbitmaps
      (list botao (if p16 p16 p24) (if p24 p24 p16)))
  )
)

(defun TLB:_Botoes (tb itens og / i it botao)
  (setq i 0)
  (foreach it itens
    (setq botao
      (vla-addtoolbarbutton
        tb
        i
        (nth 1 it)
        (strcat (nth 1 it) "  [" (nth 2 it) "]")
        (nth 3 it)
        :vlax-false))
    (TLB:_Icones botao (nth 0 it) og)
    (setq i (1+ i))
  )
)

;; posicao inicial de uma barra NOVA (i = posicao da barra na lista)
(defun TLB:_Posiciona (tb i / pos)
  (setq pos (HYDRO:Get "HYDRO.TOOLBAR.DOCK" "left"))
  (cond
    ((equal pos "top") (vla-dock tb 0))
    ((equal pos "bottom") (vla-dock tb 1))
    ((equal pos "left") (vla-dock tb 2))
    ((equal pos "right") (vla-dock tb 3))
    (T (vla-float tb (+ 150 (* i 40)) (+ 100 (* i 30)) 1))
  )
)

(defun TLB:_CriarInterno (/ acad toolbars estrutura existentes b tb novo usados i)
  (setq acad (vlax-get-acad-object))
  (setq toolbars (vla-get-toolbars (TLB:_GrupoPrincipal acad)))
  (setq estrutura
    (TLB:_Estrutura
      (PNL:_Grupos (HYDRO:RegList "acao-painel"))
      'PNL:Disponivel))
  (setq existentes (TLB:_Existentes toolbars))
  (setq i 0)
  (foreach b estrutura
    (setq tb (TLB:_Acha existentes (car b)))
    (setq novo (not tb))
    (if tb
      (TLB:_Limpa tb)
      (setq tb (vla-add toolbars (car b)))
    )
    (TLB:_Botoes tb (nth 2 b) (nth 1 b))
    (if novo (TLB:_Posiciona tb i))
    (vla-put-visible tb :vlax-true)
    (setq usados (cons (car b) usados))
    (setq i (1+ i))
  )
  ;; barras de grupos que nao existem mais
  (foreach tb existentes
    (if (not (member (vla-get-name tb) usados))
      (vla-delete tb)
    )
  )
  (length estrutura)
)

;; Cria/atualiza as barras. Retorna a quantidade de barras ou nil (com mensagem).
(defun TLB:Criar (/ r)
  (setq r (vl-catch-all-apply 'TLB:_CriarInterno nil))
  (if (vl-catch-all-error-p r)
    (progn
      (princ
        (strcat "\n[HYDRO] Nao foi possivel criar as barras de ferramentas: "
                (vl-catch-all-error-message r)
                "\n        Use o comando HYDRO (painel de botoes) ou o menu Hydro."))
      nil
    )
    r
  )
)

;; Apaga as barras "Hydro - *". Retorna quantas foram apagadas (ou nil).
(defun TLB:Remover (/ r)
  (setq r
    (vl-catch-all-apply
      (function
        (lambda (/ acad lista tb)
          (setq acad (vlax-get-acad-object))
          (setq lista
            (TLB:_Existentes (vla-get-toolbars (TLB:_GrupoPrincipal acad))))
          (foreach tb lista (vla-delete tb))
          (length lista)
        )
      )
      nil
    )
  )
  (if (vl-catch-all-error-p r)
    (progn
      (princ (strcat "\n[HYDRO] Nao foi possivel remover as barras: "
                     (vl-catch-all-error-message r)))
      nil
    )
    r
  )
)

;;; ------------------------------------------------------------
;;; COMANDOS E INTEGRACAO
;;; ------------------------------------------------------------
(defun c:HYDROBARRAS (/ n)
  (setq n (TLB:Criar))
  (if n
    (princ (strcat "\n[HYDRO] " (itoa n) " barra(s) de ferramentas criada(s)/atualizada(s)."))
  )
  (princ)
)

(defun c:HYDROBARRASREMOVER (/ n)
  (setq n (TLB:Remover))
  (if n
    (princ (strcat "\n[HYDRO] " (itoa n) " barra(s) de ferramentas removida(s)."))
  )
  (princ)
)

;; Depois que todos os plugins carregaram: cria as barras sozinho
(defun TLB:_OnCarregado (dados / n)
  (if (and (= (HYDRO:Get "HYDRO.TOOLBAR.AUTO" 1) 1)
           (HYDRO:Has "painel"))
    (setq n (TLB:Criar))
  )
)

(HYDRO:On "hydro.carregado" "toolbar" 'TLB:_OnCarregado)

(HYDRO:SetLabel "HYDRO.TOOLBAR.AUTO" "Criar as barras de ferramentas sozinho ao carregar (1 = sim)" "")
(HYDRO:SetLabel "HYDRO.TOOLBAR.DOCK" "Posicao inicial das barras novas (left, top, bottom, right, float)" "")
(HYDRO:SetLabel "HYDRO.TOOLBAR.EXT" "Formato dos icones das barras (bmp ou png)" "")

;; botoes do painel para os comandos deste plugin
(if (HYDRO:Has "painel")
  (progn
    (PNL:Acao "sis.barras"        "Sistema" 90 100 "Recriar as barras Hydro" "HYDROBARRAS" '("toolbar"))
    (PNL:Acao "sis.barrasremover" "Sistema" 90 110 "Remover as barras Hydro" "HYDROBARRASREMOVER" '("toolbar"))
  )
)

(HYDRO:Provide "toolbar" "1.0")
(princ)
