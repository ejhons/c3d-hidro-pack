;;; ============================================================
;;; models/estrutura.lsp - MODELO ESTRUTURA (EST:)
;;;
;;; Modelo UNICO para poco de visita, caixa, ala, boca de lobo... O que muda de uma
;;; estrutura para outra e o TIPO, definido num CATALOGO (HYDRO.TIPOS.ESTRUTURA) e a
;;; CLASSE do tipo, que sabe calcular. Aceita entidade do Civil 3D (AECC_STRUCTURE), bloco,
;;; circulo ou ponto.
;;;
;;; ATOMIZADO (como as seccoes de sarjeta e de tubo): este arquivo e so o OBJETO. O resto e
;;; cada um no seu arquivo:
;;;   plugins/tipo_estrutura.lsp           catalogo de tipos (criar, editar, remover) e de CLASSES
;;;   plugins/registry/estrutura_passagem.lsp   classe "passagem": poco, caixa, ala; perda de carga
;;;   plugins/registry/estrutura_boca_lobo.lsp  classe "boca-lobo": captacao por metodo
;;;   plugins/registry/estrutura_dissipador.lsp classe "dissipador": balanco de energia por metodo
;;;   plugins/registry/dissipacao.lsp      metodos de dissipacao ("informado"; brecha p/ equacoes)
;;;   plugins/registry/captacao.lsp        metodos de captacao ("unitaria"; brecha p/ equacoes)
;;;   views/tipo_estrutura_view.lsp        comandos do catalogo
;;; O model nao conhece as formulas: acha a classe do tipo (catalogo "classe-estrutura") e chama
;;; o CALCULA e o FORMATA dela. Classe nova = arquivo novo em registry/, sem alterar este.
;;;
;;; ESTRUTURA DO ARQUIVO (padrao dos models; ver .claude/skills/hydro-model)
;;;   1. UTILITARIOS
;;;   2. GEOMETRIA (CARACTERIZACAO)
;;;   3. LER, GRAVAR, EDITAR, REMOVER
;;;   4. CAMPOS (CARACT, PARAMS e ATRIB)
;;;   5. RESULTADOS (RESULT)
;;;   6. CALCULOS                             despacho para a classe + dados dos montantes
;;;   7. RESUMO E FORMATACAO
;;;   8. TIPO NO CATALOGO
;;;   9. COMANDOS E INTERACAO (ESTRUTURACAD, ESTRUTURAEDITA, ESTRUTURAS, ESTRUTURAINFO,
;;;                            ESTRUTURAZOOM) e AUDITORIA
;;;   toString: EST:ToString (secao 7), tambem a capacidade "TOSTRING" do tipo
;;;
;;; REGISTRO (formato padrao, docs/arquitetura.md secao 18)
;;;   ATRIB   TIPO-EST  id do tipo no catalogo (TIPOESTRUTURA)
;;;           QTD       quantidade de bocas (boca de lobo: 1 simples, 2 dupla, 3 tripla)
;;;   CARACT  (nada: a estrutura nao tem geometria usada no calculo)
;;;   RESULT  por CENARIO. O core de ligacao grava ENTRADA e VAZAO (repasse de vazao e tempo
;;;           dos montantes); a classe do tipo acrescenta os grupos dela (ver cada arquivo de
;;;           classe) e o AVISOS.
;;; ============================================================
(vl-load-com)


;;; ------------------------------------------------------------
;;; 1. UTILITARIOS
;;; ------------------------------------------------------------
(defun EST:_Erro (msg)
  (list (cons "ERRO" msg))
)


;;; ------------------------------------------------------------
;;; 2. GEOMETRIA (CARACTERIZACAO)
;;; ------------------------------------------------------------
;; A estrutura nao tem geometria usada no calculo: sem CARACTERIZA (CARACT fica vazio).


;;; ------------------------------------------------------------
;;; 3. LER, GRAVAR, EDITAR, REMOVER
;;; ------------------------------------------------------------
;; HERDA a porta de armazenamento da classe base (objetos.lsp): ler OBJ:Ler/OBJ:Registro,
;; gravar OBJ:GravaRegistro, cadastro generico (OBJ:CadastrarCom; ESTRUTURACAD) e um campo
;; (ESTRUTURAEDITA), remover OBJ:Remover. Nada proprio a declarar.


