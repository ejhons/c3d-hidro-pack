;;; ============================================================
;;; template_objeto.lsp - MODELO PARA CRIAR UM TIPO NOVO DE OBJETO HIDRAULICO
;;;
;;; Principio aberto/fechado: para ter um objeto novo (bueiro, bacia de
;;; detencao, canal...) voce cria UM ARQUIVO NOVO com um cadastro no catalogo
;;; "objeto-hidraulico". Nenhum plugin existente e alterado; as tabelas
;;; (LIGACOES), os comandos (OBJETO, LIGAR, CALCULAOBJETO...) e a validacao
;;; passam a reconhecer o tipo sozinhos.
;;;
;;; PASSOS
;;;   1. Copie para Hydro.bundle/Contents/plugins/models/<nome>.lsp e troque o
;;;      prefixo EXO pelo seu. Mantenha as 9 SECOES, na ordem (verificar.py confere).
;;;   2. Inclua "plugins/models/<nome>" em HYDRO:Manifest (core/core.lsp), DEPOIS de
;;;      "plugins/objetos" (o cadastro chama OBJ:RegistrarTipo ao carregar).
;;;   3. Se o seu tipo depende de outro plugin, cadastre dentro de
;;;      (if (HYDRO:Has "plugin") ...).
;;;   4. Os comandos c: de linha de comando (e as perguntas deles) ficam na secao 9,
;;;      para o objeto funcionar com um unico .lsp. Texto no desenho e dialogos DCL
;;;      vao em views/<nome>_view.lsp. Todo objeto tem um toString (secao 7).
;;;
;;; ESQUELETO UNICO (docs/objeto_generico.lsp explica cada ponto; plano em docs/plano_esqueleto_unico.md):
;;;   - CADASTRAR NUNCA CALCULA: so ATRIB, PARAMS (vinculos) e CARACT; o resultado nasce no calculo
;;;   - nao escreva cadastro interativo: declare PARAMS-DEFS, CARACT-DEFS, CARACTERIZA, PADROES
;;;   - os 5 comandos padrao (CAD, EDITA, S, INFO, ZOOM) sao uma linha cada, via OPV:* (secao 9)
;;;   - editar marca o RESULT como OBSOLETO; so o calculo remove (OBJ:GravarResultado)
;;;
;;; ATENCAO: o calculo abaixo (capacidade a secao plena de um tubo circular
;;; pela formula de Manning) e so um EXEMPLO do contrato. Confira formula,
;;; unidades e limites antes de usar em projeto.
;;;
;;; Regras (veja docs/arquitetura.md):
;;;   - prefixo proprio; nenhuma variavel global; declare todas as locais
;;;   - (and ...) e (or ...) devolvem T ou nil, nunca o valor
;;;   - so ASCII; nao grave pares com valor nil nos dados
;;;   - RESULT guarda GRUPOS com nome (VAZAO, HIDRAULICA, TC...) e os campos
;;;     calculados ficam PLANOS na entrada do grupo; nao ha lista "CALCULOS"
;;; ============================================================
(vl-load-com)


;;; ------------------------------------------------------------
;;; 1. UTILITARIOS
;;; ------------------------------------------------------------
(defun EXO:_Erro (msg)
  (list (cons "ERRO" msg))
)


;;; ------------------------------------------------------------
;;; 2. GEOMETRIA (CARACTERIZACAO)
;;; O que se le do desenho; vira CARACT ao cadastrar.
;;; ------------------------------------------------------------
;; (fn en vinculos) -> alist gravada em CARACT (comprimento, area... o que o desenho informa)
;; vinculos = alist (chave-de-PARAMS . ename); veja docs/objeto_generico.lsp
(defun EXO:Caracterizar (en vinculos / comp)
  (setq comp
    (vl-catch-all-apply
      (function (lambda () (vlax-curve-getDistAtParam en (vlax-curve-getEndParam en))))
      nil))
  (if (vl-catch-all-error-p comp) nil (list (cons "COMP" comp)))
)


;;; ------------------------------------------------------------
;;; 3. LER, GRAVAR, EDITAR, REMOVER
;;; Tipo simples HERDA a porta da classe base (OBJ:Ler, OBJ:GravaRegistro,
;;; OBJ:CadastrarCom, OBJ:Remover). Nao declare ARMAZENAMENTO: para limpeza
;;; propria use o gancho ("AO-REMOVER" . fn); se o tipo monta o proprio
;;; registro, grave com OBJ:Salvar; leia com OBJ:RegistroDe (como a bacia).
;;; ------------------------------------------------------------


;;; ------------------------------------------------------------
;;; 4. CAMPOS (CARACT, PARAMS e ATRIB)
;;; ATRIB = o usuario define (descrito no argumento `params` de
;;; OBJ:RegistrarTipo: chave rotulo padrao unidade [tipo [opcoes]]).
;;; CARACT = o desenho informa. PARAMS = so para ligar a outro objeto (evite).
;;; ------------------------------------------------------------
;; (fn en) -> alist de padroes de ATRIB na hora de cadastrar
(defun EXO:_Padroes (en)
  (list (cons "DIAM" 0.8))
)

