;;; vlx_flag.lsp - PRIMEIRO arquivo do projeto VLX (hydro.prv).
;;; Avisa o hydro.lsp de que todo o codigo ja esta dentro do VLX e nao deve
;;; ser carregado do disco.
(setq HYDRO:*embedded* T)
(princ)
