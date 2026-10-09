;;; ============================================================
;;; views/menu.lsp - MENU "HYDRO" NA BARRA DE MENUS (MNU:)
;;;
;;; Cria um menu suspenso "Hydro" na barra de menus do AutoCAD/Civil 3D com
;;; um submenu por grupo e um item por acao, usando a API ActiveX de menus
;;; do Visual LISP (AcadMenuGroup / AcadPopupMenu). Os itens vem do MESMO
;;; catalogo "acao-painel" do painel (ver painel.lsp): comando novo com
;;; PNL:Acao = item novo no menu, sem alterar este arquivo.
;;;
;;; QUANDO E CRIADO
;;;   Automaticamente depois que TODOS os plugins carregaram (evento
;;;   "hydro.carregado"), se HYDRO.MENU.AUTO = 1 (padrao). Dentro do menu so
;;;   entram acoes disponiveis (comando definido e plugins exigidos
;;;   carregados). HYDRORELOAD reconstroi.
;;;
;;; SEM DUPLICAR
;;;   Se o menu "Hydro" ja existe (outro desenho, recarga), ele e REAPROVEITADO:
;;;   os itens sao apagados e recriados. Nao grava nada no arquivo de
;;;   personalizacao (nao chama Save); o menu e refeito a cada sessao.
;;;
;;; BARRA DE MENUS OCULTA
;;;   Versoes recentes mostram a ribbon e escondem a barra de menus
;;;   (variavel MENUBAR = 0). O menu existe mesmo assim; HYDROMENU oferece
;;;   mostrar a barra.
;;;
;;; COMANDOS
;;;   HYDROMENU          (re)cria o menu e oferece mostrar a barra de menus
;;;   HYDROMENUREMOVER   tira o menu da barra
;;; CHAVE: HYDRO.MENU.AUTO (1 = criar sozinho)
;;; ============================================================
(vl-load-com)

;;; ------------------------------------------------------------
;;; ESTRUTURA DO MENU (pura)
;;; ------------------------------------------------------------
;; grupos = saida de PNL:_Grupos; disp-fn = funcao dados -> T/nil (acao disponivel).
;; Retorna ((grupo (rotulo . macro) ...) ...), sem grupos vazios.
(defun MNU:_Estrutura (grupos disp-fn / g it itens out)
  (foreach g grupos
    (setq itens nil)
    (foreach it (cdr g)
      (if (apply disp-fn (list (cdr it)))
        (setq itens
          (append itens
            (list (cons (PNL:_Rotulo it)
                        (PNL:_Macro (cdr (assoc "CMD" (cdr it))))))))
      )
    )
    (if itens
      (setq out (append out (list (cons (PNL:_Sanitiza (car g)) itens))))
    )
  )
  out
)

;;; ------------------------------------------------------------
;;; API ACTIVEX DE MENUS
;;; ------------------------------------------------------------
;; Grupo de menus principal: "ACAD" se existir; senao o primeiro.
(defun MNU:_GrupoPrincipal (acad / g achou primeiro)
  (vlax-for g (vla-get-menugroups acad)
    (if (not primeiro) (setq primeiro g))
    (if (and (not achou) (equal (strcase (vla-get-name g)) "ACAD"))
      (setq achou g)
    )
  )
  (if achou achou primeiro)
)

(defun MNU:_AchaMenu (menus nome / p out)
  (vlax-for p menus
    (if (and (not out) (equal (vla-get-name p) nome))
      (setq out p)
    )
  )
  out
)

;; apaga todos os itens do menu (de tras para frente)
(defun MNU:_Limpa (pop / i)
  (setq i (1- (vla-get-count pop)))
  (while (>= i 0)
    (vla-delete (vla-item pop i))
    (setq i (1- i))
  )
)

(defun MNU:_Preenche (pop estrutura / g sub it)
  (vla-addmenuitem pop (vla-get-count pop) "Painel de comandos..." (PNL:_Macro "HYDRO"))
  (vla-addseparator pop (vla-get-count pop))
  (foreach g estrutura
    (setq sub (vla-addsubmenu pop (vla-get-count pop) (car g)))
    (foreach it (cdr g)
      (vla-addmenuitem sub (vla-get-count sub) (car it) (cdr it))
    )
  )
)