;;; ------------------------------------------------------------
;;; 4. CAMPOS (CARACT, PARAMS e ATRIB)
;;; ------------------------------------------------------------
;; ATRIB (o usuario define): (chave rotulo padrao unidade [tipo [opcoes]])
(defun EST:_AtribDefs ()
  (list
    (list "TIPO-EST" "Id do tipo de estrutura (TIPOESTRUTURA)" 0 "" "int")
    (list "QTD" "Quantidade de bocas (boca de lobo: 1 simples, 2 dupla, 3 tripla)" 1 "" "int")
  )
)

;; PADROES de ATRIB: o tipo atual do catalogo
(defun EST:_Padroes (en)
  (if (HYDRO:Has "tipo-estrutura")
    (list (cons "TIPO-EST" (TES:TipoAtualId)))
    nil
  )
)

;; tipo (id ("k" . v) ...) do catalogo pelo id, ou nil (sem o plugin do catalogo, nil)
(defun EST:_Tipo (id)
  (if (and id (HYDRO:Has "tipo-estrutura")) (TES:_Tipo id) nil)
)

;; entrada da classe (catalogo "classe-estrutura") do tipo, ou nil
(defun EST:_Classe (tipo)
  (if (and tipo (HYDRO:Has "tipo-estrutura")) (TES:Classe (TES:Val "classe" tipo)) nil)
)


;;; ------------------------------------------------------------
;;; 5. RESULTADOS (RESULT)
;;; ------------------------------------------------------------
;; "VALOR" de um grupo do cenario (ou nil); para AVISOS, a lista de textos
(defun EST:_V (en cenario grupo)
  (HYDRO:Val "VALOR" (OBJ:ResultGrupoDe en cenario grupo))
)


;;; ------------------------------------------------------------
;;; 6. CALCULOS
;;; ------------------------------------------------------------
;; (nao puro: le os montantes) maior velocidade, maior lamina e maior Froude dos objetos que
;; descarregam neste, no cenario: (("V" . m/s|nil) ("Y" . m|nil) ("FR" . numero|nil)). Sem o
;; plugin de ligacao, nil nos tres.
(defun EST:_Montantes (en cenario / v y fr m x)
  (if (HYDRO:Has "ligacao")
    (foreach m (LIG:Afluentes en)
      (setq x (HYDRO:Val "VALOR" (OBJ:ResultGrupoDe m cenario "VELOCIDADE")))
      (if (and x (or (null v) (> x v))) (setq v x))
      (setq x (HYDRO:Val "VALOR" (OBJ:ResultGrupoDe m cenario "ALTURA_LAMINA")))
      (if (and x (or (null y) (> x y))) (setq y x))
      (setq x (HYDRO:Val "VALOR" (OBJ:ResultGrupoDe m cenario "FROUDE")))
      (if (and x (or (null fr) (> x fr))) (setq fr x))
    )
  )
  (list (cons "V" v) (cons "Y" y) (cons "FR" fr))
)

;; Capacidade CALCULA: acha a classe do tipo e chama o CALCULA dela com o ctx acrescido de
;; "MONTANTES". Devolve GRUPOS ((grupo . campos) ...) ou (("ERRO" . msg)). Quem grava e
;; LIG:CalcularCore (junto com ENTRADA e VAZAO).
(defun EST:Calcular (en ctx params / dados id tipo cl q)
  (setq dados (OBJ:AtribDe en))
  (setq id (cdr (assoc "TIPO-EST" dados)))
  (setq tipo (EST:_Tipo id))
  (setq cl (EST:_Classe tipo))
  (setq q (cdr (assoc "QP" (cdr (assoc "ENTRADA" ctx)))))
  (cond
    ((not (HYDRO:Has "tipo-estrutura"))
      (EST:_Erro "Plugin do catalogo de tipos (tipo_estrutura.lsp) nao carregado."))
    ((not tipo)
      (EST:_Erro
        (strcat "Tipo " (if id (itoa id) "?")
                " nao cadastrado. Edite o objeto (ESTRUTURAEDITA) ou crie o tipo (CRIATIPOESTRUTURA).")))
    ((not cl)
      (EST:_Erro
        (strcat "Classe '" (TES:Val "classe" tipo) "' nao carregada (plugins/registry/estrutura_*.lsp).")))
    ((or (not q) (<= q 0.0))
      (EST:_Erro "Nao ha vazao afluente: ligue tubos ou outros objetos calculados a esta estrutura (LIGAR)."))
    (T
      (apply (cdr (assoc "CALCULA" cl))
        (list en
              (append ctx (list (cons "MONTANTES" (EST:_Montantes en (cdr (assoc "CENARIO" ctx))))))
              tipo dados))
    )
  )
)


