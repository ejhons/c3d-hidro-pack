;;; ============================================================
;;; objeto_generico.lsp - OBJETO HIDRAULICO GENERICO (REFERENCIA DE LEITURA)
;;;
;;; Objetivo: mostrar, no menor arquivo possivel, COMO um objeto e escrito:
;;;   A. como registrar o tipo no sistema (cada argumento explicado)
;;;   B. como selecionar uma entidade do Civil 3D e transforma-la nesse objeto
;;;
;;; NAO esta no HYDRO:Manifest e nao e carregado pelo sistema. Para usar de
;;; verdade, copie para plugins/models/<nome>.lsp, troque o prefixo GEN e inclua
;;; no manifesto (veja docs/template_objeto.lsp e a skill hydro-model).
;;;
;;; STATUS: nada daqui foi executado no AutoCAD/Civil 3D. A selecao de objetos
;;; do Civil 3D (secao 2 e 9) e a parte mais incerta: confirme os nomes DXF.
;;;
;;; ESQUELETO UNICO (vale para TODO objeto, bacia inclusive; ver docs/plano_esqueleto_unico.md)
;;;   1. SELECIONA a entidade principal              (entsel)
;;;   2. VINCULOS: percorre as definicoes de PARAMS e pede cada entidade de apoio
;;;      (ex.: talvegue). Enter = nao informar; o dado vira campo MANUAL
;;;   3. CARACTERIZA o que o desenho diz, usando a entidade e os vinculos
;;;                                                  (GEN:Caracterizar -> CARACT)
;;;   4. pergunta os ATRIBUTOS e os CARACT que ficaram sem valor (manuais)
;;;   5. GRAVA (OBJ:Cadastrar) e emite "objeto.cadastrado"
;;; CADASTRAR NUNCA CALCULA. tc, vazao, capacidade... so nascem no comando de
;;; calculo (CALCULAOBJETO) e vao para RESULT. O cadastro so guarda o que o
;;; usuario escolheu (ex.: o METODO do tc e seus parametros, em ATRIB).
;;; Depois disso o objeto aparece em OBJETO, LIGAR, CALCULAOBJETO, TABELAS etc.
;;; sem nenhuma outra alteracao no sistema.
;;;
;;; OS QUATRO LUGARES ONDE UM DADO PODE MORAR (decida antes de escrever):
;;;   ATRIB   o USUARIO define        (diametro, rugosidade, nome do material)
;;;   CARACT  o DESENHO informa       (comprimento, cota, area, posicao)
;;;   RESULT  o CALCULO produz        (vazao, capacidade, velocidade)
;;;   PARAMS  handle de OUTRO objeto  (so a ligacao; quase nunca voce mexe)
;;; ============================================================
(vl-load-com)


;;; ------------------------------------------------------------
;;; 1. UTILITARIOS
;;; Funcoes pequenas, sem regra de negocio.
;;; ------------------------------------------------------------
;; Resultado de erro padrao dos calculos: uma alist com a chave "ERRO".
(defun GEN:_Erro (msg)
  (list (cons "ERRO" msg))
)

;; Executa fn (sem argumentos) protegida; devolve o valor ou nil se falhar.
;; Cada acesso a COM / curvas / entget deve passar por aqui.
(defun GEN:_Try (fn / r)
  (setq r (vl-catch-all-apply fn nil))
  (if (vl-catch-all-error-p r) nil r)
)