(defun MNU:_CriarInterno (/ acad grupo menus pop barra n)
  (setq acad (vlax-get-acad-object))
  (setq grupo (MNU:_GrupoPrincipal acad))
  (setq menus (vla-get-menus grupo))
  (setq pop (MNU:_AchaMenu menus "Hydro"))
  (if pop
    (MNU:_Limpa pop)
    (setq pop (vla-add menus "Hydro"))
  )
  (MNU:_Preenche
    pop
    (MNU:_Estrutura (PNL:_Grupos (HYDRO:RegList "acao-painel")) 'PNL:Disponivel)
  )
  (setq barra (vla-get-menubar acad))
  (if (equal (vla-get-onmenubar pop) :vlax-false)
    (progn
      (setq n (vla-get-count barra))
      ; (vla-insertinmenubar pop barra (max 0 (1- n))) 
      (vla-insertinmenubar pop (max 0 (1- n)))   ; antes do ultimo item (Ajuda)
    )
  )
  T
)

;; Cria/atualiza o menu. Retorna T ou nil (com mensagem).
(defun MNU:Criar (/ r)
  (setq r (vl-catch-all-apply 'MNU:_CriarInterno nil))
  (if (vl-catch-all-error-p r)
    (progn
      (princ
        (strcat "\n[HYDRO] Nao foi possivel criar o menu: "
                (vl-catch-all-error-message r)
                "\n        Use o comando HYDRO (painel de botoes)."))
      nil
    )
    r
  )
)

;; Tira o menu da barra (e esvazia). Retorna T se existia.
(defun MNU:Remover (/ r)
  (setq r
    (vl-catch-all-apply
      (function
        (lambda (/ acad pop)
          (setq acad (vlax-get-acad-object))
          (setq pop
            (MNU:_AchaMenu
              (vla-get-menus (MNU:_GrupoPrincipal acad)) "Hydro"))
          (if pop
            (progn
              (if (equal (vla-get-onmenubar pop) :vlax-true)
                (vla-removefrommenubar pop)
              )
              (MNU:_Limpa pop)
              T
            )
            nil
          )
        )
      )
      nil
    )
  )
  (if (vl-catch-all-error-p r)
    (progn
      (princ (strcat "\n[HYDRO] Nao foi possivel remover o menu: "
                     (vl-catch-all-error-message r)))
      nil
    )
    r
  )
)

(defun MNU:_BarraOculta ()
  (if (= (getvar "MENUBAR") 0) T nil)
)

;;; ------------------------------------------------------------
;;; COMANDOS E INTEGRACAO
;;; ------------------------------------------------------------
(defun c:HYDROMENU (/ op)
  (if (MNU:Criar)
    (progn
      (princ "\n[HYDRO] Menu 'Hydro' criado na barra de menus.")
      (if (MNU:_BarraOculta)
        (progn
          (initget "Sim Nao")
          (setq op
            (getkword "\nA barra de menus esta oculta (MENUBAR = 0). Mostrar agora? [Sim/Nao] <Sim>: "))
          (if (not (equal op "Nao"))
            (setvar "MENUBAR" 1)
          )
        )
      )
    )
  )
  (princ)
)

(defun c:HYDROMENUREMOVER ()
  (if (MNU:Remover)
    (princ "\n[HYDRO] Menu 'Hydro' removido da barra de menus.")
    (princ "\n[HYDRO] O menu 'Hydro' nao estava na barra de menus.")
  )
  (princ)
)

;; Depois que todos os plugins carregaram: cria o menu sozinho
(defun MNU:_OnCarregado (dados)
  (if (and (= (HYDRO:Get "HYDRO.MENU.AUTO" 1) 1)
           (HYDRO:Has "painel"))
    (if (MNU:Criar)
      (if (MNU:_BarraOculta)
        (princ "\n[HYDRO] Menu 'Hydro' criado. A barra de menus esta oculta: MENUBAR = 1 (ou HYDROMENU).")
      )
    )
  )
)

(HYDRO:On "hydro.carregado" "menu" 'MNU:_OnCarregado)

(HYDRO:SetLabel "HYDRO.MENU.AUTO" "Criar o menu Hydro sozinho ao carregar (1 = sim)" "")

;; botoes do painel para os comandos deste plugin
(if (HYDRO:Has "painel")
  (progn
    (PNL:Acao "sis.menu"        "Sistema" 90 80 "Recriar o menu Hydro"  "HYDROMENU" '("menu"))
    (PNL:Acao "sis.menuremover" "Sistema" 90 90 "Remover o menu Hydro"  "HYDROMENUREMOVER" '("menu"))
  )
)

(HYDRO:Provide "menu" "1.0")
(princ)
