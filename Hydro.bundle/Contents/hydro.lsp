;;; ============================================================
;;; hydro.lsp - PONTO DE ENTRADA DO CONJUNTO HYDRO
;;;
;;; E o UNICO arquivo que o AutoCAD precisa carregar. Ele:
;;;   1. descobre a raiz do conjunto (pasta Contents do bundle) -> HYDRO:*dir*
;;;   2. carrega core/core (.fas ou .lsp)
;;;   3. pede ao core para carregar os plugins
;;;
;;; Como a raiz e descoberta (nesta ordem; so vale pasta que contenha o Hydro):
;;;   a) HYDRO:*dir* ja definida antes do load
;;;        (setq HYDRO:*dir* "C:/Dev/Hydro/Hydro.bundle/Contents")
;;;   b) pasta escolhida com o comando HYDRODIR (guardada no Registro do
;;;      Windows, por usuario: HKEY_CURRENT_USER\Software\Hydro  valor "Dir")
;;;   c) caminho de suporte do AutoCAD (o PackageContents.xml acrescenta
;;;      ./Contents a ele)  -> findfile "hydro.vlx|fas|lsp"
;;;   d) pastas padrao do Autoloader (APPDATA, ALLUSERSPROFILE, PROGRAMFILES)
;;;
;;; Comandos definidos aqui (existem mesmo quando a raiz nao foi encontrada):
;;;   HYDRODIR     escolhe/limpa a pasta do Hydro (caixa de dialogo de pasta)
;;;   HYDRORELOAD  recarrega tudo (core + plugins) a partir da raiz atual
;;;
;;; Modo VLX (tudo em um arquivo): o PRV lista vlx_flag.lsp primeiro, depois
;;; core e plugins, e este arquivo por ultimo. Nesse caso HYDRO:*embedded* = T,
;;; nada e carregado do disco; so a raiz e definida (para achar DCL/SLD).
;;; ============================================================
(vl-load-com)

(defun HYDRO:_Norm (p)
  (vl-string-right-trim "/" (vl-string-translate "\\" "/" p))
)

;;; ------------------------------------------------------------
;;; Escolha guardada no Registro do Windows (por usuario)
;;; ------------------------------------------------------------
(defun HYDRO:_RegKey ()
  "HKEY_CURRENT_USER\\Software\\Hydro"
)

(defun HYDRO:_RegLer ()
  (vl-registry-read (HYDRO:_RegKey) "Dir")
)

(defun HYDRO:_RegGravar (dir)
  (vl-registry-write (HYDRO:_RegKey) "Dir" dir)
)

(defun HYDRO:_RegLimpar ()
  (vl-registry-delete (HYDRO:_RegKey) "Dir")
)

;;; ------------------------------------------------------------
;;; Validacao da raiz
;;; ------------------------------------------------------------
;; Uma pasta e raiz valida se contem o ponto de entrada ou o core.
(defun HYDRO:_ValidRoot (dir)
  (if (and dir
           (vl-some
             (function (lambda (n) (findfile (strcat dir "/" n))))
             '("hydro.vlx" "hydro.fas" "hydro.lsp" "core/core.fas" "core/core.lsp")
           )
      )
    dir
    nil
  )
)

;; Aceita a pasta Contents, a pasta Hydro.bundle ou a pasta do repositorio
;; e devolve a pasta Contents correta (ou nil).
(defun HYDRO:_ResolveRoot (sel / p c achou)
  (setq p (HYDRO:_Norm sel))
  (foreach c (list p
                   (strcat p "/Contents")
                   (strcat p "/Hydro.bundle/Contents"))
    (if (and (not achou) (HYDRO:_ValidRoot c))
      (setq achou c)
    )
  )
  achou
)

;;; ------------------------------------------------------------
;;; Descoberta da raiz
;;; ------------------------------------------------------------
(defun HYDRO:FindRoot (/ achou n b p)
  (cond
    ;; a) definida antes do load
    ((and (boundp 'HYDRO:*dir*)
          HYDRO:*dir*
          (HYDRO:_ValidRoot (HYDRO:_Norm HYDRO:*dir*)))
      (HYDRO:_Norm HYDRO:*dir*)
    )
    ;; b) escolhida com HYDRODIR
    ((and (setq p (HYDRO:_RegLer))
          (setq p (HYDRO:_ResolveRoot p)))
      p
    )
    (T
      ;; c) caminho de suporte
      (foreach n '("hydro.vlx" "hydro.fas" "hydro.lsp")
        (if (and (not achou) (setq p (findfile n)))
          (setq achou (HYDRO:_Norm (vl-filename-directory p)))
        )
      )
      ;; d) pastas padrao do Autoloader
      (if (not achou)
        (foreach b (list (getenv "APPDATA")
                         (getenv "ALLUSERSPROFILE")
                         (getenv "PROGRAMFILES"))
          (if (and b (not achou))
            (foreach n '("hydro.vlx" "hydro.fas" "hydro.lsp")
              (setq p
                (strcat (HYDRO:_Norm b)
                        "/Autodesk/ApplicationPlugins/Hydro.bundle/Contents/"
                        n)
              )
              (if (and (not achou) (findfile p))
                (setq achou (HYDRO:_Norm (vl-filename-directory (findfile p))))
              )
            )
          )
        )
      )
      achou
    )
  )
)