;;; ------------------------------------------------------------
;;; 7. RESUMO E FORMATACAO (linhas de texto; quem desenha e a view)
;;; ------------------------------------------------------------
;; linhas do resultado de um cenario (capacidade FORMATA: (fn en cenario)): cabecalho, as
;; linhas da classe e os avisos
(defun EST:Formata (en cenario / dados tipo cl fn linhas av)
  (setq dados (OBJ:AtribDe en))
  (setq tipo (EST:_Tipo (cdr (assoc "TIPO-EST" dados))))
  (setq cl (EST:_Classe tipo))
  (setq fn (if cl (cdr (assoc "FORMATA" cl)) nil))
  (setq linhas
    (list
      (strcat "Q = " (rtos (EST:_V en cenario "VAZAO") 2 3) " m3/s   tc = "
              (rtos (HYDRO:Val "TC" (OBJ:ResultGrupoDe en cenario "VAZAO")) 2 1) " min   "
              (if tipo (TES:Val "nome" tipo) "tipo ?"))
    )
  )
  (if fn (setq linhas (append linhas (apply fn (list en cenario)))))
  (foreach av (EST:_V en cenario "AVISOS")
    (setq linhas (append linhas (list (strcat "ATENCAO: " av))))
  )
  linhas
)

(defun EST:Resumo (en / dados id tipo linhas c)
  (setq dados (OBJ:AtribDe en))
  (setq id (cdr (assoc "TIPO-EST" dados)))
  (setq tipo (EST:_Tipo id))
  (setq linhas
    (list
      (strcat "Estrutura: " (OBJ:Nome en))
      (strcat "Handle: " (HYDRO:Handle en))
      (if tipo
        (strcat (TES:Rotulo tipo)
                (if (equal (TES:Val "classe" tipo) "boca-lobo")
                  (strcat "   quantidade: " (itoa (if (cdr (assoc "QTD" dados)) (cdr (assoc "QTD" dados)) 1)))
                  ""))
        (strcat "Tipo " (if id (itoa id) "?") " (nao cadastrado)"))
      (strcat "Afluentes: " (itoa (length (LIG:Afluentes en))))
    )
  )
  (foreach c (OBJ:CenariosDe en)
    (if (EST:_V en c "VAZAO")
      (setq linhas
        (append linhas
          (list
            (strcat "Cenario " c (if (OBJ:Obsoleto en c) " (DESATUALIZADO)" "")
                    ":  Q = " (rtos (EST:_V en c "VAZAO") 2 3) " m3/s"
                    (if (EST:_V en c "PERDA_CARGA")
                      (strcat "   dH = " (rtos (EST:_V en c "PERDA_CARGA") 2 4) " m") "")
                    (if (EST:_V en c "CAPACIDADE")
                      (strcat "   Qcap = " (rtos (EST:_V en c "CAPACIDADE") 2 3) " m3/s") "")))))
    )
  )
  linhas
)

;; toString da estrutura: texto multilinha. Capacidade "TOSTRING" do tipo.
(defun EST:ToString (en)
  (HYDRO:Join (EST:Resumo en) "\n")
)


