;;; ============================================================
;;; ligacao.lsp - LIGACOES DE DESCARGA ENTRE OBJETOS (LIG:)
;;;
;;; Uma LIGACAO diz que uma ORIGEM descarrega em um DESTINO (receptor):
;;; bacia -> sarjeta, bacia -> bacia, sarjeta -> sarjeta, sarjeta -> trecho...
;;; Qualquer entidade com tipo hidraulico (ver objetos.lsp) pode participar.
;;;
;;; ONDE FICA A INFORMACAO (decisao de projeto)
;;;   O RECEPTOR guarda a lista de MONTANTES no PARAMS do registro padrao dele
;;;   (docs/arquitetura.md secao 18), campo "MONTANTE":
;;;       ("PARAMS" . (("TALVEGUE" . "2F")            ; so a bacia: componente dela
;;;                    ("MONTANTE" . (("30" . T)      ; dicionario handle -> flag
;;;                                   ("31")))))       ; ("31") = ("31" . nil)
;;;   flag T  = o montante CONTRIBUI DIRETAMENTE para o talvegue do receptor (descarrega
;;;             nele, ou seja, compartilha o talvegue); nil = nao contribui (ausente).
;;;   Faz sentido para receptor que concentra (bacia). A ORIGEM nao guarda nada: o
;;;   destino de uma origem e CALCULADO procurando quem a lista. TALVEGUE nao e montante
;;;   (e parte da bacia) e continua em campo proprio.
;;;
;;; O OBJETO COMO MECANISMO: ENTRADA -> SAIDA
;;;   ENTRADA  vem dos montantes: vazao Q = soma das SAIDAS deles, tempo tc = maior tempo
;;;            de saida (hidrograma: futuro). Grupo de RESULT "ENTRADA".
;;;   SAIDA    vazao e tempo que o objeto entrega aos outros. Grupo "VAZAO".
;;;   Bacia sem montante so tem SAIDA (propria). Estrutura/sarjeta precisa de montante: os
;;;   parametros de entrada (Q, tc) alimentam o dimensionamento/verificacao hidraulica.
;;;   Os montantes devem estar calculados ANTES, com o mesmo METODO e TR (a saida deles e
;;;   lida do RESULT, nao recalculada).
;;;
;;; TEMPO DE SAIDA (tc_k = tempo de saida do montante k; tp = tempo proprio)
;;;   concentracao (bacia, tp = tc dela): tc = max( tp ,
;;;                                                 max_k( tc_k + (k contribui ? tp : 0) ) )
;;;                montante que NAO contribui para o talvegue corre em paralelo (maximo);
;;;                o que contribui percorre o talvegue em serie (soma).
;;;   percurso (sarjeta, trecho; tp = tempo de escoamento): tc = max_k( tc_k ) + tp
;;;   Capacidade do tipo "TEMPO-MODO" ("concentracao" ou "percurso", padrao).
;;;
;;; VAZAO DE SAIDA E A FLAG GERAL
;;;   A precipitacao e sempre calculada com o MAIOR tempo (o de saida). Cada bacia a
;;;   montante (e a propria) e reavaliada com o METODO e o TR nesse tempo (capacidade
;;;   "VAZAO-EM") e as vazoes somam: Q_calc. No metodo racional isto e o racional
;;;   composto, Q = i(tc) . soma(C.A)/360; nos demais o tc e propagado do mesmo jeito
;;;   (aproximacao). Como o tempo maior pode REDUZIR a vazao, a flag geral
;;;   HYDRO.VAZAO.PRESERVA (comando PRESERVAVAZAO; padrao ligada) faz
;;;   Q_saida = max( Q_entrada , Q_calc ); desligada, Q_saida = Q_calc.
;;;
;;; REGRAS DE INTEGRIDADE (aplicadas em LIG:Conectar)
;;;   1. Uma origem tem NO MAXIMO UM destino. Ligar de novo a outro destino
;;;      MOVE a ligacao (adiciona no novo e so entao remove do antigo; se a
;;;      remocao falhar, o novo e desfeito). Ligar de novo ao mesmo destino
;;;      so atualiza o flag.
;;;   2. Nao pode ligar a si mesma nem criar CICLO (o destino nao pode estar a
;;;      montante da origem).
;;;   3. Os tipos devem permitir: origem EMITE, destino RECEBE e as REGRAS
;;;      opcionais de cada tipo (que cada tipo define sobre si; ver objetos.lsp).
;;;   4. Referencias a entidades apagadas, tipos que sumiram e origens listadas
;;;      em mais de um receptor (ex.: receptor copiado e colado) sao detectados
;;;      por VALIDARLIGACOES, que tambem corrige.
;;;   Trocar o TIPO do objeto (OBJETO) descarta o PARAMS e, com ele, os montantes.
;;;
;;; EVENTOS EMITIDOS
;;;   "ligacao.criada"   "ORIGEM" "DESTINO" (enames) "ANTERIOR" (ename ou nil)
;;;                      "COMPARTILHA" (T/nil: contribui ao talvegue)
;;;   "ligacao.removida" "ORIGEM" "DESTINO"
;;;   "objeto.calculado" "OBJETO" "TIPO" "METODO" "TR" "RES"
;;; EVENTO ASSINADO
;;;   "objeto.removido" -> desfaz as ligacoes do objeto
;;;
;;; COMANDOS
;;;   LIGAR            origens (varias) -> destino (pergunta o flag se o destino concentra)
;;;   DESLIGAR         tira a(s) origem(ns) do destino atual
;;;   VALIDARLIGACOES  verifica e corrige a integridade
;;;   CALCULAOBJETO    calcula um objeto: entrada, saida e o calculo proprio do tipo
;;;   PRESERVAVAZAO    flag geral: preservar a maior vazao entre entrada e saida
;;; ============================================================
(vl-load-com)

;;; ------------------------------------------------------------
;;; ARMAZENAMENTO NO RECEPTOR (PARAMS "MONTANTE")
;;; ------------------------------------------------------------
;; Montantes do receptor: lista de (handle-da-origem . contribui-ao-talvegue).
;; Um flag nil aparece como ("handle"), isto e, (cons "handle" nil).
(defun LIG:ListaMontante (en)
  (OBJ:_Val "MONTANTE" (OBJ:ParamsDe en))
)