;;; ------------------------------------------------------------
;;; Carga
;;; ------------------------------------------------------------
(defun HYDRO:_Boot (/ f)
  (setq HYDRO:*dir* (HYDRO:FindRoot))
  (cond
    ;; modo VLX: tudo ja foi carregado de dentro do VLX
    ((and (boundp 'HYDRO:*embedded*) HYDRO:*embedded*)
      (HYDRO:Provide "hydro" "1.0.0")
      (HYDRO:Log (strcat "Plugins ativos: " (HYDRO:ListaFeatures)))
      (HYDRO:Emit "hydro.carregado" nil)
    )
    ((not HYDRO:*dir*)
      (princ
        (strcat
          "\n[HYDRO] Nao foi possivel localizar a pasta do conjunto."
          "\n        Use o comando HYDRODIR para escolher a pasta Contents."
        )
      )
    )
    (T
      ;; findfile devolve o caminho (string) ou nil. Nao usar (or ...) aqui:
      ;; em AutoLISP ele devolve T, nao o caminho.
      (setq f (findfile (strcat HYDRO:*dir* "/core/core.fas")))
      (if (not f)
        (setq f (findfile (strcat HYDRO:*dir* "/core/core.lsp")))
      )
      (if f
        (progn
          (load f)
          (HYDRO:Provide "hydro" "1.0.0")
          (HYDRO:LoadAll)
        )
        (princ (strcat "\n[HYDRO] core nao encontrado em " HYDRO:*dir* "/core"))
      )
    )
  )
  (princ)
)

;;; ------------------------------------------------------------
;;; Selecao de pasta (caixa de dialogo do Windows)
;;; ------------------------------------------------------------
;; Usa o Shell.Application. Retorna o caminho ou nil (cancelou/indisponivel).
;; Opcao 81 = so pastas do sistema de arquivos (1) + caixa de texto e
;; botao "Criar nova pasta" (80).
(defun HYDRO:_PickFolder (msg / shell folder path)
  (setq shell (vl-catch-all-apply 'vlax-create-object (list "Shell.Application")))
  (if (and shell (not (vl-catch-all-error-p shell)))
    (progn
      (setq folder
        (vl-catch-all-apply
          'vlax-invoke-method
          (list shell 'BrowseForFolder 0 msg 81)
        )
      )
      (if (and folder (not (vl-catch-all-error-p folder)))
        (progn
          (setq path
            (vl-catch-all-apply
              (function
                (lambda ()
                  (vlax-get-property (vlax-get-property folder 'Self) 'Path)
                )
              )
              nil
            )
          )
          (if (vl-catch-all-error-p path) (setq path nil))
        )
      )
      (vl-catch-all-apply 'vlax-release-object (list shell))
      path
    )
    nil
  )
)

;;; ------------------------------------------------------------
;;; COMANDOS
;;; ------------------------------------------------------------
(defun c:HYDRODIR (/ atual gravada op sel dir)
  (setq atual   (if (boundp 'HYDRO:*dir*) HYDRO:*dir* nil))
  (setq gravada (HYDRO:_RegLer))
  (princ (strcat "\nRaiz em uso: " (if atual atual "(nao definida)")))
  (princ (strcat "\nEscolha gravada para este usuario: " (if gravada gravada "(nenhuma)")))
  (initget "Selecionar Limpar")
  (setq op (getkword "\nOpcao [Selecionar/Limpar] <Selecionar>: "))
  (cond
    ((equal op "Limpar")
      (HYDRO:_RegLimpar)
      (princ "\nEscolha removida. Na proxima carga a raiz sera descoberta automaticamente.")
    )
    (T
      (setq sel
        (HYDRO:_PickFolder
          "Selecione a pasta Contents do Hydro (ou a pasta Hydro.bundle)"
        )
      )
      (if (not sel)
        (setq sel
          (getstring T "\nDialogo cancelado ou indisponivel. Digite o caminho da pasta (Enter cancela): ")
        )
      )
      (if (and sel (/= sel ""))
        (progn
          (setq dir (HYDRO:_ResolveRoot sel))
          (if dir
            (progn
              (if (HYDRO:_RegGravar dir)
                (princ "\nEscolha gravada no Registro (vale para os proximos desenhos e sessoes).")
                (princ "\nNao foi possivel gravar no Registro; a escolha vale so nesta sessao.")
              )
              (setq HYDRO:*dir* dir)
              (princ (strcat "\nRaiz definida: " dir))
              (HYDRO:_Boot)
            )
            (alert
              (strcat
                "A pasta escolhida nao contem o Hydro:\n" sel
                "\n\nSelecione a pasta 'Contents' (onde estao hydro.lsp e a pasta core)."
              )
            )
          )
        )
        (princ "\nCancelado.")
      )
    )
  )
  (princ)
)

;; Recarrega core e plugins (use depois de editar qualquer .lsp)
(defun c:HYDRORELOAD ()
  (HYDRO:_Boot)
  (princ)
)

(HYDRO:_Boot)
(princ)