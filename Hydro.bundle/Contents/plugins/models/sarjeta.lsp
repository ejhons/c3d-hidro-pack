;;; ============================================================
;;; models/sarjeta.lsp - MODELO SARJETA (SOB:)
;;;
;;; Representa a sarjeta no sistema: comprimento, declividade e secao; calcula
;;; lamina, largura inundada, area molhada e velocidade (Izzard). Uma sarjeta
;;; e um OBJETO QUE RECEBE BACIAS: a mesma polilinha que e o talvegue de uma
;;; bacia pode ser cadastrada como sarjeta (comando OBJETO); as bacias sao
;;; ligadas a ela com LIGAR. So a funcionalidade do objeto fica aqui; comandos
;;; e texto no desenho do fluxo antigo estao em plugins/sarjetas.lsp.
;;;
;;; ESTRUTURA DO ARQUIVO (padrao dos models; ver .claude/skills/hydro-model)
;;;   1. UTILITARIOS
;;;   2. GEOMETRIA (CARACTERIZACAO)
;;;   3. LER, GRAVAR, EDITAR, REMOVER
;;;   4. CAMPOS (CARACT, PARAMS, ATRIB)
;;;   5. RESULTADOS (RESULT)
;;;   6. CALCULOS
;;;   7. RESUMO E FORMATACAO
;;;   8. TIPO NO CATALOGO
;;;   9. COMANDOS E INTERACAO (SARJETACAD, SARJETAS, SARJETAINFO, SARJETAZOOM) e AUDITORIA
;;;   toString: SOB:ToString (secao 7), tambem a capacidade "TOSTRING" do tipo
;;;
;;; REGISTRO (formato padrao, docs/arquitetura.md secao 18)
;;;   ATRIB   SECAO  id de uma secao cadastrada (CRIASECAO)
;;;           N      rugosidade de Manning (0 = usar a da secao)
;;;   CARACT  COMP, DECL   obtidos do desenho (capacidade CARACTERIZA) ou digitados
;;;           (CARACT-DEFS; as chaves digitadas ficam em CARACT "MANUAL"). O CALCULO usa
;;;           o CARACT; antes de calcular, LIG:CalcularCore o atualiza pelo desenho
;;;           (OBJ:AtualizaCaract; flag HYDRO.CARACT.AUTO, comando CARACTAUTO, padrao 1).
;;;   PARAMS  sem vinculos proprios (so JUSANTE, da ligacao)
;;;   RESULT  por CENARIO (docs/plano_resultados_cenarios.md); grupos da sarjeta, campos planos:
;;;           ENTRADA          ("VALOR" . m3/s) ("TC" . min) ("AREA" . m2)   o que chega dos montantes
;;;           VAZAO            ("VALOR" . m3/s) ("TC" . min) ("METODO" ..) ("INPUT" ..)  a saida
;;;           ALTURA_LAMINA    ("VALOR" . m) ("METODO" . "izzard")
;;;           LARGURA_INUNDADA ("VALOR" . m)     AREA_MOLHADA ("VALOR" . m2)
;;;           VELOCIDADE       ("VALOR" . m/s)   PERCURSO ("VALOR" . min)
;;;           AVISOS           ("VALOR" . lista de textos)
;;;           Secao, n, COMP e DECL NAO sao copiados: estao em ATRIB/CARACT.
;;;
;;; SECOES (catalogo HYDRO.SECOES; secao = (id ("h" . m) ("s" . %) ("w" . m) ("n" . manning)))
;;; CALCULO (comando CALCULAOBJETO)
;;;   MONTANTE (derivado do JUSANTE das origens; ligacao.lsp) pode ter bacias E outras sarjetas. A sarjeta e um
;;;   mecanismo ENTRADA -> SAIDA e PRECISA de montante:
;;;     ENTRADA  Q = soma das saidas dos montantes; tc = maior tempo de saida. Sao os
;;;              parametros de entrada do dimensionamento/verificacao (Izzard abaixo).
;;;     tp       percurso = COMP / VELOCIDADE (min), da hidraulica com a Q de entrada
;;;     SAIDA    tc = tc de entrada + tp (modo "percurso"); Q = bacias a montante
;;;              reavaliadas nesse tc maximo, e com a flag geral HYDRO.VAZAO.PRESERVA
;;;              max(Q entrada, Q calculada). Gravada em VAZAO; a entrada em ENTRADA.
;;;   Por isso as sarjetas devem ser calculadas de montante para jusante, no mesmo cenario.
;;;   Izzard: Q = 0.375 (z/n) y^(8/3) S^0.5, z = 100 / caimento(%)
;;;   avisa se a lamina passa do meio-fio ou a largura da secao.
;;; ============================================================
(vl-load-com)