;;; ------------------------------------------------------------
;;; 2. GEOMETRIA (CARACTERIZACAO)
;;; Le a entidade selecionada e devolve o que o DESENHO sabe dela.
;;; O sistema chama esta funcao sozinho ao cadastrar (capacidade
;;; "CARACTERIZA") e grava o resultado em CARACT.
;;;
;;; Regras: recebe o ename e os VINCULOS informados; nao pergunta nada;
;;; devolve alist SEM pares nil (nunca grave valor nil); nil se nao leu nada.
;;; O que nao puder ser lido (vinculo nao informado, ponto fora da superficie)
;;; simplesmente NAO aparece; o cadastro pergunta esse campo ao usuario (secao 4).
;;; ------------------------------------------------------------
;; (fn en vinculos) -> alist gravada em CARACT
;;   vinculos = alist (chave-de-PARAMS . ename) so dos que o usuario informou
(defun GEN:Caracterizar (en vinculos / dxf obj comp)
  (setq dxf (HYDRO:DxfDe en))                       ; "AECC_PIPE", "LINE"...
  (cond
    ;; -- Entidade do Civil 3D: use a propriedade do OBJETO COM (vla-*) --
    ;; Os objetos AECC_* nao tem geometria em DXF util; as propriedades vem do
    ;; COM. Propriedades como Length, StartPoint, EndPoint, InnerDiameterOrWidth
    ;; existem no AeccPipe; confira os nomes no Civil 3D (Object Model).
    ((equal dxf "AECC_PIPE")
      (setq obj (vlax-ename->vla-object en))
      (GEN:_Limpa
        (list
          (cons "COMP" (GEN:_Try (function (lambda () (vlax-get-property obj 'Length)))))
          (cons "DIAM-DESENHO"
            (GEN:_Try (function (lambda () (vlax-get-property obj 'InnerDiameterOrWidth)))))))
    )
    ;; -- Entidade comum (LINE, LWPOLYLINE...): curvas do AutoCAD --
    (T
      (setq comp
        (GEN:_Try
          (function (lambda () (vlax-curve-getDistAtParam en (vlax-curve-getEndParam en))))))
      (GEN:_Limpa (list (cons "COMP" comp)))
    )
  )
)

;; Remove pares de valor nil (nunca persista nil).
(defun GEN:_Limpa (pares)
  (vl-remove-if (function (lambda (x) (null (cdr x)))) pares)
)


;;; ------------------------------------------------------------
;;; 3. LER, GRAVAR, EDITAR, REMOVER
;;; VAZIA DE PROPOSITO: este tipo herda a classe base (objetos.lsp).
;;;   ler       (OBJ:Ler en)               registro completo ou nil
;;;   gravar    (OBJ:Cadastrar en id atrib nome)   ja chama a caracterizacao
;;;   remover   (OBJ:Remover en)
;;; Nao declare "ARMAZENAMENTO". Limpeza propria ao remover: gancho "AO-REMOVER".
;;; ------------------------------------------------------------


;;; ------------------------------------------------------------
;;; 4. CAMPOS (CARACT, PARAMS e ATRIB)
;;; Aqui mora a DEFINICAO dos parametros do usuario (ATRIB). Cada campo e
;;; uma lista:
;;;
;;;     (chave  rotulo  padrao  unidade  [tipo  [opcoes]])
;;;
;;;     chave    texto unico dentro do objeto; e o nome gravado ("DIAM")
;;;     rotulo   texto da pergunta ao usuario ("Diametro")
;;;     padrao   valor inicial quando nada foi informado antes (0.8)
;;;     unidade  texto exibido ("m", "m/m", "" se adimensional)
;;;     tipo     opcional: "real" (padrao), "int" ou "opcoes"
;;;     opcoes   so para tipo "opcoes": as alternativas, ex.: '("PVC" "Concreto") ou um SIMBOLO de funcao
;;;              sem argumentos que devolve a lista na hora da pergunta ('BAC:_IdsTc)
;;;
;;; A MESMA lista e passada para OBJ:RegistrarTipo (secao 8); o sistema usa
;;; ela para perguntar, validar e rotular. Escreva uma vez, num lugar so.
;;; ------------------------------------------------------------
(defun GEN:Campos ()
  (list
    (list "DIAM"     "Diametro"             0.8    "m")
    (list "N"        "Rugosidade (Manning)" 0.013  "")
    (list "DECL"     "Declividade"          0.01   "m/m")
    (list "MATERIAL" "Material"             "Concreto" "" "opcoes" '("Concreto" "PVC" "PEAD"))
  )
)

;;; ---- VINCULOS (PARAMS): entidades de apoio a pedir no cadastro ----
;;; PARAMS so guarda HANDLES de outras entidades. A definicao diz QUAIS tipos de
;;; entidade/objeto cada vinculo aceita; o cadastro interativo percorre a lista
;;; e pede uma selecao para cada um (Enter = pular):
;;;
;;;     (chave  rotulo  aceita  [obrigatorio])
;;;
;;;     chave        nome gravado em PARAMS ("TALVEGUE", "SUPERFICIE")
;;;     rotulo       texto da pergunta
;;;     aceita       lista de nomes DXF e/ou ids de tipo ('("LWPOLYLINE" "AECC_PIPE"))
;;;     obrigatorio  T = nao deixa pular (padrao nil)
;;;
;;; Se o usuario pula, nada e gravado em PARAMS e os CARACT que dependiam dele
;;; viram campos manuais (CARACT-DEFS, abaixo). Capacidade "PARAMS-DEFS".
(defun GEN:VinculosDefs ()
  (list
    (list "APOIO" "Linha de apoio (opcional)" '("LINE" "LWPOLYLINE" "AECC_PIPE"))
  )
)

;;; ---- CARACT manual: o que o usuario digita quando o desenho nao informa ----
;;; Mesmo formato dos campos de ATRIB. So e perguntado o campo que a
;;; caracterizacao NAO devolveu; o valor digitado entra em CARACT e a chave vai
;;; em ("MANUAL" . ("COMP" ...)) para uma nova caracterizacao nao sobrescreve-lo.
;;; Capacidade "CARACT-DEFS".
(defun GEN:CaractDefs ()
  (list
    (list "COMP" "Comprimento" 0.0 "m")
  )
)

;; Pré-definições dpro priedades que dependem da entidade (opcional; capacidade "PADROES").
;; Tem prioridade sobre o padrao fixo do campo. Ex.: diametro do desenho.
;; (fn en) -> alist (chave . valor)
(defun GEN:_PreDefinicoes (en / d)
  (setq d (cdr (assoc "DIAM-DESENHO" (GEN:CaractDe en))))
  (if d (list (cons "DIAM" d)) nil)
)

;; Acessos de leitura (use sempre estes, nunca assoc direto no registro)
(defun GEN:AtribDe (en)  (OBJ:AtribDe en))     ; o que o usuario definiu
(defun GEN:CaractDe (en) (OBJ:CaractDe en))    ; o que o desenho informou
(defun GEN:Atrib (en chave) (cdr (assoc chave (GEN:AtribDe en))))


;;; ------------------------------------------------------------
;;; 5. RESULTADOS (RESULT)
;;; O que e CALCULADO fica em RESULT, em GRUPOS com nome; os campos ficam
;;; PLANOS dentro da entrada do grupo (nunca "CALCULOS", nunca sub-lista).
;;;
;;;   ("RESULT" . (("VAZAO"      . ((entrada ...)))     o que CHEGA
;;;                ("HIDRAULICA" . ((entrada ...)))))   o que ESTE tipo calcula
;;;   entrada = (("METODO" . id) ("TR" . anos) ("Q" . 1.2) ("QCAP" . 3.4) ...)
;;;
;;; Quem grava e o CALCULAOBJETO, com (OBJ:GravarResultado en "HIDRAULICA" entrada).
;;; Aqui so ficam atalhos de leitura.
;;; ------------------------------------------------------------
(defun GEN:Hidraulica (en)  (OBJ:ResultGrupoDe en "HIDRAULICA"))


;;; ------------------------------------------------------------
;;; 6. CALCULOS
;;; FUNCOES PURAS: nao perguntam, nao imprimem, nao gravam. Recebem dados,
;;; devolvem alist de campos planos ou (("ERRO" . msg)).
;;;
;;; ATENCAO: Manning a secao plena de tubo circular e so exemplo do contrato.
;;; Confira formula, unidades e faixa de validade antes de usar em projeto.
;;; ------------------------------------------------------------
;; (fn en ctx params) -> alist de HIDRAULICA
;;   ctx = (("TR" . anos) ("METODO" . id) ("VAZAO" . (("QP" . m3/s) ...)))
(defun GEN:Calcular (en ctx params / diam n s q a r qcap)
  (setq diam (GEN:Atrib en "DIAM"))
  (setq n    (GEN:Atrib en "N"))
  (setq s    (GEN:Atrib en "DECL"))
  (setq q    (cdr (assoc "QP" (cdr (assoc "VAZAO" ctx)))))
  (if (or (not diam) (<= diam 0.0) (not n) (<= n 0.0) (not s) (<= s 0.0) (not q))
    (GEN:_Erro "Informe diametro, n e declividade > 0 e calcule os montantes.")
    (progn
      (setq a (/ (* pi diam diam) 4.0))                       ; area (m2)
      (setq r (/ diam 4.0))                                   ; raio hidraulico (m)
      (setq qcap (* (/ 1.0 n) a (expt r (/ 2.0 3.0)) (sqrt s)))   ; Manning (m3/s)
      (list
        (cons "Q" q)
        (cons "QCAP" qcap)
        (cons "RAZAO" (/ q qcap))
      )
    )
  )
)


;;; ------------------------------------------------------------
;;; 7. RESUMO E FORMATACAO
;;; So devolvem TEXTO; quem desenha no CAD e a view.
;;; ------------------------------------------------------------
;; (fn en) -> lista de linhas (tabelas, etiquetas)
(defun GEN:_Resumo (en)
  (list
    (strcat "Generico: " (OBJ:Nome en))
    (strcat "Diametro: " (HYDRO:FmtReal (GEN:Atrib en "DIAM")) " m")
  )
)

;; toString: UMA string (capacidade "TOSTRING"), usada por OBJETOINFO e alerts
(defun GEN:ToString (en)
  (HYDRO:Join (GEN:_Resumo en) "\n")
)

;; (fn res) -> linhas do resultado de HIDRAULICA
(defun GEN:Formata (res)
  (list
    (strcat "Q = " (rtos (cdr (assoc "Q" res)) 2 3) " m3/s")
    (strcat "Qcap = " (rtos (cdr (assoc "QCAP" res)) 2 3) " m3/s")
  )
)


;;; ------------------------------------------------------------
;;; 8. TIPO NO CATALOGO  (O REGISTRO NO SISTEMA)
;;;
;;; (OBJ:RegistrarTipo  id  nome  descricao  aceita  params  recebe  emite  extras)
;;;
;;;   id         "generico"   texto unico e estavel (vai gravado em cada entidade;
;;;                           NAO mude depois que houver desenhos usando)
;;;   nome       "Objeto generico"   como aparece nos menus
;;;   descricao  texto de uma linha
;;;   aceita     nomes DXF das entidades que podem ser deste tipo. Para ver o
;;;              nome de uma entidade: (HYDRO:DxfDe (car (entsel))) ou
;;;              (cdr (assoc 0 (entget (car (entsel)))))
;;;   params     a lista de campos de ATRIB (secao 4)
;;;   recebe     T se outros objetos podem descarregar nele
;;;   emite      T se ele pode descarregar em outro
;;;   extras     alist de CAPACIDADES, todas opcionais. Cada uma e
;;;              ("NOME" . funcao). O sistema so usa as que existirem:
;;;      "CARACTERIZA"  (fn en vinculos)     -> CARACT          (secao 2)
;;;      "PARAMS-DEFS"  defs (lista)         vinculos a pedir   (secao 4)
;;;      "CARACT-DEFS"  defs (lista)         CARACT manuais     (secao 4)
;;;      "PADROES"      (fn en)              -> padroes de ATRIB (secao 4)
;;;      "CALCULA"      (fn en ctx params)   -> campos de HIDRAULICA (secao 6)
;;;      "FORMATA"      (fn res)             -> linhas           (secao 7)
;;;      "RESUMO"       (fn en)              -> linhas           (secao 7)
;;;      "TOSTRING"     (fn en)              -> string           (secao 7)
;;;      "AO-REMOVER"   (fn en)              -> limpeza propria
;;;      outras (VAZAO-EM, RECALCULA, TEMPO-MODO, REGRA, EDITAR...): veja o
;;;      cabecalho de plugins/objetos.lsp.
;;;
;;; Funcoes citadas com ' (quote) para o catalogo guardar o SIMBOLO: assim
;;; um HYDRORELOAD enxerga a versao nova.
;;; ------------------------------------------------------------
(if (HYDRO:Has "objetos")
  (OBJ:RegistrarTipo
    "generico"
    "Objeto generico"
    "Tubo circular de exemplo: capacidade a secao plena por Manning."
    '("AECC_PIPE" "LINE" "LWPOLYLINE")        ; aceita: tubo do Civil 3D e linhas
    (GEN:Campos)
    T                                         ; recebe afluentes
    T                                         ; descarrega em outro
    (list
      (cons "CARACTERIZA" 'GEN:Caracterizar)
      (cons "PARAMS-DEFS" (GEN:VinculosDefs))
      (cons "CARACT-DEFS" (GEN:CaractDefs))
      (cons "PADROES"     'GEN:_PreDefinicoes)
      (cons "RESUMO"      'GEN:_Resumo)
      (cons "TOSTRING"    'GEN:ToString)
      (cons "CALCULA"     'GEN:Calcular)
      (cons "FORMATA"     'GEN:Formata)
    )
  )
)


;;; ------------------------------------------------------------
;;; 9. COMANDOS E INTERACAO (linha de comando)
;;; Unico lugar com getXXX / entsel / alert.
;;; ------------------------------------------------------------

;; SELECIONAR UMA ENTIDADE (Civil 3D ou comum) QUE ESTE TIPO ACEITA.
;;   retorno: ename ou nil (cancelou, nada sob o clique, ou tipo nao aceito)
;;
;; entsel funciona com objetos do Civil 3D (AECC_PIPE, AECC_STRUCTURE,
;; AECC_ALIGNMENT...): devolve (ename ponto). Se o objeto estiver dentro de
;; bloco/xref use nentsel. Para o usuario selecionar VARIOS de uma vez, use
;;   (ssget '((0 . "AECC_PIPE")))    ; so tubos, e filtra pela lista do tipo
(defun GEN:Selecionar (/ sel en dxf aceitos)
  (setq sel (entsel "\nSelecione o tubo ou linha: "))
  (if sel
    (progn
      (setq en  (car sel))
      (setq dxf (HYDRO:DxfDe en))
      (setq aceitos (OBJ:Cap "generico" "ACEITA"))
      (if (member dxf aceitos)
        en
        (progn
          (princ (strcat "\nEntidade " dxf " nao aceita por este tipo."))
          nil
        )
      )
    )
    nil
  )
)

;; GEN:Cadastrar: seleciona -> caracteriza -> pergunta ATRIB -> grava.
;; E o fluxo completo "selecionar um objeto do Civil e definir como objeto".
;;   OBJ:CadastroInterativoTipo faz os passos 2 e 3 (caracteriza, pergunta
;;   os campos de ATRIB com padroes, grava e emite "objeto.cadastrado").
(defun GEN:Cadastrar (/ en novo)
  (setq en (GEN:Selecionar))
  (if en
    (progn
      (setq novo (OBJ:CadastroInterativoTipo en "generico"))
      (if novo (alert (GEN:ToString en)))
    )
  )
  (princ)
)

;; Comandos padrao de todo objeto (arquitetura 18b). Na pratica os tres
;; ultimos sao uma linha cada, chamando os fluxos OPV:* (views/objetos_padrao_view):
;;   (defun c:GENERICOCAD ()  (GEN:_Padrao 'OPV:Cadastrar))   ; cadastra/edita
;;   (defun c:GENERICOS ()    (GEN:_Padrao 'OPV:Listar))      ; lista
;;   (defun c:GENERICOINFO () (GEN:_Padrao 'OPV:Info))        ; mostra
;;   (defun c:GENERICOZOOM () (GEN:_Padrao 'OPV:Zoom))        ; localiza
;; Aqui, para ficar autocontido, so o cadastro com a selecao explicita:
(defun c:GENERICOCAD ()
  (GEN:Cadastrar)
)

(HYDRO:Provide "generico" "1.0")
(princ)