;; funcoes puras sobre a lista de montantes
(defun LIG:_HandlesDe (lista)
  (mapcar 'car lista)
)

;; acrescenta o montante h ou, se ja existe, atualiza o flag (mantem a posicao)
(defun LIG:_AddAfl (lista h flag / novo velho)
  (setq novo (cons h (if flag T nil)))
  (setq velho (assoc h lista))
  (if velho
    (subst novo velho lista)
    (append lista (list novo))
  )
)

(defun LIG:_RemAfl (lista h)
  (vl-remove (assoc h lista) lista)
)

;; Grava a lista de montantes no PARAMS do receptor (lista vazia remove o campo)
;; Retorna T ou nil (entidade sem cadastro de objeto ou gravacao falhou)
(defun LIG:_Salvar (en lista / reg id params)
  (setq reg (OBJ:Registro en))
  (setq id (OBJ:TipoDe en))
  (if (and reg id)
    (progn
      (setq params (OBJ:_SetChave (OBJ:_Val "PARAMS" reg) "MONTANTE" lista))
      (if (OBJ:GravaRegistro id en (OBJ:_SetChave reg "PARAMS" params)) T nil)
    )
    nil
  )
)

;;; ------------------------------------------------------------
;;; CONSULTAS
;;; ------------------------------------------------------------
;; handles dos afluentes de um receptor (como gravados)
(defun LIG:AfluentesH (en)
  (LIG:_HandlesDe (LIG:ListaMontante en))
)

;; T se o montante `origem` contribui diretamente para o talvegue de `receptor`
(defun LIG:Compartilha (receptor origem)
  (if (cdr (assoc (HYDRO:Handle origem) (LIG:ListaMontante receptor))) T nil)
)

(defun LIG:_Existe (h / e)
  (setq e (handent h))
  (if (and e (HYDRO:EntValida e)) e nil)
)

;; enames dos afluentes que ainda existem
(defun LIG:Afluentes (en / out h e)
  (foreach h (LIG:AfluentesH en)
    (setq e (LIG:_Existe h))
    (if e (setq out (append out (list e))))
  )
  out
)

;; objetos do desenho que tem montantes (varre os objetos cadastrados)
(defun LIG:Receptores (/ out e)
  (foreach e (OBJ:Listar)
    (if (LIG:ListaMontante e)
      (setq out (append out (list e)))
    )
  )
  out
)

;; receptores que listam a origem (normalmente 0 ou 1)
(defun LIG:Destinos (origem / ho out r)
  (setq ho (HYDRO:Handle origem))
  (foreach r (LIG:Receptores)
    (if (member ho (LIG:AfluentesH r))
      (setq out (append out (list r)))
    )
  )
  out
)

(defun LIG:Destino (origem)
  (car (LIG:Destinos origem))
)

;; afluentes validos de um handle (usado nos percursos do grafo)
(defun LIG:_AflValidosH (h / e out x)
  (setq e (LIG:_Existe h))
  (if e
    (foreach x (LIG:AfluentesH e)
      (if (LIG:_Existe x) (setq out (append out (list x))))
    )
  )
  out
)

;; Percurso a montante sobre HANDLES (puro: afl-fn = funcao handle -> handles)
(defun LIG:_MontanteH (h afl-fn / visit fila x)
  (setq fila (apply afl-fn (list h)))
  (while fila
    (setq x (car fila))
    (setq fila (cdr fila))
    (if (not (member x visit))
      (progn
        (setq visit (cons x visit))
        (setq fila (append fila (apply afl-fn (list x))))
      )
    )
  )
  (reverse visit)
)

;; Todos os objetos a montante (afluentes, afluentes dos afluentes...)
(defun LIG:Montante (en / out h e)
  (foreach h (LIG:_MontanteH (HYDRO:Handle en) 'LIG:_AflValidosH)
    (setq e (handent h))
    (if e (setq out (append out (list e))))
  )
  out
)

;; Cadeia a jusante (destino, destino do destino...) sem repetir
(defun LIG:Jusante (en / out e visit)
  (setq e (LIG:Destino en))
  (while (and e (not (member e visit)))
    (setq visit (cons e visit))
    (setq out (append out (list e)))
    (setq e (LIG:Destino e))
  )
  out
)

;;; ------------------------------------------------------------
;;; REGRAS
;;; ------------------------------------------------------------
;; regra opcional de um tipo: retorna string (motivo) ou nil
(defun LIG:_Regra (dados-tipo to td / fn r)
  (setq fn (cdr (assoc "REGRA" dados-tipo)))
  (if fn
    (progn
      (setq r (apply fn (list to td)))
      (if (= (type r) 'STR) r nil)
    )
    nil
  )
)

;; nil = a ligacao e permitida; string = motivo da recusa
(defun LIG:MotivoRecusa (origem destino / to td dto dtd msg)
  (cond
    ((not (HYDRO:EntValida origem)) "A origem nao existe mais.")
    ((not (HYDRO:EntValida destino)) "O destino nao existe mais.")
    ((equal origem destino) "Uma entidade nao pode descarregar em si mesma.")
    (T
      (setq to (OBJ:TipoDe origem))
      (setq td (OBJ:TipoDe destino))
      (setq dto (if to (OBJ:TipoDados to) nil))
      (setq dtd (if td (OBJ:TipoDados td) nil))
      (cond
        ((not to) "A origem nao e um objeto hidraulico (use OBJETO).")
        ((not td) "O destino nao e um objeto hidraulico (use OBJETO).")
        ((not (cdr (assoc "EMITE" dto)))
          (strcat "Objetos do tipo '" (OBJ:_NomeTipo to) "' nao descarregam em outros."))
        ((not (cdr (assoc "RECEBE" dtd)))
          (strcat "Objetos do tipo '" (OBJ:_NomeTipo td) "' nao recebem afluentes."))
        ((setq msg (LIG:_Regra dto to td)) msg)
        ((setq msg (LIG:_Regra dtd to td)) msg)
        ((member destino (LIG:Montante origem))
          "A ligacao criaria um ciclo: o destino ja recebe agua da origem.")
        (T nil)
      )
    )
  )
)

;;; ------------------------------------------------------------
;;; LIGAR / DESLIGAR
;;; ------------------------------------------------------------
;; Retorna (("OK" . T) ("ANTERIOR" . ename)) ou (("ERRO" . motivo)).
;; compartilha = T se a origem contribui diretamente para o talvegue do destino (flag do MONTANTE).
;; Se a origem ja tinha outro destino, MOVE (adiciona no novo e remove do
;; antigo; falhando a remocao, o novo e desfeito). Se ja estava neste destino,
;; so atualiza o flag.
(defun LIG:Conectar (origem destino compartilha /
                     motivo ho ja flag antigos falha r gravou)
  (setq motivo (LIG:MotivoRecusa origem destino))
  (setq flag (if compartilha T nil))
  (if motivo
    (list (cons "ERRO" motivo))
    (progn
      (setq ho (HYDRO:Handle origem))
      (setq ja (assoc ho (LIG:ListaMontante destino)))
      (setq antigos (vl-remove destino (LIG:Destinos origem)))
      ;; 1) acrescenta (ou atualiza o flag) no novo receptor
      (if (not (equal ja (cons ho flag)))
        (if (LIG:_Salvar destino (LIG:_AddAfl (LIG:ListaMontante destino) ho flag))
          (setq gravou T)
          (setq falha "Nao foi possivel gravar a ligacao no destino.")
        )
      )
      ;; 2) remove dos antigos
      (if (not falha)
        (foreach r antigos
          (if (not falha)
            (if (not (LIG:_Salvar r (LIG:_RemAfl (LIG:ListaMontante r) ho)))
              (setq falha "Nao foi possivel remover a ligacao anterior.")
            )
          )
        )
      )
      (if falha
        (progn
          ;; desfaz o passo 1
          (if gravou
            (LIG:_Salvar destino
              (if ja
                (LIG:_AddAfl (LIG:ListaMontante destino) ho (cdr ja))
                (LIG:_RemAfl (LIG:ListaMontante destino) ho)))
          )
          (list (cons "ERRO" falha))
        )
        (progn
          (if (or gravou antigos)
            (HYDRO:Emit "ligacao.criada"
              (list (cons "ORIGEM" origem)
                    (cons "DESTINO" destino)
                    (cons "ANTERIOR" (car antigos))
                    (cons "COMPARTILHA" flag)))
          )
          (list (cons "OK" T) (cons "ANTERIOR" (car antigos)))
        )
      )
    )
  )
)

;; Tira a origem de todos os receptores que a listam. Retorna quantos.
(defun LIG:Desconectar (origem / ho n r)
  (setq ho (HYDRO:Handle origem))
  (setq n 0)
  (foreach r (LIG:Destinos origem)
    (if (LIG:_Salvar r (LIG:_RemAfl (LIG:ListaMontante r) ho))
      (progn
        (setq n (1+ n))
        (HYDRO:Emit "ligacao.removida"
          (list (cons "ORIGEM" origem) (cons "DESTINO" r)))
      )
    )
  )
  n
)

;; Ao remover o cadastro de um objeto: desfaz as ligacoes dele
(defun LIG:_OnObjetoRemovido (dados / en)
  (setq en (cdr (assoc "OBJETO" dados)))
  (if en
    (LIG:Desconectar en)
  )
)

;;; ------------------------------------------------------------
;;; ENTRADA, TEMPO DE SAIDA E VAZAO DE SAIDA
;;; ------------------------------------------------------------
;; Modo de tempo do tipo: "concentracao" (bacia) ou "percurso" (padrao)
(defun LIG:_Modo (en / id m)
  (setq id (OBJ:TipoDe en))
  (setq m (if id (OBJ:Cap id "TEMPO-MODO") nil))
  (if m m "percurso")
)

;; Regra do tempo de saida (PURA).
;;   modo      "concentracao" ou "percurso"
;;   tp        tempo proprio do objeto (min)
;;   chegadas  lista de (tc-de-saida-do-montante . contribui-ao-talvegue)
;; concentracao: max( tp , max_k( tc_k + (contribui ? tp : 0) ) )
;; percurso:     max_k( tc_k ) + tp   (nil se nao ha chegadas)
(defun LIG:_TcPuro (modo tp chegadas / r c)
  (if (equal modo "concentracao")
    (progn
      (setq r tp)
      (foreach c chegadas
        (setq r (max r (+ (car c) (if (cdr c) tp 0.0))))
      )
      r
    )
    (if chegadas
      (progn
        (setq r (car (car chegadas)))
        (foreach c chegadas
          (setq r (max r (car c)))
        )
        (+ r tp)
      )
      nil
    )
  )
)

;; Flag geral: preservar a maior vazao entre entrada e saida (padrao: ligada)
(defun LIG:PreservaAtiva ()
  (if (= (HYDRO:Get "HYDRO.VAZAO.PRESERVA" 1) 1) T nil)
)

;; Vazao de saida final (PURA). Retorna (q-final preservada?).
;;   qent  vazao de entrada (soma das saidas dos montantes), ou nil
;;   qcalc vazao calculada na saida (precipitacao no tempo maximo), ou nil
;;   ativo flag geral
(defun LIG:Preserva (qent qcalc ativo)
  (if (and ativo qent qcalc (> qent qcalc))
    (list qent T)
    (list (if qcalc qcalc qent) nil)
  )
)

;; Entrada gravada de um montante: o resultado de SAIDA (grupo VAZAO) de METODO e TR
(defun LIG:Saida (en metodo tr / out r)
  (foreach r (OBJ:GrupoDe en "VAZAO")
    (if (and (equal (OBJ:_Val "METODO" r) metodo)
             (equal (OBJ:_Val "TR" r) tr 1e-9))
      (setq out r)
    )
  )
  out
)

;; ENTRADA do objeto: o que chega dos montantes DIRETOS, lido da saida gravada deles.
;; Retorna (("QP" . soma|nil) ("TC" . maior tempo|nil)
;;          ("CHEGADAS" . ((tc . contribui) ...)) ("ORIGENS" . ((nome . q) ...))
;;          ("FALTAM" . (nomes de montantes sem calculo)) ("AREA" . m2))
;; QP e TC ficam nil se algum montante nao tem saida para este METODO e TR.
(defun LIG:Entrada (en metodo tr / total tc cheg origens faltam m e s c)
  (foreach m (LIG:ListaMontante en)
    (setq e (LIG:_Existe (car m)))
    (if e
      (progn
        (setq s (LIG:Saida e metodo tr))
        (if (and s (OBJ:_Val "QP" s) (OBJ:_Val "TC" s))
          (progn
            (setq total (+ (if total total 0.0) (OBJ:_Val "QP" s)))
            (setq cheg (append cheg (list (cons (OBJ:_Val "TC" s) (cdr m)))))
            (setq origens
              (append origens (list (cons (OBJ:Nome e) (OBJ:_Val "QP" s)))))
          )
          (setq faltam (append faltam (list (OBJ:Nome e))))
        )
      )
    )
  )
  (foreach c cheg
    (setq tc (if tc (max tc (car c)) (car c)))
  )
  (list
    (cons "QP" (if faltam nil total))
    (cons "TC" (if faltam nil tc))
    (cons "CHEGADAS" cheg)
    (cons "ORIGENS" origens)
    (cons "FALTAM" faltam)
    (cons "AREA" (LIG:AreaMontante en))
  )
)

;; Vazao dos objetos a montante (TODOS, transitivamente; NAO inclui o proprio)
;; reavaliada com METODO e TR no tempo tc (capacidade "VAZAO-EM"); as vazoes somam.
;; Retorna (("QP" . total|nil) ("VOLUME" . m3|nil) ("ORIGENS" . ((nome . q) ...))
;;          ("FALTAM" . (nomes sem calculo para este metodo e TR))
;;          ("AREA" . m2 contribuinte total a montante))
(defun LIG:VazaoMontante (en metodo tr tc / total vol volok origens faltam e id fn r)
  (setq volok T)
  (foreach e (LIG:Montante en)
    (setq id (OBJ:TipoDe e))
    (setq fn (if id (OBJ:Cap id "VAZAO-EM") nil))
    (if fn
      (progn
        (setq r (apply fn (list e metodo tr tc)))
        (if (and r (cdr (assoc "QP" r)))
          (progn
            (setq total (+ (if total total 0.0) (cdr (assoc "QP" r))))
            (if (cdr (assoc "VOLUME" r))
              (setq vol (+ (if vol vol 0.0) (cdr (assoc "VOLUME" r))))
              (setq volok nil)
            )
            (setq origens
              (append origens (list (cons (OBJ:Nome e) (cdr (assoc "QP" r))))))
          )
          (setq faltam (append faltam (list (OBJ:Nome e))))
        )
      )
    )
  )
  (list
    (cons "QP" total)
    (cons "VOLUME" (if volok vol nil))
    (cons "ORIGENS" origens)
    (cons "FALTAM" faltam)
    (cons "AREA" (LIG:AreaMontante en))
  )
)

;; Soma das areas contribuintes (m2) dos objetos a montante (tipos com
;; AREA-PROPRIA, como a bacia)
(defun LIG:AreaMontante (en / area e id fn a)
  (setq area 0.0)
  (foreach e (LIG:Montante en)
    (setq id (OBJ:TipoDe e))
    (setq fn (if id (OBJ:Cap id "AREA-PROPRIA") nil))
    (if fn
      (progn
        (setq a (apply fn (list e)))
        (if a (setq area (+ area a)))
      )
    )
  )
  area
)

;;; ------------------------------------------------------------
;;; TEXTOS (arvore de afluentes)
;;; ------------------------------------------------------------
(defun LIG:_Indent (nivel / s)
  (setq s "")
  (repeat nivel (setq s (strcat s "    ")))
  s
)

;; linhas "<- nome [tipo]" com recuo por nivel (protegido contra ciclos)
(defun LIG:_Arvore (en nivel visit / out e m)
  (foreach m (LIG:ListaMontante en)
    (setq e (LIG:_Existe (car m)))
    (if e
      (if (member e visit)
        (setq out
          (append out
            (list (strcat (LIG:_Indent nivel) "<- " (OBJ:Nome e) "  (CICLO!)"))))
        (setq out
          (append out
            (list (strcat (LIG:_Indent nivel) "<- " (OBJ:Nome e)
                          "  [" (OBJ:_NomeTipo (OBJ:TipoDe e)) "]"
                          (if (cdr m) "  (contribui ao talvegue)" "")))
            (LIG:_Arvore e (1+ nivel) (cons e visit))))
      )
    )
  )
  out
)

(defun LIG:LinhasArvore (en)
  (LIG:_Arvore en 0 (list en))
)

(defun LIG:LinhaJusante (en / cadeia)
  (setq cadeia (LIG:Jusante en))
  (if cadeia
    (strcat (OBJ:Nome en) "  ->  "
            (HYDRO:Join (mapcar 'OBJ:Nome cadeia) "  ->  "))
    "(nao descarrega em nenhum objeto)"
  )
)

;;; ------------------------------------------------------------
;;; VALIDACAO
;;; ------------------------------------------------------------
;; Analise PURA. mapa = lista de (receptor-h . (origem-h ...));
;; existe-fn = funcao handle -> T/nil. Retorna lista de problemas:
;;   ("PENDENTE" receptor origem)   origem apagada/inexistente
;;   ("DUPLICADA" origem (receptor ...))  origem listada em mais de um receptor
;;   ("CICLO" receptor)             receptor aparece a montante de si mesmo
(defun LIG:_Analisa (mapa existe-fn / out par r o cont aflf)
  (foreach par mapa
    (foreach o (cdr par)
      (if (not (apply existe-fn (list o)))
        (setq out (append out (list (list "PENDENTE" (car par) o))))
      )
    )
  )
  ;; origens em mais de um receptor
  (foreach par mapa
    (foreach o (cdr par)
      (if (not (assoc o cont))
        (setq cont (append cont (list (cons o nil))))
      )
      (setq cont
        (subst
          (cons o (append (cdr (assoc o cont)) (list (car par))))
          (assoc o cont)
          cont))
    )
  )
  (foreach par cont
    (if (> (length (cdr par)) 1)
      (setq out (append out (list (list "DUPLICADA" (car par) (cdr par)))))
    )
  )
  ;; ciclos
  (setq aflf (function (lambda (h) (cdr (assoc h mapa)))))
  (foreach par mapa
    (if (member (car par) (LIG:_MontanteH (car par) aflf))
      (setq out (append out (list (list "CICLO" (car par)))))
    )
  )
  out
)

;; Analisa o desenho. Acrescenta "SEM-TIPO": origem existe mas nao e mais
;; um objeto hidraulico (cadastro removido ou plugin do tipo ausente...).
;; Retorna lista de problemas (ver LIG:_Analisa).
(defun LIG:Validar (/ mapa r problemas par o e)
  (foreach r (LIG:Receptores)
    (setq mapa (append mapa (list (cons (HYDRO:Handle r) (LIG:AfluentesH r)))))
  )
  (setq problemas (LIG:_Analisa mapa 'LIG:_Existe))
  (foreach par mapa
    (foreach o (cdr par)
      (setq e (LIG:_Existe o))
      (if (and e (not (OBJ:TipoDe e)))
        (setq problemas (append problemas (list (list "SEM-TIPO" (car par) o))))
      )
    )
  )
  problemas
)

(defun LIG:_NomeH (h / e)
  (setq e (handent h))
  (if (and e (HYDRO:EntValida e)) (OBJ:Nome e) (strcat "(apagado " h ")"))
)

(defun LIG:_TextoProblema (p)
  (cond
    ((equal (car p) "PENDENTE")
      (strcat "Afluente apagado: " (nth 2 p) " listado em " (LIG:_NomeH (nth 1 p))))
    ((equal (car p) "SEM-TIPO")
      (strcat "Afluente sem tipo hidraulico: " (LIG:_NomeH (nth 2 p))
              " listado em " (LIG:_NomeH (nth 1 p))))
    ((equal (car p) "DUPLICADA")
      (strcat "Origem em mais de um receptor: " (LIG:_NomeH (nth 1 p))
              " listada em " (HYDRO:Join (mapcar 'LIG:_NomeH (nth 2 p)) ", ")))
    ((equal (car p) "CICLO")
      (strcat "Ciclo de descarga passando por " (LIG:_NomeH (nth 1 p))))
    (T (vl-prin1-to-string p))
  )
)

;; remove a origem (handle) do receptor (handle)
(defun LIG:_RemoveDe (receptor-h origem-h / r)
  (setq r (LIG:_Existe receptor-h))
  (if r
    (LIG:_Salvar r (LIG:_RemAfl (LIG:ListaMontante r) origem-h))
    nil
  )
)

;; Corrige o que da para corrigir. Para DUPLICADA pergunta qual receptor
;; mantem. CICLO nao tem correcao automatica. Retorna quantas correcoes.
(defun LIG:Reparar (problemas / n p idx rs r)
  (setq n 0)
  (foreach p problemas
    (cond
      ((member (car p) '("PENDENTE" "SEM-TIPO"))
        (if (LIG:_RemoveDe (nth 1 p) (nth 2 p)) (setq n (1+ n)))
      )
      ((equal (car p) "DUPLICADA")
        (setq rs (nth 2 p))
        (setq idx
          (HYDRO:Escolher
            (strcat "A origem " (LIG:_NomeH (nth 1 p)) " esta em varios receptores. Manter em:")
            (mapcar 'LIG:_NomeH rs)
            0))
        (foreach r rs
          (if (not (equal r (nth idx rs)))
            (if (LIG:_RemoveDe r (nth 1 p)) (setq n (1+ n)))
          )
        )
      )
    )
  )
  n
)

(defun c:VALIDARLIGACOES (/ problemas op n p)
  (setq problemas (LIG:Validar))
  (if (not problemas)
    (princ "\nLigacoes integras: nenhum problema encontrado.")
    (progn
      (princ (strcat "\n" (itoa (length problemas)) " problema(s) encontrado(s):"))
      (foreach p problemas
        (princ (strcat "\n  - " (LIG:_TextoProblema p)))
      )
      (initget "Sim Nao")
      (setq op (getkword "\nCorrigir o que for possivel? [Sim/Nao] <Nao>: "))
      (if (equal op "Sim")
        (progn
          (setq n (LIG:Reparar problemas))
          (princ (strcat "\n" (itoa n) " correcao(oes) aplicada(s)."))
          (if (assoc "CICLO" problemas)
            (princ "\nCiclos exigem decisao sua: use DESLIGAR em um dos objetos do ciclo.")
          )
        )
      )
    )
  )
  (princ)
)

;; Auditoria geral (HYDROAUDIT): as mesmas verificacoes e correcoes de VALIDARLIGACOES
(HYDRO:RegAdd "auditoria" "ligacoes"
  (list (cons "NOME" "Ligacoes entre objetos")
        (cons "VERIFICA" 'LIG:Validar)
        (cons "TEXTO" 'LIG:_TextoProblema)
        (cons "REPARA" 'LIG:Reparar)))

;;; ------------------------------------------------------------
;;; COMANDOS: LIGAR E DESLIGAR
;;; ------------------------------------------------------------
;; Entidades da selecao que sao objetos hidraulicos
(defun LIG:_Origens (ss / i en out ign)
  (setq i (sslength ss))
  (setq ign 0)
  (while (> i 0)
    (setq i (1- i))
    (setq en (ssname ss i))
    (if (OBJ:TipoDe en)
      (setq out (cons en out))
      (setq ign (1+ ign))
    )
  )
  (if (> ign 0)
    (princ
      (strcat "\n" (itoa ign)
              " entidade(s) ignorada(s): nao sao objetos hidraulicos (use OBJETO)."))
  )
  out
)

;; destino padrao da origem (capacidade DESTINO-PADRAO do tipo), se houver
(defun LIG:_DestinoPadrao (origem / id fn dest)
  (setq id (OBJ:TipoDe origem))
  (setq fn (if id (OBJ:Cap id "DESTINO-PADRAO") nil))
  (setq dest (if fn (apply fn (list origem)) nil))
  (if (and dest (HYDRO:EntValida dest)) dest nil)
)

(defun LIG:_PedeDestino (origens / sel dest)
  (setq sel
    (entsel "\nSelecione o DESTINO (Enter = destino padrao da origem): "))
  (cond
    (sel (car sel))
    ((= (length origens) 1)
      (setq dest (LIG:_DestinoPadrao (car origens)))
      (if (not dest) (princ "\nA origem nao tem destino padrao."))
      dest
    )
    (T
      (princ "\nSelecione um destino (o padrao so vale para uma origem).")
      nil
    )
  )
)

;; destino sem tipo: oferece cadastrar agora
(defun LIG:_GarantirTipo (en / r)
  (if (OBJ:TipoDe en)
    T
    (progn
      (initget "Sim Nao")
      (setq r
        (getkword
          "\nO destino nao e um objeto hidraulico. Cadastrar agora? [Sim/Nao] <Sim>: "))
      (if (equal r "Nao")
        nil
        (if (OBJ:CadastroInterativo en) T nil)
      )
    )
  )
)

;; O destino concentra (ex.: bacia)? Pergunta se os montantes contribuem direto ao talvegue dele.
(defun LIG:_PedeCompartilha (destino / r)
  (if (equal (LIG:_Modo destino) "concentracao")
    (progn
      (initget "Sim Nao")
      (setq r
        (getkword "\nO(s) montante(s) contribui(em) diretamente para o talvegue do destino? [Sim/Nao] <Nao>: "))
      (equal r "Sim")
    )
    nil
  )
)

;; origens = enames de objetos. Pergunta o destino e liga. Retorna quantas.
(defun LIG:LigarInterativo (origens / destino n falhas r o comp)
  (setq destino (LIG:_PedeDestino origens))
  (cond
    ((not destino) 0)
    ((not (LIG:_GarantirTipo destino))
      (princ "\nDestino sem tipo hidraulico: nada foi ligado.")
      0
    )
    (T
      (setq comp (LIG:_PedeCompartilha destino))
      (setq n 0)
      (foreach o origens
        (setq r (LIG:Conectar o destino comp))
        (if (assoc "ERRO" r)
          (setq falhas
            (append falhas
              (list (strcat (OBJ:Nome o) ": " (cdr (assoc "ERRO" r))))))
          (setq n (1+ n))
        )
      )
      (princ
        (strcat "\n" (itoa n) " ligacao(oes) criada(s) com destino em "
                (OBJ:Nome destino) "."))
      (if falhas
        (alert (strcat "Nao foi possivel ligar:\n" (HYDRO:Join falhas "\n")))
      )
      n
    )
  )
)

(defun c:LIGAR (/ ss origens)
  (princ "\nSelecione as ORIGENS (objetos que descarregam; Enter para terminar): ")
  (setq ss (ssget))
  (if ss
    (progn
      (setq origens (LIG:_Origens ss))
      (if origens
        (LIG:LigarInterativo origens)
        (princ "\nNenhuma origem valida selecionada.")
      )
    )
  )
  (princ)
)

(defun c:DESLIGAR (/ ss origens o n tot)
  (princ "\nSelecione as ORIGENS a desligar (Enter para terminar): ")
  (setq ss (ssget))
  (if ss
    (progn
      (setq origens (LIG:_Origens ss))
      (setq tot 0)
      (foreach o origens
        (setq n (LIG:Desconectar o))
        (setq tot (+ tot n))
      )
      (princ (strcat "\n" (itoa tot) " ligacao(oes) removida(s)."))
    )
  )
  (princ)
)

;;; ------------------------------------------------------------
;;; CALCULAOBJETO (generico)
;;; ------------------------------------------------------------
(defun LIG:_EscolheMetodo (/ lista itens ult i pos m idx)
  (setq lista (HYDRO:RegList "metodo-chuva-vazao"))
  (setq ult (HYDRO:Get "HYDRO.BACIA.METODO" nil))
  (cond
    ((null lista) nil)
    ;; modo automatico: o ultimo metodo usado, sem perguntar
    ((and (HYDRO:CalcAuto) ult (HYDRO:RegGet "metodo-chuva-vazao" ult)) ult)
    (T
      (setq i 0 pos 0)
      (foreach m lista
        (if (equal (car m) ult) (setq pos i))
        (setq i (1+ i))
      )
      (setq itens
        (mapcar (function (lambda (x) (cdr (assoc "NOME" (cdr x))))) lista))
      (setq idx
        (HYDRO:Escolher "Metodo usado no calculo das bacias a montante:" itens pos))
      (HYDRO:Set "HYDRO.BACIA.METODO" (car (nth idx lista)))
      (car (nth idx lista))
    )
  )
)

;; linhas padrao de um resultado (quando o tipo nao define FORMATA)
(defun LIG:_FormataPadrao (res / out p)
  (foreach p res
    (if (and (cdr p) (not (listp (cdr p))))
      (setq out
        (append out
          (list (strcat (car p) ": " (OBJ:_FmtVal (cdr p))))))
    )
  )
  out
)

;; Parametros do calculo da ULTIMA vez para METODO e TR (HIDRAULICA, "PARAMS");
;; se nunca foi calculado, os padroes (projeto > ultimo usado > padrao do tipo)
(defun LIG:_ParamsAnteriores (en id metodo tr / out r)
  (foreach r (OBJ:GrupoDe en "HIDRAULICA")
    (if (and (equal (OBJ:_Val "METODO" r) metodo)
             (equal (OBJ:_Val "TR" r) tr 1e-9))
      (setq out (OBJ:_Val "PARAMS" r))
    )
  )
  (if out
    out
    (HYDRO:ParamsPadrao (OBJ:Cap id "PARAMS-CALCULO") (strcat "HYDRO.OBJ." id ".calc.") nil)
  )
)

;; Calculo SEM perguntas de um objeto que recebe (sarjeta, trecho, estrutura...):
;; le a ENTRADA dos montantes, aplica o CALCULA do tipo (se tiver), define a SAIDA
;; (tempo e vazao com a flag de preservacao) e grava ENTRADA, VAZAO e HIDRAULICA.
;;   params : parametros do calculo do tipo, ou nil para os anteriores/padroes
;; Retorna (("OK" . T) ("ENTRADA" ..) ("RES" ..) ("COMP" ..) ("PR" ..) ("QS" . q)
;;          ("TCS" . min) ("PARAMS" ..)) ou (("ERRO" . msg)).
;; Os montantes precisam estar calculados (LIG:RecalcularMontantes faz isso).
(defun LIG:CalcularCore (en metodo tr params /
                         id tipo ent fn res tp tcs comp pr qs)
  (setq id (OBJ:TipoDe en))
  (setq tipo (if id (OBJ:TipoDados id) nil))
  (setq ent (if id (LIG:Entrada en metodo tr) nil))
  (cond
    ((not id)
      (list (cons "ERRO" "Esta entidade nao e um objeto hidraulico. Use OBJETO.")))
    ((not (cdr (assoc "RECEBE" tipo)))
      (list (cons "ERRO" (strcat "O tipo '" (OBJ:_NomeTipo id)
                                 "' nao recebe montantes. Bacias: use BACIA."))))
    ((not (LIG:ListaMontante en))
      (list (cons "ERRO" "Este objeto nao tem montante. Ligue bacias ou outros objetos a ele (LIGAR).")))
    ((cdr (assoc "FALTAM" ent))
      (list (cons "ERRO" (strcat "Montantes sem calculo para este metodo e TR: "
                                 (HYDRO:Join (cdr (assoc "FALTAM" ent)) ", ")
                                 ". Calcule antes, de montante para jusante."))))
    ((not (cdr (assoc "QP" ent)))
      (list (cons "ERRO" "Nenhum montante valido: as entidades ligadas nao existem mais (rode HYDROAUDIT).")))
    (T
      (if (not params) (setq params (LIG:_ParamsAnteriores en id metodo tr)))
      ;; calculo proprio do tipo (usa a ENTRADA); sem ele o objeto so repassa
      (setq fn (OBJ:Cap id "CALCULA"))
      (setq res
        (if fn
          (apply fn
            (list en
                  (list (cons "TR" tr) (cons "METODO" metodo) (cons "VAZAO" ent))
                  params))
          nil))
      (if (assoc "ERRO" res)
        res
        (progn
          ;; SAIDA: tempo = regra do modo; vazao = precipitacao no maior tempo
          (setq tp (cdr (assoc "PERCURSO" res)))
          (if (not tp) (setq tp 0.0))
          (setq tcs (LIG:_TcPuro (LIG:_Modo en) tp (cdr (assoc "CHEGADAS" ent))))
          (setq comp (LIG:VazaoMontante en metodo tr tcs))
          (setq pr
            (LIG:Preserva (cdr (assoc "QP" ent))
                          (cdr (assoc "QP" comp))
                          (LIG:PreservaAtiva)))
          (setq qs (car pr))
          (OBJ:GravarResultado en "ENTRADA"
            (OBJ:_Limpa
              (list (cons "METODO" metodo)
                    (cons "TR" tr)
                    (cons "QP" (cdr (assoc "QP" ent)))
                    (cons "TC" (cdr (assoc "TC" ent)))
                    (cons "AREA" (cdr (assoc "AREA" ent))))))
          (OBJ:GravarResultado en "VAZAO"
            (OBJ:_Limpa
              (list (cons "METODO" metodo)
                    (cons "TR" tr)
                    (cons "QP" qs)
                    (cons "TC" tcs)
                    (cons "QP-CALC" (cdr (assoc "QP" comp)))
                    (cons "PRESERVADA" (cadr pr))
                    (cons "VOLUME" (cdr (assoc "VOLUME" comp))))))
          (if res
            (OBJ:GravarResultado en "HIDRAULICA"
              (OBJ:_Limpa
                (append
                  (list (cons "METODO" metodo)
                        (cons "TR" tr)
                        (cons "PARAMS" params))
                  (vl-remove-if
                    (function
                      (lambda (x) (member (car x) '("METODO" "TR" "PARAMS"))))
                    res))))
          )
          (HYDRO:Emit "objeto.calculado"
            (list (cons "OBJETO" en) (cons "TIPO" id)
                  (cons "METODO" metodo) (cons "TR" tr) (cons "RES" res)))
          (list (cons "OK" T) (cons "ENTRADA" ent) (cons "RES" res)
                (cons "COMP" comp) (cons "PR" pr) (cons "QS" qs)
                (cons "TCS" tcs) (cons "PARAMS" params))
        )
      )
    )
  )
)

;; Objetos a montante (transitivos) em ORDEM DE CALCULO: o mais a montante primeiro,
;; cada um depois dos seus montantes, sem repetir e sem entrar em ciclo.
;;   acc, stack : chame com nil nil
(defun LIG:_Ordem (en acc stack / m e)
  (foreach m (LIG:ListaMontante en)
    (setq e (LIG:_Existe (car m)))
    (if (and e (not (member e acc)) (not (member e stack)))
      (setq acc (append (LIG:_Ordem e acc (cons en stack)) (list e)))
    )
  )
  acc
)

;; Recalcula UM objeto sem perguntas. Retorna nil se deu certo, ou o texto do erro.
;; Usa a capacidade "RECALCULA" do tipo; sem ela, o calculo generico (LIG:CalcularCore)
;; com os parametros da ultima vez.
(defun LIG:Recalcular (en metodo tr / id fn r)
  (setq id (OBJ:TipoDe en))
  (setq fn (if id (OBJ:Cap id "RECALCULA") nil))
  (cond
    (fn (apply fn (list en metodo tr)))
    ((and id (cdr (assoc "RECEBE" (OBJ:TipoDados id))))
      (setq r (LIG:CalcularCore en metodo tr nil))
      (if (assoc "ERRO" r) (cdr (assoc "ERRO" r)) nil)
    )
    (T "tipo sem calculo")
  )
)

;; Recalcula TODOS os montantes de `en` (do mais a montante para jusante) com o
;; METODO e TR dados. Para no primeiro erro. Retorna nil (ok) ou o texto do erro.
(defun LIG:RecalcularMontantes (en metodo tr / e erro)
  (foreach e (LIG:_Ordem en nil nil)
    (if (not erro)
      (progn
        (princ (strcat "\nRecalculando montante: " (OBJ:Nome e) " ..."))
        (setq erro (LIG:Recalcular e metodo tr))
        (if erro (setq erro (strcat (OBJ:Nome e) ": " erro)))
      )
    )
  )
  erro
)

;; Linhas de texto do resultado de LIG:CalcularCore
(defun LIG:_LinhasCalculo (en id metodo tr r / ent comp pr res fn)
  (setq ent (cdr (assoc "ENTRADA" r)))
  (setq comp (cdr (assoc "COMP" r)))
  (setq pr (cdr (assoc "PR" r)))
  (setq res (cdr (assoc "RES" r)))
  (setq fn (OBJ:Cap id "FORMATA"))
  (append
    (list (strcat "OBJETO " (OBJ:Nome en) "  (" (OBJ:_NomeTipo id) ")")
          (strcat "TR " (HYDRO:FmtReal tr) " anos  |  "
                  (cdr (assoc "NOME" (HYDRO:RegGet "metodo-chuva-vazao" metodo))))
          (strcat "ENTRADA: Q = " (rtos (cdr (assoc "QP" ent)) 2 3)
                  " m3/s   tc = " (rtos (cdr (assoc "TC" ent)) 2 1) " min   ("
                  (itoa (length (cdr (assoc "ORIGENS" ent)))) " montante(s), "
                  (rtos (/ (cdr (assoc "AREA" ent)) 10000.0) 2 3) " ha)")
          (strcat "SAIDA:   Q = " (rtos (cdr (assoc "QS" r)) 2 3) " m3/s   tc = "
                  (rtos (cdr (assoc "TCS" r)) 2 1) " min"
                  (if (cadr pr)
                    (strcat "   (preservada a vazao de entrada; calculada no tc maximo: "
                            (rtos (cdr (assoc "QP" comp)) 2 3) ")")
                    "")))
    (OBJ:LinhasAtrib en)
    (OBJ:LinhaParams "Parametros do calculo" (cdr (assoc "PARAMS" r)))
    (if (cdr (assoc "FALTAM" comp))
      (list (strcat "ATENCAO: sem calculo para este metodo/TR: "
                    (HYDRO:Join (cdr (assoc "FALTAM" comp)) ", ")))
    )
    (if res
      (if fn (apply fn (list res)) (LIG:_FormataPadrao res))
      (list "(tipo sem calculo hidraulico: so repassa a vazao)"))
  )
)

;; CALCULAOBJETO. Recalcula antes os montantes, pergunta TR, metodo e parametros
;; (nao pergunta nada no modo automatico, CALCAUTO) e mostra entrada e saida.
(defun LIG:CalcularInterativo (en / id tipo tr metodo erro params r auto
                                    linhas op pt)
  (if en
    (progn
      (setq id (OBJ:TipoDe en))
      (setq tipo (if id (OBJ:TipoDados id) nil))
      (setq auto (HYDRO:CalcAuto))
      (cond
        ((not id)
          (alert "Esta entidade nao e um objeto hidraulico. Use OBJETO."))
        ((not (cdr (assoc "RECEBE" tipo)))
          (alert (strcat "O tipo '" (OBJ:_NomeTipo id) "' nao recebe montantes. Bacias: use BACIA.")))
        (T
          (setq tr
            (if (and auto (HYDRO:Get "HYDRO.TR" nil))
              (HYDRO:Get "HYDRO.TR" nil)
              (HYDRO:AskReal "Tempo de retorno (anos)" (HYDRO:Get "HYDRO.TR" nil))))
          (setq metodo (LIG:_EscolheMetodo))
          (cond
            ((or (not tr) (<= tr 0.0)) (alert "Tempo de retorno nao informado."))
            ((not metodo) (alert "Nenhum metodo chuva-vazao cadastrado."))
            (T
              (HYDRO:Set "HYDRO.TR" tr)
              ;; todos os montantes sao recalculados antes, em ordem
              (setq erro (LIG:RecalcularMontantes en metodo tr))
              (if erro
                (alert (strcat "Nao foi possivel recalcular os montantes:\n" erro))
                (progn
                  (setq params
                    (if auto
                      (LIG:_ParamsAnteriores en id metodo tr)
                      (HYDRO:AskParams
                        (OBJ:Cap id "PARAMS-CALCULO")
                        (strcat "HYDRO.OBJ." id ".calc.")
                        (LIG:_ParamsAnteriores en id metodo tr))))
                  (setq r (LIG:CalcularCore en metodo tr params))
                  (if (assoc "ERRO" r)
                    (alert (strcat "Erro: " (cdr (assoc "ERRO" r))))
                    (progn
                      (setq linhas (LIG:_LinhasCalculo en id metodo tr r))
                      (if auto
                        (foreach op linhas (princ (strcat "\n" op)))
                        (progn
                          (alert (HYDRO:Join linhas "\n"))
                          (initget "Sim Nao")
                          (setq op
                            (getkword "\nInserir o resultado como texto no desenho? [Sim/Nao] <Nao>: "))
                          (if (equal op "Sim")
                            (progn
                              (setq pt (getpoint "\nSelecione o local de insercao do texto: "))
                              (if pt
                                (HYDRO:Mtext pt (HYDRO:Join linhas "\\P")
                                  (HYDRO:Get "HYDRO.TEXT.HEIGHT" 1.8)
                                  (HYDRO:Get "HYDRO.TEXT.ROTATION" 0.0)))
                            )
                          )
                        )
                      )
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  )
  (princ)
)

;; Oferece LIGAR um objeto recem criado antes de seguir. Nao pergunta se ele ja
;; tem montante ou destino. Montante: objetos que descarregam NELE; Destino: onde
;; ELE descarrega.
(defun LIG:OferecerLigacao (en / id dados recebe emite ops op ss origens comp n r o)
  (setq id (OBJ:TipoDe en))
  (if (and id (null (LIG:ListaMontante en)) (null (LIG:Destinos en)))
    (progn
      (setq dados (OBJ:TipoDados id))
      (setq recebe (cdr (assoc "RECEBE" dados)))
      (setq emite (cdr (assoc "EMITE" dados)))
      (setq ops
        (append (if recebe (list "Montante") nil)
                (if emite (list "Destino") nil)
                (list "Nao")))
      (if (> (length ops) 1)
        (progn
          (initget (HYDRO:Join ops " "))
          (setq op
            (getkword
              (strcat "\nLigar " (OBJ:Nome en) " a outro objeto agora? ["
                      (HYDRO:Join ops "/") "] <Nao>: ")))
          (cond
            ((equal op "Montante")
              (princ "\nSelecione os objetos de MONTANTE (os que descarregam neste; Enter para terminar): ")
              (setq ss (ssget))
              (if ss
                (progn
                  (setq origens (vl-remove en (LIG:_Origens ss)))
                  (if origens
                    (progn
                      (setq comp (LIG:_PedeCompartilha en))
                      (setq n 0)
                      (foreach o origens
                        (setq r (LIG:Conectar o en comp))
                        (if (assoc "ERRO" r)
                          (princ (strcat "\n" (OBJ:Nome o) ": " (cdr (assoc "ERRO" r))))
                          (setq n (1+ n))
                        )
                      )
                      (princ (strcat "\n" (itoa n) " montante(s) ligado(s)."))
                    )
                  )
                )
              )
            )
            ((equal op "Destino")
              (LIG:LigarInterativo (list en))
            )
          )
        )
      )
    )
  )
  (princ)
)

;; Flag do modo automatico dos calculos
(defun c:CALCAUTO (/ op ativo)
  (setq ativo (HYDRO:CalcAuto))
  (princ
    (strcat "\nModo automatico dos calculos: " (if ativo "LIGADO" "DESLIGADO")
            "\n(Ligado: BACIA e CALCULAOBJETO usam o ultimo TR, metodo e parametros sem perguntar.)"))
  (initget "Sim Nao")
  (setq op
    (getkword (strcat "\nLigar o modo automatico? [Sim/Nao] <" (if ativo "Sim" "Nao") ">: ")))
  (if op
    (HYDRO:Set "HYDRO.CALC.AUTO" (if (equal op "Sim") 1 0))
  )
  (princ)
)

;; Flag geral: preservar a maior vazao entre a de entrada e a de saida
(defun c:PRESERVAVAZAO (/ op ativa)
  (setq ativa (LIG:PreservaAtiva))
  (princ
    (strcat "\nPreservar a maior vazao entre entrada e saida: "
            (if ativa "SIM" "NAO")
            "\n(O tempo maior da saida pode reduzir a vazao calculada; com SIM a de entrada e mantida.)"))
  (initget "Sim Nao")
  (setq op
    (getkword (strcat "\nPreservar a maior vazao? [Sim/Nao] <" (if ativa "Sim" "Nao") ">: ")))
  (if op
    (HYDRO:Set "HYDRO.VAZAO.PRESERVA" (if (equal op "Sim") 1 0))
  )
  (princ)
)

(defun c:CALCULAOBJETO (/ sel)
  (setq sel (entsel "\nSelecione o objeto a calcular: "))
  (if sel (LIG:CalcularInterativo (car sel)))
  (princ)
)

;;; ------------------------------------------------------------
;;; INTEGRACAO
;;; ------------------------------------------------------------
(HYDRO:On "objeto.removido" "ligacao" 'LIG:_OnObjetoRemovido)

(HYDRO:SetLabel "HYDRO.CALC.AUTO" "Modo automatico dos calculos, sem perguntas (1 = sim)" "")
(HYDRO:SetLabel "HYDRO.VAZAO.PRESERVA" "Preservar a maior vazao entre entrada e saida (1 = sim)" "")

(HYDRO:Provide "ligacao" "3.0")
(princ)
