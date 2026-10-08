;;; ============================================================
;;; build/build.lsp - GERA O BUNDLE DE DISTRIBUICAO (dist/Hydro.bundle)
;;;
;;; Uso (AutoCAD for Windows):
;;;   (load "C:/Dev/Hydro/build/build.lsp")
;;;   (HB:Build "C:/Dev/Hydro" "fas")   ; compila tudo para .fas
;;;   (HB:Build "C:/Dev/Hydro" "vlx")   ; so prepara a pasta; o VLX voce gera
;;;                                     ; com MAKELISPAPP (docs/compilacao.md)
;;;
;;; O que o modo "fas" faz:
;;;   1. cria dist/Hydro.bundle/Contents/{core,plugins,resources/...}
;;;   2. compila hydro.lsp, core/core.lsp e plugins/*.lsp  -> .fas
;;;   3. copia os recursos (.dcl, .sld)
;;;   4. copia o PackageContents.xml trocando hydro.lsp -> hydro.fas
;;;
;;; Observacoes
;;;   - Compila no modo 'st (padrao): e o mais seguro para a arquitetura de
;;;     plugins, que depende de ligacao tardia entre simbolos.
;;;   - O formato do FAS depende de LISPSYS (veja docs/compilacao.md).
;;;   - Este arquivo e so de desenvolvimento: NAO vai para o bundle.
;;; ============================================================
(vl-load-com)

(defun HB:Norm (p)
  (vl-string-right-trim "/" (vl-string-translate "\\" "/" p))
)

(defun HB:Split (s sep / pos out)
  (while (setq pos (vl-string-search sep s))
    (setq out (append out (list (substr s 1 pos))))
    (setq s (substr s (+ pos 1 (strlen sep))))
  )
  (append out (list s))
)

;; Cria o caminho inteiro (C:/a/b/c), nivel por nivel
(defun HB:Mkdirs (path / parts acc p)
  (setq parts (HB:Split (HB:Norm path) "/"))
  (setq acc (car parts))
  (foreach p (cdr parts)
    (setq acc (strcat acc "/" p))
    (if (not (vl-file-directory-p acc))
      (vl-mkdir acc)
    )
  )
  (vl-file-directory-p path)
)

(defun HB:Copy (src dst)
  (HB:Mkdirs (vl-filename-directory dst))
  (if (findfile dst) (vl-file-delete dst))
  (vl-file-copy src dst)
)

(defun HB:Log (msg)
  (princ (strcat "\n[BUILD] " msg))
)

;; Compila src (.lsp) para dst (.fas). Retorna T se o .fas foi gerado.
(defun HB:Compile (src dst / r)
  (HB:Mkdirs (vl-filename-directory dst))
  (if (findfile dst) (vl-file-delete dst))
  (setq r (vl-catch-all-apply 'vlisp-compile (list 'st src dst)))
  (cond
    ((vl-catch-all-error-p r)
      (HB:Log (strcat "ERRO ao compilar " src ": " (vl-catch-all-error-message r)))
      nil
    )
    ((findfile dst)
      (HB:Log (strcat "ok   " dst))
      T
    )
    (T
      (HB:Log (strcat "FALHOU (sem saida): " src))
      nil
    )
  )
)

;; Copia o PackageContents trocando a extensao do ModuleName
(defun HB:CopyPackageContents (src dst ext / f out linha pos)
  (HB:Mkdirs (vl-filename-directory dst))
  (setq f (open src "r"))
  (setq out (open dst "w"))
  (while (setq linha (read-line f))
    (while (setq pos (vl-string-search "./Contents/hydro.lsp" linha))
      (setq linha
        (strcat (substr linha 1 pos)
                "./Contents/hydro" ext
                (substr linha (+ pos 1 (strlen "./Contents/hydro.lsp"))))
      )
    )
    (write-line linha out)
  )
  (close f)
  (close out)
  T
)

(defun HB:Build (raiz modo / src dst csrc cdst falhas f pasta)
  (setq raiz (HB:Norm raiz))
  (setq src  (strcat raiz "/Hydro.bundle"))
  (setq dst  (strcat raiz "/dist/Hydro.bundle"))
  (setq csrc (strcat src "/Contents"))
  (setq cdst (strcat dst "/Contents"))
  (setq falhas 0)

  (cond
    ((not (vl-file-directory-p csrc))
      (HB:Log (strcat "Nao achei " csrc " - confira o caminho da raiz."))
      nil
    )
    ((not (member modo '("fas" "vlx")))
      (HB:Log "Modo invalido. Use \"fas\" ou \"vlx\".")
      nil
    )
    (T
      (HB:Log (strcat "LISPSYS atual = " (itoa (getvar "LISPSYS"))
                      "  (1 = FAS Unicode, nao carrega no AutoCAD 2020 ou anterior)"))
      (if (= modo "fas")
        (progn
          (HB:Mkdirs (strcat cdst "/core"))
          (HB:Mkdirs (strcat cdst "/plugins"))
          (HB:Mkdirs (strcat cdst "/plugins/models"))
          (HB:Mkdirs (strcat cdst "/plugins/registry"))
          (HB:Mkdirs (strcat cdst "/views"))
        )
      )
      (HB:Mkdirs (strcat cdst "/resources/dcl"))
      (HB:Mkdirs (strcat cdst "/resources/slides"))
      (HB:Mkdirs (strcat cdst "/resources/icons"))

      ;; codigo
      (if (= modo "fas")
        (progn
          (if (not (HB:Compile (strcat csrc "/hydro.lsp") (strcat cdst "/hydro.fas")))
            (setq falhas (1+ falhas)))
          (if (not (HB:Compile (strcat csrc "/core/core.lsp") (strcat cdst "/core/core.fas")))
            (setq falhas (1+ falhas)))
          (foreach pasta '("plugins" "plugins/models" "plugins/registry" "views")
            (foreach f (vl-directory-files (strcat csrc "/" pasta) "*.lsp" 1)
              (if (not (HB:Compile (strcat csrc "/" pasta "/" f)
                                   (strcat cdst "/" pasta "/" (vl-filename-base f) ".fas")))
                (setq falhas (1+ falhas)))
            )
          )
        )
        (HB:Log "Modo vlx: gere hydro.vlx com MAKELISPAPP e copie para dist/Hydro.bundle/Contents.")
      )

      ;; recursos
      (foreach f (vl-directory-files (strcat csrc "/resources/dcl") "*.dcl" 1)
        (HB:Copy (strcat csrc "/resources/dcl/" f) (strcat cdst "/resources/dcl/" f))
      )
      (foreach f (vl-directory-files (strcat csrc "/resources/slides") "*.sld" 1)
        (HB:Copy (strcat csrc "/resources/slides/" f) (strcat cdst "/resources/slides/" f))
      )
      (foreach f (append (vl-directory-files (strcat csrc "/resources/icons") "*.bmp" 1)
                         (vl-directory-files (strcat csrc "/resources/icons") "*.png" 1))
        (HB:Copy (strcat csrc "/resources/icons/" f) (strcat cdst "/resources/icons/" f))
      )

      ;; descritor
      (HB:CopyPackageContents
        (strcat src "/PackageContents.xml")
        (strcat dst "/PackageContents.xml")
        (if (= modo "fas") ".fas" ".vlx")
      )

      (HB:Log (strcat "Bundle gerado em " dst))
      (if (> falhas 0)
        (HB:Log (strcat "ATENCAO: " (itoa falhas) " arquivo(s) nao compilaram."))
        (HB:Log "Concluido sem erros.")
      )
      (= falhas 0)
    )
  )
)

(princ "\nBuild carregado. Use: (HB:Build \"C:/caminho/Hydro\" \"fas\")")
(princ)