;;; ------------------------------------------------------------
;;; 8. TIPO NO CATALOGO (declaracao)
;;; ------------------------------------------------------------
(if (HYDRO:Has "objetos")
  (OBJ:RegistrarTipo
    "estrutura"
    "Estrutura"
    "Poco de visita, caixa, ala ou boca de lobo (tipos no catalogo TIPOESTRUTURA)."
    '("AECC_STRUCTURE" "INSERT" "CIRCLE" "POINT" "BLOCK")
    (EST:_AtribDefs)
    T
    T
    (list
      (cons "PADROES" 'EST:_Padroes)
      (cons "RESUMO" 'EST:Resumo)
      (cons "TOSTRING" 'EST:ToString)
      (cons "CALCULA" 'EST:Calcular)
      (cons "TEMPO-MODO" "percurso")
      (cons "FORMATA" 'EST:Formata)
    )
  )
)


;;; ------------------------------------------------------------
;;; 9. COMANDOS E INTERACAO (linha de comando)
;;; ------------------------------------------------------------
;; Comandos padrao do objeto (docs/arquitetura.md secao 18b): fluxos genericos de
;; views/objetos_padrao_view.lsp. Calculo e ligacoes: CALCULAOBJETO e LIGAR. Catalogo de tipos:
;; views/tipo_estrutura_view.lsp.
(defun EST:_Padrao (fn)
  (if (HYDRO:Has "objetos-padrao-view")
    (apply fn (list "estrutura"))
    (alert "Comandos de objeto indisponiveis: carregue objetos_padrao e a view dele.")
  )
  (princ)
)

(defun c:ESTRUTURACAD ()   (EST:_Padrao 'OPV:Cadastrar))
(defun c:ESTRUTURAEDITA () (EST:_Padrao 'OPV:EditaCampo))
(defun c:ESTRUTURAS ()     (EST:_Padrao 'OPV:Listar))
(defun c:ESTRUTURAINFO ()  (EST:_Padrao 'OPV:Info))
(defun c:ESTRUTURAZOOM ()  (EST:_Padrao 'OPV:Zoom))

;;; ------------------------------------------------------------
;;; AUDITORIA (catalogo "auditoria"; ver plugins/auditoria.lsp)
;;; ------------------------------------------------------------
;; problemas: ("TIPO-INEXISTENTE" ename id) - estrutura cujo tipo nao esta no catalogo
(defun EST:_AudTipo (/ out en id)
  (foreach en (OBJ:ListaTipo "estrutura")
    (setq id (cdr (assoc "TIPO-EST" (OBJ:AtribDe en))))
    (if (and id (HYDRO:Has "tipo-estrutura") (not (EST:_Tipo id)))
      (setq out (append out (list (list "TIPO-INEXISTENTE" en id))))
    )
  )
  out
)

(defun EST:_TxtTipo (p)
  (strcat "Estrutura " (OBJ:Nome (nth 1 p)) " usa o tipo " (itoa (nth 2 p))
          ", que nao esta cadastrado")
)

;; Pergunta UM tipo existente para todas as estruturas com problema
(defun EST:_ReparaTipo (problemas / tipos idx id n p en)
  (setq tipos (TES:Tipos))
  (setq idx
    (HYDRO:Escolher
      (strcat "Tipo a usar nas " (itoa (length problemas)) " estrutura(s) com tipo inexistente:")
      (mapcar 'TES:Rotulo tipos)
      0))
  (setq id (car (nth idx tipos)))
  (setq n 0)
  (foreach p problemas
    (setq en (nth 1 p))
    (if (OBJ:CadastrarCom en "estrutura" (OBJ:_SetChave (OBJ:AtribDe en) "TIPO-EST" id)
          (OBJ:NomeGravado en) nil nil)
      (setq n (1+ n))
    )
  )
  (if (> n 0)
    (princ "\nRode CALCULAOBJETO nessas estruturas: os resultados antigos usaram outro tipo.")
  )
  n
)

(HYDRO:RegAdd "auditoria" "tipo-estrutura"
  (list (cons "NOME" "Tipo das estruturas")
        (cons "VERIFICA" 'EST:_AudTipo)
        (cons "TEXTO" 'EST:_TxtTipo)
        (cons "REPARA" 'EST:_ReparaTipo)))

(HYDRO:Provide "estrutura-obj" "2.0")
(princ)