;; VINCULOS (PARAMS-DEFS): entidades de apoio pedidas no cadastro, gravadas em PARAMS como
;; handles. (chave rotulo aceita [obrigatorio]); aceita = nomes DXF e/ou ids de tipo; Enter pula.
(defun EXO:_VinculosDefs ()
  (list (list "APOIO" "a linha de apoio (Enter = pular)" '("LINE" "LWPOLYLINE")))
)

;; CARACT digitavel (CARACT-DEFS): perguntado so quando o desenho nao informa. Formato de ATRIB.
(defun EXO:_CaractDefs ()
  (list (list "COMP" "Comprimento" 0.0 "m"))
)

;; (fn tipo-origem tipo-destino) -> nil/T (permitido) ou STRING (motivo)
;; Cada tipo so fala de si: esta regra impede que ESTE tipo receba
;; descargas de sarjetas (exemplo).
(defun EXO:_Regra (tipo-origem tipo-destino)
  (if (and (equal tipo-destino "bueiro") (equal tipo-origem "sarjeta"))
    "Sarjetas nao descarregam diretamente em bueiros; use uma estrutura."
    nil
  )
)


;;; ------------------------------------------------------------
;;; 5. RESULTADOS (RESULT)
;;; Acessos aos grupos de RESULT deste tipo. Quem grava e o CALCULAOBJETO:
;;;   (OBJ:GravarResultado en "VAZAO" entrada)       o que chega
;;;   (OBJ:GravarResultado en "HIDRAULICA" entrada)  o que o tipo calcula
;;; entrada = campos planos + METODO e TR (identidade da entrada).
;;; ------------------------------------------------------------
(defun EXO:Hidraulica (en)  (OBJ:ResultGrupoDe en "HIDRAULICA"))


;;; ------------------------------------------------------------
;;; 6. CALCULOS
;;; Puros: nao perguntam nem imprimem. Devolvem os campos de HIDRAULICA
;;; (alist plana) ou (("ERRO" . msg)).
;;; ------------------------------------------------------------
;; (fn en ctx params)
;;   ctx = (("TR" . anos) ("METODO" . id) ("VAZAO" . (("QP" . m3/s) ...)))
;;         a vazao e a SOMA DOS PICOS das bacias a montante
(defun EXO:Calcular (en ctx params / d diam n s q a r qcap)
  (setq d (OBJ:AtribDe en))
  (setq diam (cdr (assoc "DIAM" d)))
  (setq n    (cdr (assoc "N" d)))
  (setq s    (cdr (assoc "DECL" d)))
  (setq q    (cdr (assoc "QP" (cdr (assoc "VAZAO" ctx)))))
  (if (or (not diam) (<= diam 0.0) (not n) (<= n 0.0) (not s) (<= s 0.0))
    (EXO:_Erro "Informe diametro, n e declividade maiores que zero (OBJETO).")
    (progn
      (setq a (/ (* pi diam diam) 4.0))            ; area (m2)
      (setq r (/ diam 4.0))                        ; raio hidraulico a secao plena (m)
      (setq qcap (* (/ 1.0 n) a (expt r (/ 2.0 3.0)) (sqrt s)))   ; Manning
      (list
        (cons "Q" q)
        (cons "QCAP" qcap)
        (cons "RAZAO" (/ q qcap))
        (cons "AVISOS"
          (if (> q qcap) (list "vazao maior que a capacidade a secao plena") nil))
      )
    )
  )
)


;;; ------------------------------------------------------------
;;; 7. RESUMO E FORMATACAO
;;; Linhas de texto; quem insere no desenho e a view.
;;; ------------------------------------------------------------
;; (fn en) -> linhas de texto para as tabelas
(defun EXO:_Resumo (en / d)
  (setq d (OBJ:AtribDe en))
  (list
    (strcat "Bueiro: " (OBJ:Nome en))
    (strcat "Diametro: " (HYDRO:FmtReal (cdr (assoc "DIAM" d))) " m   n = "
            (HYDRO:FmtReal (cdr (assoc "N" d))) "   S = "
            (HYDRO:FmtReal (cdr (assoc "DECL" d))) " m/m")
    (strcat "Afluentes: " (itoa (length (LIG:Afluentes en))))
  )
)

;; toString do objeto: UMA string (linhas separadas por newline). Capacidade "TOSTRING".
(defun EXO:ToString (en)
  (HYDRO:Join (EXO:_Resumo en) "\n")
)

;; (fn res) -> linhas do resultado (res = campos de HIDRAULICA)
(defun EXO:Formata (res / av linhas)
  (setq linhas
    (list
      (strcat "Q afluente = " (rtos (cdr (assoc "Q" res)) 2 3) " m3/s")
      (strcat "Capacidade (secao plena) = " (rtos (cdr (assoc "QCAP" res)) 2 3) " m3/s")
      (strcat "Q / Qcap = " (rtos (cdr (assoc "RAZAO" res)) 2 2))))
  (foreach av (cdr (assoc "AVISOS" res))
    (setq linhas (append linhas (list (strcat "ATENCAO: " av))))
  )
  linhas
)


;;; ------------------------------------------------------------
;;; 8. TIPO NO CATALOGO
;;; (OBJ:RegistrarTipo id nome descricao aceita params recebe emite extras)
;;; ------------------------------------------------------------
(OBJ:RegistrarTipo
  "bueiro"
  "Bueiro (exemplo)"
  "Tubo circular que recebe a vazao das bacias a montante."
  '("LINE" "LWPOLYLINE")                         ; entidades que podem ser deste tipo
  (list (list "DIAM" "Diametro" 0.8 "m")         ; campos de ATRIB
        (list "N" "Rugosidade de Manning" 0.013 "")
        (list "DECL" "Declividade" 0.01 "m/m"))
  T                                              ; recebe afluentes
  T                                              ; descarrega em outros
  (list
    (cons "CARACTERIZA" 'EXO:Caracterizar)
    (cons "PARAMS-DEFS" (EXO:_VinculosDefs))
    (cons "CARACT-DEFS" (EXO:_CaractDefs))
    (cons "PADROES" 'EXO:_Padroes)
    (cons "REGRA" 'EXO:_Regra)
    (cons "RESUMO" 'EXO:_Resumo)
    (cons "TOSTRING" 'EXO:ToString)
    (cons "CALCULA" 'EXO:Calcular)
    (cons "FORMATA" 'EXO:Formata)
    ;; outras capacidades opcionais (veja objetos.lsp):
    ;;   ("PARAMS-CALCULO" . defs)  perguntas extras do calculo
    ;;   ("VAZAO-EM" . fn)          (fn en metodo tr tc) -> alist do metodo (QP...) se o objeto GERA vazao
    ;;   ("RECALCULA" . fn)       (fn en metodo tr) -> nil ou texto do erro; recalculo sem perguntas dos montantes
    ;;   ("TEMPO-MODO" . "concentracao"|"percurso")  como o tempo de saida combina os montantes
    ;;     (CALCULA pode devolver "PERCURSO" em min; sem CALCULA o objeto so repassa)
    ;;   ("AREA-PROPRIA" . fn)      area contribuinte
    ;;   ("NOME-FN" . fn)           nome para exibir
    ;;   ("DESTINO-PADRAO" . fn)    destino sugerido em LIGAR
    ;;   ("EDITAR" . fn)            edicao propria
    ;;   ("DETECTA" . fn)           reconhece entidades sem cadastro de objeto
    ;;
    ;;   ("AO-REMOVER" . fn)        limpeza propria ao remover o cadastro
    ;;
    ;; ARMAZENAMENTO PROPRIO (so se o tipo guardar FORA da extensao da entidade;
    ;; verificar.py recusa em models/; o registro continua sendo o padrao):
    ;;   ("ARMAZENAMENTO" . (("LER" . fn) ("GRAVAR" . fn) ("LISTAR" . fn)
    ;;                       ("REINDEXAR" . fn) ("REMOVER" . fn)))
    ;; Sem as 5 operacoes o tipo NAO e registrado.
  )
)

;;; ------------------------------------------------------------
;;; 9. COMANDOS E INTERACAO (linha de comando)
;;; Comandos c: proprios do objeto e as perguntas deles (getXXX, alert).
;;; Os 5 comandos padrao do objeto (verificar.py exige; cada um com botao no painel):
;;;   (defun EXO:_Padrao (fn)
;;;     (if (HYDRO:Has "objetos-padrao-view") (apply fn (list "bueiro")) (alert "Carregue objetos_padrao."))
;;;     (princ))
;;;   (defun c:EXEMPLOCAD ()   (EXO:_Padrao 'OPV:Cadastrar))    cadastra/edita (todos os campos)
;;;   (defun c:EXEMPLOEDITA () (EXO:_Padrao 'OPV:EditaCampo))   altera UM campo
;;;   (defun c:EXEMPLOS ()     (EXO:_Padrao 'OPV:Listar))
;;;   (defun c:EXEMPLOINFO ()  (EXO:_Padrao 'OPV:Info))
;;;   (defun c:EXEMPLOZOOM ()  (EXO:_Padrao 'OPV:Zoom))
;;; (troque EXEMPLO pelo nome do arquivo em maiusculas). O calculo e as ligacoes usam os comandos
;;; genericos (CALCULAOBJETO, LIGAR...). Perguntas proprias so se o calculo precisar de dados extras.
;;; ------------------------------------------------------------

(HYDRO:Provide "exemplo-objeto" "1.0")
(princ)