;;; ------------------------------------------------------------
;;; 1. UTILITARIOS
;;; ------------------------------------------------------------
(defun SOB:_Erro (msg)
  (list (cons "ERRO" msg))
)


;;; ------------------------------------------------------------
;;; 2. GEOMETRIA (CARACTERIZACAO)
;;; ------------------------------------------------------------
;; A superficie e guardada pelo HANDLE (sobrevive ao salvar/reabrir o DWG)
(defun SOB:Superficie (/ h)
  (setq h (HYDRO:Get "HYDRO.SURFACE.HANDLE" nil))
  (if h (handent h) nil)
)

(defun SOB:_Comprimento (en / r)
  (setq r
    (vl-catch-all-apply
      (function
        (lambda ()
          (vlax-curve-getDistAtParam en (vlax-curve-getEndParam en))
        )
      )
      nil
    )
  )
  (if (vl-catch-all-error-p r) nil r)
)

(defun SOB:_ElevSuperficie (surf pt / r)
  (setq r
    (vl-catch-all-apply
      'vlax-invoke-method
      (list (vlax-ename->vla-object surf) 'FindElevationAtXY (car pt) (cadr pt))
    )
  )
  (if (vl-catch-all-error-p r) nil r)
)

;; Desnivel entre inicio e fim da polilinha.
;; Com superficie: cotas lidas da superficie. Sem: cotas da propria
;; polilinha (util para polilinhas 3D).
(defun SOB:_Desnivel (en surf / p1 p2 z1 z2)
  (setq p1 (vlax-curve-getStartPoint en))
  (setq p2 (vlax-curve-getEndPoint en))
  (if surf
    (setq z1 (SOB:_ElevSuperficie surf p1)
          z2 (SOB:_ElevSuperficie surf p2))
    (setq z1 (caddr p1)
          z2 (caddr p2))
  )
  (if (and z1 z2) (- z2 z1) nil)
)

;; Caracteristicas obtidas do desenho (gravadas em CARACT ao cadastrar): COMP e,
;; se houver cota nas duas pontas (superficie ou polilinha 3D), DECL. O que nao der
;; para ler simplesmente nao entra: o cadastro pergunta (CARACT-DEFS, secao 4).
;; vinculos: alist (chave . ename) de PARAMS-DEFS; a sarjeta nao tem vinculos
(defun SOB:Caracterizar (en vinculos / comp desn)
  (setq comp (SOB:_Comprimento en))
  (setq desn
    (if comp
      (vl-catch-all-apply 'SOB:_Desnivel (list en (SOB:Superficie)))
      nil))
  (if (vl-catch-all-error-p desn) (setq desn nil))
  (OBJ:_Limpa
    (list
      (cons "COMP" (if (and comp (> comp 0.0)) comp nil))
      (cons "DECL" (if (and comp desn (> comp 0.0)) (/ (abs desn) comp) nil))
    )
  )
)


;;; ------------------------------------------------------------
;;; 3. LER, GRAVAR, EDITAR, REMOVER
;;; ------------------------------------------------------------
;; A sarjeta HERDA a porta de armazenamento da classe base (objetos.lsp):
;;   ler      OBJ:Ler / OBJ:Registro      gravar   OBJ:GravaRegistro
;;   editar   OBJ:Cadastrar (comando OBJETO; ATRIB e CARACT)
;;   remover  OBJ:Remover (emite "objeto.removido" antes de apagar)
;;   editar um campo: comando SARJETAEDITA (OPV:EditaCampo); marca RESULT obsoleto
;; Nada proprio a declarar: sem indice nem evento especiais. Se um dia precisar,
;; declare ("ARMAZENAMENTO" . ...) com as cinco operacoes na secao 8.


;;; ------------------------------------------------------------
;;; 4. CAMPOS (CARACT, PARAMS e ATRIB)
;;; ------------------------------------------------------------
;; Secao: (id ("h" . altura-meio-fio) ("s" . caimento %) ("w" . largura) ("n" . manning))
(defun SOB:_SecaoPadrao ()
  (list 0 (cons "h" 0.15) (cons "s" 3.0) (cons "w" 3.5) (cons "n" 0.013))
)

(defun SOB:Secoes ()
  (HYDRO:Get "HYDRO.SECOES" (list (SOB:_SecaoPadrao)))
)

(defun SOB:SecaoAtualId ()
  (HYDRO:Get "HYDRO.SECAO.ATUAL" 0)
)

(defun SOB:SecaoAtual ()
  (cdr (assoc (SOB:SecaoAtualId) (SOB:Secoes)))
)

;; secao cadastrada (alist h/s/w/n) pelo id, ou nil
(defun SOB:_Secao (id)
  (cdr (assoc id (SOB:Secoes)))
)

;; CARACT que o usuario digita quando o desenho nao informa (formato de ATRIB)
(defun SOB:_CaractDefs ()
  (list
    (list "COMP" "Comprimento" 0.0 "m")
    (list "DECL" "Declividade" 0.0 "m/m")
  )
)

;; padroes de ATRIB na hora de cadastrar: a secao atual do plugin sarjetas
(defun SOB:_Padroes (en)
  (list (cons "SECAO" (SOB:SecaoAtualId)))
)

;; rugosidade efetiva: a do objeto (se > 0) ou a da secao
(defun SOB:_N (dados secao / n)
  (setq n (cdr (assoc "N" dados)))
  (if (and n (> n 0.0)) n (cdr (assoc "n" secao)))
)


;;; ------------------------------------------------------------
;;; 5. RESULTADOS (RESULT)
;;; ------------------------------------------------------------
;; grupos de um cenario: VAZAO (saida) e ALTURA_LAMINA; os demais: OBJ:ResultGrupoDe
(defun SOB:Vazao (en cenario)       (OBJ:ResultGrupoDe en cenario "VAZAO"))

(defun SOB:Lamina (en cenario)      (OBJ:ResultGrupoDe en cenario "ALTURA_LAMINA"))

;;; ------------------------------------------------------------
;;; 6. CALCULOS
;;; ------------------------------------------------------------
;; Izzard: Q = 0.375 * (z/n) * y^(8/3) * S^0.5   ->   y
;; z = 100 / caimento(%)
(defun SOB:LaminaIzzard (q z n s)
  (expt (/ (* q n) (* 0.375 z (expt s 0.5))) (/ 3.0 8.0))
)

;; Devolve os GRUPOS calculados ((grupo . campos) ...) ou (("ERRO" . msg)).
;; Quem grava e LIG:CalcularCore (OBJ:GravarCalculo, uma gravacao so, junto com
;; ENTRADA e VAZAO). ctx = (("CENARIO" ..) ("TR" ..) ("METODO" ..) ("ENTRADA" ("QP" ..) ("TC" ..)))
(defun SOB:Calcular (en ctx params /
                     dados id sec q cr decl comp n h cai w z y larg am vel avisos)
  (setq dados (OBJ:AtribDe en))
  (setq id (cdr (assoc "SECAO" dados)))
  (setq sec (if id (SOB:_Secao id) nil))
  (setq q (cdr (assoc "QP" (cdr (assoc "ENTRADA" ctx)))))
  ;; geometria = o que esta em CARACT (do desenho ou digitado)
  (setq cr (OBJ:CaractDe en))
  (setq decl (cdr (assoc "DECL" cr)))
  (setq comp (cdr (assoc "COMP" cr)))
  (cond
    ((not sec)
      (SOB:_Erro
        (strcat "Secao " (if id (itoa id) "?")
                " nao cadastrada. Edite o objeto (SARJETAEDITA) ou crie a secao (CRIASECAO)."))
    )
    ((or (not q) (<= q 0.0))
      (SOB:_Erro "Nao ha vazao afluente: ligue bacias ou sarjetas calculadas a esta sarjeta (LIGAR).")
    )
    ((or (not decl) (<= decl 0.0))
      (SOB:_Erro
        (strcat "Declividade ausente ou nula. Defina a superficie (ATUALIZASUPERFICIE) ou "
                "digite-a (SARJETAEDITA)."))
    )
    ((or (not comp) (<= comp 0.0))
      (SOB:_Erro "Comprimento ausente. Digite-o (SARJETAEDITA).")
    )
    (T
      (setq n   (SOB:_N dados sec))
      (setq h   (cdr (assoc "h" sec)))
      (setq cai (cdr (assoc "s" sec)))
      (setq w   (cdr (assoc "w" sec)))
      (setq z   (/ 100.0 cai))
      (setq y   (SOB:LaminaIzzard q z n decl))
      (setq larg (* y z))
      (setq am  (/ (* y larg) 2.0))
      (setq vel (/ q am))
      (if (and h (> y h))
        (setq avisos (append avisos (list "lamina maior que a altura do meio-fio")))
      )
      (if (and w (> larg w))
        (setq avisos (append avisos (list "largura inundada maior que a largura da secao")))
      )
      ;; GRUPOS do cenario (campos planos; "VALOR" = o numero principal)
      (list
        (cons "ALTURA_LAMINA" (list (cons "VALOR" y) (cons "METODO" "izzard")))
        (cons "LARGURA_INUNDADA" (list (cons "VALOR" larg)))
        (cons "AREA_MOLHADA" (list (cons "VALOR" am)))
        (cons "VELOCIDADE" (list (cons "VALOR" vel)))
        (cons "PERCURSO" (list (cons "VALOR" (/ comp vel 60.0))))
        (cons "AVISOS" (list (cons "VALOR" avisos)))
      )
    )
  )
)


;;; ------------------------------------------------------------
;;; 7. RESUMO E FORMATACAO (linhas de texto; quem desenha e a view)
;;; ------------------------------------------------------------
;; "VALOR" de um grupo do cenario (ou nil); AVISOS devolve a lista de textos
(defun SOB:_V (en cenario grupo)
  (OBJ:_Val "VALOR" (OBJ:ResultGrupoDe en cenario grupo))
)

(defun SOB:Formata (en cenario / g dados id n linhas av)
  (setq dados (OBJ:AtribDe en))
  (setq id (cdr (assoc "SECAO" dados)))
  (setq n (SOB:_N dados (if id (SOB:_Secao id) nil)))
  (setq linhas
    (list
      (strcat "Q = " (rtos (SOB:_V en cenario "VAZAO") 2 3) " m3/s   "
              "Secao " (if id (itoa id) "?")
              (if n (strcat "   n = " (rtos n 2 4)) ""))
      (strcat "Lamina: " (rtos (SOB:_V en cenario "ALTURA_LAMINA") 2 3) " m   "
              "Largura: " (rtos (SOB:_V en cenario "LARGURA_INUNDADA") 2 2) " m")
      (strcat "Velocidade: " (rtos (SOB:_V en cenario "VELOCIDADE") 2 2) " m/s")
      (strcat "Percurso: " (rtos (SOB:_V en cenario "PERCURSO") 2 2) " min"
              (if (OBJ:_Val "TC" (OBJ:ResultGrupoDe en cenario "ENTRADA"))
                (strcat "   tc de chegada: "
                        (rtos (OBJ:_Val "TC" (OBJ:ResultGrupoDe en cenario "ENTRADA")) 2 1) " min")
                ""))
    )
  )
  (foreach av (SOB:_V en cenario "AVISOS")
    (setq linhas (append linhas (list (strcat "ATENCAO: " av))))
  )
  linhas
)

(defun SOB:Resumo (en / dados id sec linhas cr c)
  (setq dados (OBJ:AtribDe en))
  (setq id (cdr (assoc "SECAO" dados)))
  (setq sec (if id (SOB:_Secao id) nil))
  (setq cr (OBJ:CaractDe en))
  (setq linhas
    (list
      (strcat "Sarjeta: " (OBJ:Nome en))
      (strcat "Handle: " (HYDRO:Handle en))
      (if sec
        (strcat "Secao " (itoa id) ":  h = " (rtos (cdr (assoc "h" sec)) 2 3)
                " m   s = " (rtos (cdr (assoc "s" sec)) 2 2) " %   w = "
                (rtos (cdr (assoc "w" sec)) 2 3) " m   n = "
                (rtos (SOB:_N dados sec) 2 4))
        (strcat "Secao " (if id (itoa id) "?") " (nao cadastrada)")
      )
      (if (and (assoc "COMP" cr) (assoc "DECL" cr))
        (strcat "L = " (rtos (cdr (assoc "COMP" cr)) 2 1) " m   S = "
                (rtos (cdr (assoc "DECL" cr)) 2 4) " m/m"
                (if (member "DECL" (cdr (assoc "MANUAL" cr))) "  (manual)" ""))
        "Geometria indisponivel (use SARJETAEDITA para digitar comprimento/declividade)"
      )
      (strcat "Afluentes: " (itoa (length (LIG:Afluentes en))))
    )
  )
  (setq linhas (append linhas (OBJ:LinhasAtrib en)))
  (foreach c (OBJ:CenariosDe en)
    (if (SOB:_V en c "ALTURA_LAMINA")
      (setq linhas
        (append linhas
          (list
            (strcat "Cenario " c (if (OBJ:Obsoleto en c) " (DESATUALIZADO)" "")
                    ":  y = " (rtos (SOB:_V en c "ALTURA_LAMINA") 2 3)
                    " m   T = " (rtos (SOB:_V en c "LARGURA_INUNDADA") 2 2) " m")))
      )
    )
  )
  linhas
)

;; toString da sarjeta: texto multilinha (separador newline) com secao,
;; geometria, afluentes e calculos. Capacidade "TOSTRING" do tipo.
(defun SOB:ToString (en)
  (HYDRO:Join (SOB:Resumo en) "\n")
)


;;; ------------------------------------------------------------
;;; 8. TIPO NO CATALOGO (declaracao e rotulos)
;;; ------------------------------------------------------------
(HYDRO:SetLabel "HYDRO.SURFACE.HANDLE" "Superficie (handle)" "")
(HYDRO:SetLabel "HYDRO.SECOES" "Secoes de sarjeta cadastradas" "")
(HYDRO:SetLabel "HYDRO.SECAO.ATUAL" "Secao de sarjeta atual (id)" "")


(if (HYDRO:Has "objetos")
  (OBJ:RegistrarTipo
    ;;id
    "sarjeta"
    ; Nome
    "Sarjeta"
    ;Descrição:
    "Recebe bacias; tem secao e rugosidade. A mesma linha do talvegue pode ser a sarjeta."
    ; Aceita:
    '("LINE" "LWPOLYLINE" "POLYLINE" "SPLINE")
    ; Params
    (list (list "SECAO" "Id da secao" 0 "" "int")
          (list "N" "Rugosidade de Manning (0 = a da secao)" 0.0 ""))
    ; Recebe
    T
    ; Emite
    T
    ; Extras
    (list
      (cons "PADROES" 'SOB:_Padroes)
      (cons "CARACTERIZA" 'SOB:Caracterizar)
      (cons "CARACT-DEFS" (SOB:_CaractDefs))
      (cons "RESUMO" 'SOB:Resumo)
      (cons "TOSTRING" 'SOB:ToString)
      (cons "CALCULA" 'SOB:Calcular)
      (cons "TEMPO-MODO" "percurso")
      (cons "FORMATA" 'SOB:Formata)
    )
  )
)

;;; ------------------------------------------------------------
;;; 9. COMANDOS E INTERACAO (linha de comando)
;;; ------------------------------------------------------------
;; Comandos padrao do objeto (docs/arquitetura.md secao 18b). Os fluxos sao os
;; genericos de views/objetos_padrao_view.lsp; aqui so se diz de que tipo e.
;; O calculo e as ligacoes usam os comandos genericos (CALCULAOBJETO, LIGAR...).
(defun SOB:_Padrao (fn)
  (if (HYDRO:Has "objetos-padrao-view")
    (apply fn (list "sarjeta"))
    (alert "Comandos de objeto indisponiveis: carregue objetos_padrao e a view dele.")
  )
  (princ)
)

(defun c:SARJETACAD ()  (SOB:_Padrao 'OPV:Cadastrar))
(defun c:SARJETAEDITA () (SOB:_Padrao 'OPV:EditaCampo))
(defun c:SARJETAS ()    (SOB:_Padrao 'OPV:Listar))
(defun c:SARJETAINFO () (SOB:_Padrao 'OPV:Info))
(defun c:SARJETAZOOM () (SOB:_Padrao 'OPV:Zoom))

;;; ------------------------------------------------------------
;;; AUDITORIA (catalogo "auditoria"; ver plugins/auditoria.lsp)
;;; ------------------------------------------------------------
;; problemas: ("SECAO-INEXISTENTE" ename id) - sarjeta cuja secao nao esta cadastrada
(defun SOB:_AudSecao (/ out en id)
  (foreach en (OBJ:ListaTipo "sarjeta")
    (setq id (cdr (assoc "SECAO" (OBJ:AtribDe en))))
    (if (and id (not (SOB:_Secao id)))
      (setq out (append out (list (list "SECAO-INEXISTENTE" en id))))
    )
  )
  out
)

(defun SOB:_TxtSecao (p)
  (strcat "Sarjeta " (OBJ:Nome (nth 1 p)) " usa a secao " (itoa (nth 2 p))
          ", que nao esta cadastrada")
)

;; Pergunta UMA secao existente para todas as sarjetas com problema
(defun SOB:_ReparaSecao (problemas / secs idx id n p en)
  (setq secs (SOB:Secoes))
  (setq idx
    (HYDRO:Escolher
      (strcat "Secao a usar nas " (itoa (length problemas)) " sarjeta(s) com secao inexistente:")
      (mapcar
        (function
          (lambda (x)
            (strcat "Secao " (itoa (car x))
                    "  h=" (rtos (cdr (assoc "h" (cdr x))) 2 2)
                    "  s=" (rtos (cdr (assoc "s" (cdr x))) 2 1) "%"
                    "  w=" (rtos (cdr (assoc "w" (cdr x))) 2 2))))
        secs)
      0))
  (setq id (car (nth idx secs)))
  (setq n 0)
  (foreach p problemas
    (setq en (nth 1 p))
    (if (OBJ:Cadastrar en "sarjeta"
          (OBJ:_SetChave (OBJ:AtribDe en) "SECAO" id)
          (OBJ:NomeGravado en))
      (setq n (1+ n))
    )
  )
  (if (> n 0)
    (princ "
Rode CALCULAOBJETO nessas sarjetas: os resultados antigos usaram outra secao.")
  )
  n
)

(HYDRO:RegAdd "auditoria" "secao-sarjeta"
  (list (cons "NOME" "Secao das sarjetas")
        (cons "VERIFICA" 'SOB:_AudSecao)
        (cons "TEXTO" 'SOB:_TxtSecao)
        (cons "REPARA" 'SOB:_ReparaSecao)))

(HYDRO:Provide "sarjeta-obj" "2.0")
(princ)
