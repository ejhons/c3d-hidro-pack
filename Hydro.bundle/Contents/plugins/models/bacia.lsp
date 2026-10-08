;;; ============================================================
;;; models/bacia.lsp - MODELO BACIA (BAC:)
;;;
;;; Representa a bacia hidrografica no sistema: uma polilinha de CONTORNO
;;; (fechada) + uma polilinha de TALVEGUE. So a funcionalidade do OBJETO:
;;; registro, caracterizacao, tempo de concentracao, calculo de vazao e a
;;; declaracao do tipo "bacia" no catalogo de objetos. Tambem traz os COMANDOS de
;;; linha de comando (BACIACAD, BACIA, BACIAS, BACIAINFO) e as perguntas deles,
;;; para o objeto funcionar com um unico .lsp. Texto inserido no desenho fica em
;;; views/bacia_view.lsp; o dialogo em views/bacia_tabela.lsp.
;;;
;;; ESTRUTURA DO ARQUIVO (padrao dos models; ver .claude/skills/hydro-model)
;;;   1. UTILITARIOS                    funcoes pequenas, sem regra de negocio
;;;   2. GEOMETRIA (CARACTERIZACAO)     o que se le do desenho -> CARACT
;;;   3. LER, GRAVAR, EDITAR, REMOVER   porta de armazenamento do tipo
;;;   4. CAMPOS (CARACT, PARAMS, ATRIB) acessos aos campos do registro
;;;   5. RESULTADOS (RESULT)            acessos e gravacao dos grupos calculados
;;;   6. CALCULOS                       funcoes que PRODUZEM os campos de RESULT
;;;   7. RESUMO E FORMATACAO            linhas de texto e toString (sem desenhar)
;;;   8. TIPO NO CATALOGO               rotulos, eventos e OBJ:RegistrarTipo
;;;   9. COMANDOS E INTERACAO           comandos c: e perguntas da linha de comando
;;;   toString: BAC:ToString (secao 7), tambem a capacidade "TOSTRING" do tipo
;;;
;;; ONDE FICAM OS DADOS
;;;   Dicionario de extensao da polilinha do contorno, chave "HYDRO-OBJ", no
;;;   REGISTRO PADRAO dos objetos (docs/arquitetura.md secao 18). O plugin
;;;   trabalha diretamente com ele ("dados" nas funcoes abaixo):
;;;     (("VERSAO" . 2) ("TIPO" . "bacia") ("NOME" . n) ("DESCRICAO" . txt)
;;;      ("PARAMS" . (("TALVEGUE" . "handle")            ; componente da bacia
;;;                   ("MONTANTE" . (("h1" . T) ("h2")))))  ; opcional; ver ligacao.lsp
;;;      ("ATRIB"  . (("C" . 0.6) ("CN" . 80.0)))       ; definidos pelo usuario
;;;      ("CARACT" . (("AREA" . m2) ("COMP" . m) ("DESNIVEL" . m) ("DECL" . m/m)))
;;;      ("RESULT" . (("TC"          . (("MIN" . min) ("ORIGEM" . id | "usuario")
;;;                                     ("PARAMS" . alist)))
;;;                   ("VAZAO"       . (vazao ...))
;;;                   ("HIDROGRAMAS" . (...)))))         ; plugin hidrograma
;;;     vazao = (("METODO" . id) ("TR" . anos) ("DUR" . min) ("TC" . min)
;;;              ("PARAMS" . alist)
;;;              ("I" . mm/h) ("P" . mm) ("PE" . mm) ("QP" . m3/s) ("VOLUME" . m3))
;;;   RESULT guarda GRUPOS com nome (TC, VAZAO, HIDROGRAMAS), e os campos
;;;   calculados ficam direto na entrada do grupo, sem sub-lista "RES".
;;;   Uma vazao com o mesmo METODO e TR substitui a anterior.
;;;   Acompanha a entidade ao copiar, colar e salvar o desenho.
;;;   BAC:Ler / BAC:Gravar sao a porta de armazenamento do tipo "bacia".
;;;   Valores nil nao sao gravados.
;;;
;;; TEMPO DE CONCENTRACAO
;;;   Metodos no catalogo "metodo-tc" (registry/tempo_conc). Sem ele, so Kirpich.
;;;   O tc fica gravado no cadastro (com o metodo usado) e e reutilizado.
;;;
;;; BACIAS A MONTANTE (PARAMS "MONTANTE", plugin ligacao)
;;;   TALVEGUE e componente da bacia e continua em campo proprio; MONTANTE lista
;;;   os objetos que descarregam nela, com o flag "contribui diretamente ao talvegue".
;;;   A bacia e um mecanismo ENTRADA -> SAIDA (ligacao.lsp). Sem montante so tem SAIDA
;;;   (a propria). Com montantes (BAC:_CalcularEGravar):
;;;     ENTRADA  Q = soma das saidas dos montantes, tc = maior tempo de saida (grupo
;;;              "ENTRADA", gravado)
;;;     tempo de SAIDA = LIG:_TcPuro "concentracao" (paralelo se nao contribui ao
;;;              talvegue, serie se contribui); a chuva usa SEMPRE esse maior tempo
;;;     Q_calc   = bacia propria + montantes reavaliados nesse tempo (racional composto)
;;;     Q SAIDA  = max(Q entrada, Q_calc) com a flag geral HYDRO.VAZAO.PRESERVA
;;;   A entrada do grupo "VAZAO" e a SAIDA: QP/VOLUME totais, TC de saida, e acrescenta
;;;   QP-PROPRIO, AREA-TOTAL, TC-PROPRIO, QP-CALC e PRESERVADA (quando preservou).
;;;   Os montantes devem ser calculados antes, com o mesmo METODO e TR.
;;;
;;; EVENTOS EMITIDOS
;;;   "bacia.cadastrada" "BACIA" "TALVEGUE" (enames) "NOME" + caracteristicas
;;;   "bacia.calculada"  "BACIA" "TALVEGUE" "NOME" "AREA" "COMP" "DECL" "TC"
;;;                      "METODO" "TR" "DUR" "QP" "PE" "VOLUME"
;;;   "bacia.removida"   "BACIA" (emitido antes de apagar o cadastro)
;;;
;;; TIPO DE OBJETO
;;;   Ao fim deste arquivo a bacia se declara no catalogo "objeto-hidraulico"
;;;   (se o plugin objetos estiver carregado), com o armazenamento proprio
;;;   (indice HYDRO.BACIAS) e as capacidades de vazao, area e destino padrao.
;;; ============================================================
(vl-load-com)


;;; ------------------------------------------------------------
;;; 1. UTILITARIOS
;;; ------------------------------------------------------------
(defun BAC:_Try (fn / r)
  (setq r (vl-catch-all-apply fn nil))
  (if (vl-catch-all-error-p r) nil r)
)

(defun BAC:_Erro (msg)
  (list (cons "ERRO" msg))
)

;; remove pares sem valor (nil nao e gravado no cadastro)
(defun BAC:_Limpa (pares)
  (vl-remove-if (function (lambda (x) (null (cdr x)))) pares)
)

(defun BAC:_Val (chave dados)
  (cdr (assoc chave dados))
)

;; alist sem as chaves da lista
(defun BAC:_SemChaves (pares chaves)
  (vl-remove-if (function (lambda (x) (member (car x) chaves))) pares)
)

;; x e y iguais a menos de 1e-6 (relativo)?
(defun BAC:_Prox (x y)
  (if (and x y (equal x y (* 1e-6 (max 1.0 (abs x)))))
    T
    nil
  )
)

;; Usado para ordenar as bacias pelo handle
(defun BAC:_HandleLt (h1 h2)
  (if (= (strlen h1) (strlen h2))
    (< h1 h2)
    (< (strlen h1) (strlen h2))
  )
)

;; Troca (ou acrescenta) um item de nivel superior; valor nil remove o item
(defun BAC:_SetChave (dados chave valor)
  (if valor
    (append (vl-remove (assoc chave dados) dados) (list (cons chave valor)))
    (vl-remove (assoc chave dados) dados)
  )
)

;; Nome para exibir: o cadastrado ou "B-<handle>"
(defun BAC:_NomeExib (dados h)
  (if (BAC:Nome dados) (BAC:Nome dados) (strcat "B-" h))
)

;; Nome do método de cálculo chuva-vazão salvo como default
(defun BAC:_NomeMetodo (id / m)
  (setq m (HYDRO:RegGet "metodo-chuva-vazao" id))
  (if m (cdr (assoc "NOME" m)) id)
)

;; Nome do método default de cálculo do tempo de concentração
(defun BAC:_NomeTc (id / m)
  (cond
    ((not id) "-")
    ((equal id "usuario") "informado")
    (T
      (setq m (HYDRO:RegGet "metodo-tc" id))
      (if m (cdr (assoc "NOME" m)) id)
    )
  )
)


;;; ------------------------------------------------------------
;;; 2. GEOMETRIA (CARACTERIZACAO)
;;; ------------------------------------------------------------
;; Área da polilinha de contorno da bacia
(defun BAC:_Area (en)
  (BAC:_Try
    (function (lambda () (vla-get-area (vlax-ename->vla-object en))))
  )
)

;; Comprimento da polilinha usada como talvegue
(defun BAC:_Comprimento (en)
  (BAC:_Try
    (function
      (lambda () (vlax-curve-getDistAtParam en (vlax-curve-getEndParam en)))
    )
  )
)

;; Testa se polilinha do contorno está fechada
(defun BAC:_Fechada (en)
  (BAC:_Try (function (lambda () (vlax-curve-isClosed en))))
)

;; Superficie TIN escolhida com ATUALIZASUPERFICIE (chave compartilhada)
(defun BAC:Superficie (/ h)
  (setq h (HYDRO:Get "HYDRO.SURFACE.HANDLE" nil))
  (if h (handent h) nil)
)

;; Coleta a elevacao em uma coordenada na superficie
(defun BAC:_ElevSuperficie (surf pt)
  (BAC:_Try
    (function
      (lambda ()
        (vlax-invoke-method
          (vlax-ename->vla-object surf) 'FindElevationAtXY (car pt) (cadr pt))
      )
    )
  )
)

;; Desnivel entre o inicio e o fim do talvegue (com superficie ou pela cota
;; da propria polilinha, util para polilinhas 3D)
(defun BAC:_Desnivel (en surf / p1 p2 z1 z2)
  (setq p1 (vlax-curve-getStartPoint en))
  (setq p2 (vlax-curve-getEndPoint en))
  (if surf
    (setq z1 (BAC:_ElevSuperficie surf p1)
          z2 (BAC:_ElevSuperficie surf p2))
    (setq z1 (caddr p1)
          z2 (caddr p2))
  )
  (if (and z1 z2) (- z2 z1) nil)
)

;; Caracteriza a bacia (puro).
;; Retorna alist (AREA COMP DESNIVEL DECL) ou (("ERRO" . msg))
(defun BAC:Caracterizar (contorno talvegue / surf area comp desn decl)
  (setq surf (BAC:Superficie))
  (setq area (BAC:_Area contorno))
  (setq comp (BAC:_Comprimento talvegue))
  (setq desn (if comp (BAC:_Desnivel talvegue surf) nil))
  (if (and comp desn (> comp 0.0))
    (setq decl (/ (abs desn) comp))
  )
  (cond
    ((not area)
      (BAC:_Erro "Nao foi possivel obter a area do contorno.")
    )
    ((or (not comp) (<= comp 0.0))
      (BAC:_Erro "Nao foi possivel obter o comprimento do talvegue.")
    )
    ((not desn)
      (BAC:_Erro "Nao foi possivel obter o desnivel (ponto fora da superficie?).")
    )
    ((not (and decl (> decl 0.0)))
      (BAC:_Erro
        "Declividade nula. Defina a superficie (ATUALIZASUPERFICIE) ou use polilinha 3D.")
    )
    (T
      (list
        (cons "AREA" area)
        (cons "COMP" comp)
        (cons "DESNIVEL" (abs desn))
        (cons "DECL" decl)
      )
    )
  )
)

;; a geometria caracterizada mudou em relacao a gravada?
(defun BAC:_GeomIgual (a b)
  (if (and (BAC:_Prox (BAC:_Val "AREA" a) (BAC:_Val "AREA" b))
           (BAC:_Prox (BAC:_Val "COMP" a) (BAC:_Val "COMP" b))
           (BAC:_Prox (BAC:_Val "DESNIVEL" a) (BAC:_Val "DESNIVEL" b)))
    T
    nil
  )
)


;;; ------------------------------------------------------------
;;; 3. LER, GRAVAR, EDITAR, REMOVER
;;; ------------------------------------------------------------
;; Le o cadastro: o registro padrao, se a entidade e uma bacia
(defun BAC:Ler (en / reg)
  (setq reg (HYDRO:DadoLer en "HYDRO-OBJ"))
  (if (and reg (equal (BAC:_Val "TIPO" reg) "bacia"))
    reg
    nil
  )
)

;; Indice das bacias (so handles) para listar sem varrer o desenho
(defun BAC:_Indexar (en / h lista)
  (setq h (HYDRO:Handle en))
  (setq lista (HYDRO:Get "HYDRO.BACIAS" nil))
  (if (not (member h lista))
    (HYDRO:Set "HYDRO.BACIAS" (append lista (list h)))
  )
)

;; Grava o registro e indexa. Retorna dados ou nil
(defun BAC:Gravar (en dados)
  (if (HYDRO:DadoGravar en "HYDRO-OBJ" dados)
    (progn (BAC:_Indexar en) dados)
    nil
  )
)

;; Enames das bacias conhecidas que ainda existem e tem cadastro
(defun BAC:Listar (/ out h en)
  (foreach h (HYDRO:Get "HYDRO.BACIAS" nil)
    (setq en (handent h))
    (if (and en (BAC:Ler en))
      (setq out (append out (list en)))
    )
  )
  out
)

;; Reconstroi o indice varrendo o desenho (use se o indice estiver vazio,
;; por exemplo apos colar bacias de outro desenho). Retorna a quantidade.
(defun BAC:Reindexar (/ ss i en lista)
  (setq ss (ssget "_X" '((0 . "LWPOLYLINE,POLYLINE,SPLINE"))))
  (if ss
    (progn
      (setq i (sslength ss))
      (while (> i 0)
        (setq i (1- i))
        (setq en (ssname ss i))
        (if (BAC:Ler en)
          (setq lista (cons (HYDRO:Handle en) lista))
        )
      )
    )
  )
  (setq lista (vl-sort lista 'BAC:_HandleLt))
  (HYDRO:Set "HYDRO.BACIAS" lista)
  (length lista)
)

;; Grava o cadastro mantendo DESCRICAO e os resultados ja existentes (vazoes,
;; hidrogramas). tc = (("MIN" . min) ("ORIGEM" . id) ("PARAMS" . alist))
(defun BAC:Cadastrar (contorno talvegue nome atrib caract tc / dados novo)
  (setq dados (BAC:Ler contorno))
  (setq novo
    (BAC:_Limpa
      (list
        (cons "VERSAO" 2)
        (cons "TIPO" "bacia")
        (cons "NOME" nome)
        (cons "DESCRICAO" (BAC:Descricao dados))
        ;; preserva os outros vinculos (MONTANTE); so o TALVEGUE e trocado
        (cons "PARAMS" (BAC:_SetChave (BAC:Params dados) "TALVEGUE" (HYDRO:Handle talvegue)))
        (cons "ATRIB" atrib)
        (cons "CARACT" caract)
        (cons "RESULT"
          (BAC:_Limpa
            (list (cons "TC" (BAC:_Limpa tc))
                  (cons "VAZAO" (BAC:Vazao dados))
                  (cons "HIDROGRAMAS" (BAC:Hidrogramas dados)))))
      )
    )
  )
  (BAC:Gravar contorno novo)
  (HYDRO:Emit "bacia.cadastrada"
    (append
      ;entidades
      (list (cons "BACIA" contorno) (cons "TALVEGUE" talvegue))
      ; nome cadastrado
      (BAC:_Limpa (list (cons "NOME" nome)))
      ; caracteríticas da geometria
      caract
      ; Cálculo do tempo de concentração
      (BAC:_Limpa
        (list (cons "TC" (BAC:_Val "MIN" tc))
              (cons "TC-ORIGEM" (BAC:_Val "ORIGEM" tc))))
    )
  )
  novo
)

;; Obtem o cadastro (usado tambem pelo calculo de sarjetas). Se a bacia nao esta
;; cadastrada, cadastra automaticamente (Kirpich, respeitando o tc minimo).
;; Se o contorno/talvegue/superficie mudaram, atualiza mantendo nome,
;; atributos e o metodo de tc. Retorna o contexto (BAC:_Ctx) ou (("ERRO" . msg)).
(defun BAC:Obter (contorno talvegue /
                  dados caract h old id params r tcmin tc)
  (setq dados (BAC:Ler contorno))
  (setq caract (BAC:Caracterizar contorno talvegue))
  (setq h (HYDRO:Handle talvegue))
  (cond
    ; retorna erro caso processo não seja bem sucedido
    ((assoc "ERRO" caract) caract)
    ; retorna o contexto de cálculo como dicionário achatado.
    ((and dados
          (equal (BAC:Talvegue dados) h)
          (BAC:_GeomIgual caract (BAC:Caract dados)))
      (BAC:_Ctx dados)
    )
    (T
      (setq old (BAC:Tc dados))
      (setq tcmin (HYDRO:Get "HYDRO.TC.MINIMO" 10.0))
      (setq id (BAC:_Val "ORIGEM" old))
      (setq id (if (and id (not (equal id "usuario")) (BAC:_MetodoTcOk id)) id "kirpich"))
      ; Define params como o último usado ou default do método calculado
      (setq params
        (if (and (BAC:_Val "PARAMS" old) (equal id (BAC:_Val "ORIGEM" old)))
          (BAC:_Val "PARAMS" old)
          (BAC:_ParamsTc id)
        )
      )

      (setq r (BAC:CalcularTc id caract params))
      (if (assoc "ERRO" r)
        (progn
          (setq id "kirpich")
          (setq params nil)
          (setq r (BAC:CalcularTc id caract nil))
        )
      )
      (if (assoc "ERRO" r)
        r
        (progn
          (setq tc
            (list (cons "MIN" (max (BAC:_Val "TC" r) tcmin))
                  (cons "ORIGEM" id)
                  (cons "PARAMS" params)))
          (BAC:Cadastrar contorno talvegue (BAC:Nome dados) (BAC:Atrib dados) caract tc)
          (princ
            (strcat "\n[BACIA] "
                    (if dados "Cadastro atualizado" "Bacia cadastrada automaticamente")
                    " (handle " (HYDRO:Handle contorno) ")."))
          (BAC:_Ctx (BAC:Ler contorno))
        )
      )
    )
  )
)

;; Remove o cadastro da bacia (e as marcas de XData, se o plugin existir).
;; Emite "bacia.removida" ANTES de apagar, para quem guarda ligacoes.
(defun BAC:Remover (en / dados talv h)
  (HYDRO:Emit "bacia.removida" (list (cons "BACIA" en)))
  (setq dados (BAC:Ler en))
  (setq h (BAC:Talvegue dados))
  (setq talv (if h (handent h) nil))
  (HYDRO:DadoApagar en "HYDRO-OBJ")
  (HYDRO:Set "HYDRO.BACIAS" (vl-remove (HYDRO:Handle en) (HYDRO:Get "HYDRO.BACIAS" nil)))
  (if (HYDRO:Has "xdata")
    (progn
      (vl-catch-all-apply 'XD:RemoveApp (list en "DREN-BACIA"))
      (if talv (vl-catch-all-apply 'XD:RemoveApp (list talv "DREN-BACIA")))
    )
  )
  T
)


;;; ------------------------------------------------------------
;;; 4. CAMPOS (CARACT, PARAMS e ATRIB)
;;; ------------------------------------------------------------
;; Acessos ao registro (secao 18 de docs/arquitetura.md)
(defun BAC:Nome (dados)       (BAC:_Val "NOME" dados))

(defun BAC:Descricao (dados)  (BAC:_Val "DESCRICAO" dados))

(defun BAC:Params (dados)     (BAC:_Val "PARAMS" dados))

(defun BAC:Talvegue (dados)   (BAC:_Val "TALVEGUE" (BAC:Params dados)))

(defun BAC:Atrib (dados)      (BAC:_Val "ATRIB" dados))

(defun BAC:Caract (dados)     (BAC:_Val "CARACT" dados))

;; Atributos da bacia que coincidem com parametros do metodo viram padrao
;; (ex.: atributo CN preenche o parametro CN do SCS)
(defun BAC:_Sobrescritas (atrib defs / out d)
  (foreach d defs
    (if (assoc (car d) atrib)
      (setq out (append out (list (assoc (car d) atrib))))
    )
  )
  out
)

;; Contexto de calculo da bacia (NAO e o que fica gravado): caracteristicas,
;; "TC" e "TC-ORIGEM", "NOME" e os atributos (C, CN...)
(defun BAC:_Ctx (dados / tc)
  (setq tc (BAC:Tc dados))
  (append
    (BAC:Caract dados)
    (BAC:_Limpa
      (list (cons "NOME" (BAC:Nome dados))
            (cons "TC" (BAC:_Val "MIN" tc))
            (cons "TC-ORIGEM" (BAC:_Val "ORIGEM" tc))))
    (BAC:Atrib dados)
  )
)


;;; ------------------------------------------------------------
;;; 5. RESULTADOS (RESULT)
;;; ------------------------------------------------------------
(defun BAC:Result (dados)     (BAC:_Val "RESULT" dados))

;; tc: (("MIN" . min) ("ORIGEM" . id | "usuario") ("PARAMS" . alist))
(defun BAC:Tc (dados)         (BAC:_Val "TC" (BAC:Result dados)))

;; vazoes: lista de (("METODO" ..) ("TR" ..) ("DUR" ..) ("TC" ..) ("PARAMS" ..)
;;                   ("I" ..) ("P" ..) ("PE" ..) ("QP" ..) ("VOLUME" ..))
(defun BAC:Vazao (dados)      (BAC:_Val "VAZAO" (BAC:Result dados)))

(defun BAC:Hidrogramas (dados) (BAC:_Val "HIDROGRAMAS" (BAC:Result dados)))

;; Idem _SetChave, para um grupo dentro de RESULT ("TC", "VAZAO", "HIDROGRAMAS")
(defun BAC:_SetResult (dados chave valor)
  (BAC:_SetChave dados "RESULT" (BAC:_SetChave (BAC:Result dados) chave valor))
)

(defun BAC:_MesmaVazao (a b)
  (if (and (equal (BAC:_Val "METODO" a) (BAC:_Val "METODO" b))
           (equal (BAC:_Val "TR" a) (BAC:_Val "TR" b) 1e-9))
    T
    nil
  )
)

;; Acrescenta uma vazao, substituindo a de mesmo METODO e TR
(defun BAC:_AddVazao (lista vaz)
  (append
    (vl-remove-if
      (function (lambda (x) (BAC:_MesmaVazao x vaz)))
      lista
    )
    (list vaz)
  )
)

;; maior vazao de pico entre as vazoes calculadas (0.0 se nao ha)
(defun BAC:_MaxQp (dados / q c)
  (setq q 0.0)
  (foreach c (BAC:Vazao dados)
    (if (and (BAC:_Val "QP" c) (> (BAC:_Val "QP" c) q))
      (setq q (BAC:_Val "QP" c))
    )
  )
  q
)

;; Contexto de uma vazao para quem for gerar hidrogramas: TR, DUR, METODO e
;; o TC usado no calculo vem PRIMEIRO (assoc acha o primeiro), depois as
;; caracteristicas da bacia e os campos calculados (QP, PE, VOLUME...).
(defun BAC:Contexto (dados vaz)
  (append
    (BAC:_Limpa
      (list (cons "TR" (BAC:_Val "TR" vaz))
            (cons "DUR" (BAC:_Val "DUR" vaz))
            (cons "METODO" (BAC:_Val "METODO" vaz))
            (cons "TC" (BAC:_Val "TC" vaz))))
    (BAC:Caract dados)
    (BAC:_SemChaves vaz '("METODO" "TR" "DUR" "TC" "PARAMS"))
  )
)


;;; ------------------------------------------------------------
;;; 6. CALCULOS
;;; ------------------------------------------------------------
;; Kirpich / California Culverts: tc = 57 * (L^3 / H)^0.385
;; (L em km, H em m, tc em min). comp em m, decl em m/m
;; Usado apenas quando o plugin de metodos nao esta carregado.
(defun BAC:TcKirpich (comp decl)
  (if (and comp decl (> comp 0.0) (> decl 0.0))
    (* 57.0
       (expt (/ (expt (/ comp 1000.0) 3.0) (* decl comp)) 0.385))
    nil
  )
)

;; tc por um metodo do catalogo "metodo-tc". Sem o plugin tempo_conc, so
;; "kirpich". Retorna (("TC" . min)) ou (("ERRO" . msg)).
(defun BAC:CalcularTc (id caract params / r)
  (cond
    ((HYDRO:Has "tempo-conc")
      (TCM:Calcular id caract params)
    )
    ((equal id "kirpich")
      (setq r (BAC:TcKirpich (BAC:_Val "COMP" caract) (BAC:_Val "DECL" caract)))
      (if r (list (cons "TC" r)) (BAC:_Erro "Declividade nula."))
    )
    (T
      (BAC:_Erro "Plugin tempo_conc nao carregado: so o metodo kirpich esta disponivel.")
    )
  )
)

(defun BAC:_ListaTc ()
  (HYDRO:RegList "metodo-tc")
)

;; Verifica se método está cadastrado ou é default (kirpich)
(defun BAC:_MetodoTcOk (id)
  (if (or (HYDRO:RegGet "metodo-tc" id) (equal id "kirpich")) T nil)
)

;; ultimos parametros usados (ou padroes) de um metodo de tc
(defun BAC:_ParamsTc (id / m out d v)
  (setq m (HYDRO:RegGet "metodo-tc" id))
  (foreach d (cdr (assoc "PARAMS" m))
    (setq v (HYDRO:Get (strcat "HYDRO.TC." id "." (car d)) nil))
    (setq out (append out (list (cons (car d) (if v v (nth 2 d))))))
  )
  out
)

;; Executa um metodo do catalogo (puro). Retorna o resultado do metodo ou
;; (("ERRO" . msg)).
(defun BAC:ExecutarMetodo (id ctx params / m falta r)
  (setq m (HYDRO:RegGet "metodo-chuva-vazao" id))
  (cond
    ((not m)
      (BAC:_Erro (strcat "Metodo nao cadastrado: " id))
    )
    (T
      (foreach r (cdr (assoc "REQUER" m))
        (if (and (not falta) (not (HYDRO:Has r)))
          (setq falta r)
        )
      )
      (if falta
        (BAC:_Erro (strcat "Plugin requerido nao carregado: " falta))
        (apply (cdr (assoc "FN" m)) (list ctx params))
      )
    )
  )
)

;; Executa, grava a vazao na bacia (RESULT -> "VAZAO") e emite o evento.
;; Retorna a vazao gravada (campos calculados planos) ou (("ERRO" . msg)).
(defun BAC:_CalcularEGravar (contorno talv cad perg /
                             ctx res vaz dados id tr dur ent m tcprop tcout comp pr)
  (setq id  (BAC:_Val "ID" perg))
  (setq tr  (BAC:_Val "TR" perg))
  (setq dur (BAC:_Val "DUR" perg))
  (setq ent (BAC:_Entrada contorno id tr))
  (cond
    ;; ha montantes mas falta o calculo de algum deles
    ((and ent (or (BAC:_Val "FALTAM" ent) (null (BAC:_Val "QP" ent))))
      (BAC:_Erro
        (strcat "Montantes sem calculo para este metodo e TR: "
                (HYDRO:Join (BAC:_Val "FALTAM" ent) ", ")
                ". Calcule-os antes, de montante para jusante."))
    )
    (T
      ;; tempo de saida: com montantes, o maior (paralelo ou serie, ver ligacao.lsp)
      (setq tcprop (BAC:_Val "TC" cad))
      (if ent
        (progn
          (setq tcout (LIG:_TcPuro "concentracao" tcprop (BAC:_Val "CHEGADAS" ent)))
          (setq m (HYDRO:RegGet "metodo-chuva-vazao" id))
          (setq cad (cons (cons "TC" tcout) cad))
          (if (not (and m (cdr (assoc "USA-DUR" m))))
            (setq dur tcout)
          )
        )
      )
      (setq ctx (append (list (cons "TR" tr) (cons "DUR" dur)) cad))
      (setq res (BAC:ExecutarMetodo id ctx (BAC:_Val "PARAMS" perg)))
      (cond
        ((assoc "ERRO" res) res)
        (T
          (if ent
            (progn
              ;; montantes reavaliados no mesmo tempo maximo; soma com a propria
              (setq comp (LIG:VazaoMontante contorno id tr tcout))
              (setq res (BAC:_Compoe res comp (BAC:_Val "AREA" cad) tcprop))
              ;; flag geral: nao deixar o tempo maior reduzir abaixo da entrada
              (setq pr
                (LIG:Preserva (BAC:_Val "QP" ent) (BAC:_Val "QP" res) (LIG:PreservaAtiva)))
              (if (cadr pr)
                (setq res
                  (BAC:_SetChave
                    (BAC:_SetChave
                      (BAC:_SetChave res "QP-CALC" (BAC:_Val "QP" res))
                      "QP" (car pr))
                    "PRESERVADA" T))
              )
            )
          )
          (setq vaz
            (BAC:_Limpa
              (append
                (list
                  (cons "METODO" id)
                  (cons "TR" tr)
                  (cons "DUR" (if (BAC:_Val "DUR" res) (BAC:_Val "DUR" res) dur))
                  (cons "TC" (BAC:_Val "TC" cad))
                  (cons "PARAMS" (BAC:_Val "PARAMS" perg))
                )
                (BAC:_SemChaves res '("METODO" "TR" "DUR" "TC" "PARAMS"))
              )
            )
          )
          (setq dados (BAC:Ler contorno))
          (BAC:Gravar contorno
            (BAC:_SetResult dados "VAZAO" (BAC:_AddVazao (BAC:Vazao dados) vaz)))
          ;; ENTRADA (o que veio dos montantes), no registro padrao
          (if (and ent (HYDRO:Has "objetos"))
            (OBJ:GravarResultado contorno "ENTRADA"
              (BAC:_Limpa
                (list (cons "METODO" id)
                      (cons "TR" tr)
                      (cons "QP" (BAC:_Val "QP" ent))
                      (cons "TC" (BAC:_Val "TC" ent))
                      (cons "AREA" (BAC:_Val "AREA" ent)))))
          )
          (HYDRO:Emit "bacia.calculada"
            (BAC:_Limpa
              (list
                (cons "BACIA" contorno)
                (cons "TALVEGUE" talv)
                (cons "NOME" (BAC:_Val "NOME" cad))
                (cons "AREA" (BAC:_Val "AREA" cad))
                (cons "COMP" (BAC:_Val "COMP" cad))
                (cons "DECL" (BAC:_Val "DECL" cad))
                (cons "TC" (BAC:_Val "TC" cad))
                (cons "METODO" id)
                (cons "TR" tr)
                (cons "DUR" (BAC:_Val "DUR" vaz))
                (cons "QP" (BAC:_Val "QP" res))
                (cons "PE" (BAC:_Val "PE" res))
                (cons "VOLUME" (BAC:_Val "VOLUME" res))
              )
            )
          )
          vaz
        )
      )
    )
  )
)

;; ENTRADA da bacia (LIG:Entrada) se ela tem montante e o plugin ligacao esta carregado
(defun BAC:_Entrada (contorno id tr)
  (if (and (HYDRO:Has "ligacao") (LIG:Afluentes contorno))
    (LIG:Entrada contorno id tr)
    nil
  )
)

;; Montantes da bacia compostos para METODO e TR (LIG:VazaoMontante), ou nil
;; se a bacia nao tem montante ou o plugin ligacao nao esta carregado
;; Soma o que vem dos montantes ao resultado proprio do metodo (puro).
;;   res = resultado do metodo da propria bacia (ja no tc acumulado)
;;   mont = LIG:VazaoMontante (QP, VOLUME, opcional AREA)   area = area propria (m2)
;;   tcprop = tc proprio (min)
;; QP e VOLUME passam a ser os TOTAIS no exutorio; o proprio fica em QP-PROPRIO.
;; Sem VOLUME nos dois lados o volume e descartado (nao seria o total).
(defun BAC:_Compoe (res mont area tcprop / r qm)
  (setq qm (if (BAC:_Val "QP" mont) (BAC:_Val "QP" mont) 0.0))
  (setq r (BAC:_SetChave res "QP-PROPRIO" (BAC:_Val "QP" res)))
  (setq r (BAC:_SetChave r "QP" (+ (BAC:_Val "QP" res) qm)))
  (setq r
    (BAC:_SetChave r "VOLUME"
      (if (and (BAC:_Val "VOLUME" res) (BAC:_Val "VOLUME" mont))
        (+ (BAC:_Val "VOLUME" res) (BAC:_Val "VOLUME" mont))
        nil)))
  (setq r
    (BAC:_SetChave r "AREA-TOTAL"
      (+ (if area area 0.0) (if (BAC:_Val "AREA" mont) (BAC:_Val "AREA" mont) 0.0))))
  (BAC:_SetChave r "TC-PROPRIO" tcprop)
)


;;; ------------------------------------------------------------
;;; 7. RESUMO E FORMATACAO (linhas de texto; quem desenha e a view)
;;; ------------------------------------------------------------
;; Texto curto de uma vazao para menus
(defun BAC:RotuloVazao (vaz / qp)
  (setq qp (BAC:_Val "QP" vaz))
  (strcat (BAC:_NomeMetodo (BAC:_Val "METODO" vaz))
          "  |  TR " (HYDRO:FmtReal (BAC:_Val "TR" vaz)) " anos"
          "  |  dur. " (HYDRO:FmtReal (BAC:_Val "DUR" vaz)) " min"
          (if qp (strcat "  |  Qp " (rtos qp 2 3) " m3/s") ""))
)

;; Linhas de identificacao e caracteristicas
(defun BAC:LinhasCadastro (dados h / c atrib tc)
  (setq c (BAC:Caract dados))
  (setq tc (BAC:Tc dados))
  (setq atrib (BAC:Atrib dados))
  (append
    (list (strcat "BACIA " (BAC:_NomeExib dados h)))
    (if (BAC:_Val "AREA" c)
      (list (strcat "Area: " (rtos (/ (BAC:_Val "AREA" c) 10000.0) 2 3) " ha"))
    )
    (if (and (BAC:_Val "COMP" c) (BAC:_Val "DECL" c))
      (list (strcat "L = " (rtos (BAC:_Val "COMP" c) 2 1) " m   S = "
                    (rtos (BAC:_Val "DECL" c) 2 4) " m/m"))
    )
    (if (BAC:_Val "MIN" tc)
      (list (strcat "tc = " (rtos (BAC:_Val "MIN" tc) 2 2) " min ("
                    (BAC:_NomeTc (BAC:_Val "ORIGEM" tc)) ")"))
    )
    (if atrib
      (list
        (HYDRO:Join
          (mapcar
            (function (lambda (p) (strcat (car p) " = " (HYDRO:FmtReal (cdr p)))))
            atrib
          )
          "   "
        )
      )
    )
  )
)

;; Linhas de uma vazao calculada
(defun BAC:LinhasVazao (vaz)
  (append
    (list (strcat "[" (BAC:_NomeMetodo (BAC:_Val "METODO" vaz))
                  " - TR " (HYDRO:FmtReal (BAC:_Val "TR" vaz)) " anos]"))
    (if (BAC:_Val "I" vaz)
      (list (strcat "i = " (rtos (BAC:_Val "I" vaz) 2 2) " mm/h"
                    (if (BAC:_Val "P" vaz)
                      (strcat "   P = " (rtos (BAC:_Val "P" vaz) 2 2) " mm") "")))
    )
    (if (BAC:_Val "PE" vaz)
      (list (strcat "Pe = " (rtos (BAC:_Val "PE" vaz) 2 2) " mm"))
    )
    (if (BAC:_Val "QP" vaz)
      (list (strcat "Qp = " (rtos (BAC:_Val "QP" vaz) 2 3) " m3/s"))
    )
    (if (BAC:_Val "QP-PROPRIO" vaz)
      (list (strcat "  composta: propria " (rtos (BAC:_Val "QP-PROPRIO" vaz) 2 3)
                    " + montantes " (rtos (- (BAC:_Val "QP" vaz) (BAC:_Val "QP-PROPRIO" vaz)) 2 3)
                    " m3/s   tc de saida = " (rtos (BAC:_Val "TC" vaz) 2 1) " min"
                    (if (BAC:_Val "AREA-TOTAL" vaz)
                      (strcat "   A total = " (rtos (/ (BAC:_Val "AREA-TOTAL" vaz) 10000.0) 2 3) " ha")
                      "")))
    )
    (if (BAC:_Val "PRESERVADA" vaz)
      (list (strcat "  vazao de entrada preservada (calculada no tc maximo: "
                    (rtos (BAC:_Val "QP-CALC" vaz) 2 3) " m3/s)"))
    )
    (if (BAC:_Val "VOLUME" vaz)
      (list (strcat "Volume = " (rtos (BAC:_Val "VOLUME" vaz) 2 0) " m3"))
    )
  )
)


;; Linhas de texto da bacia com os calculos dados (cadastro + vazoes)
(defun BAC:LinhasTexto (dados h calcs / out c)
  (setq out (BAC:LinhasCadastro dados h))
  (foreach c calcs
    (setq out (append out (BAC:LinhasVazao c)))
  )
  out
)

;; toString da bacia: texto multilinha (linhas separadas por newline) com
;; cadastro, vazoes e quantidade de hidrogramas. Usado por alert e listagens.
(defun BAC:ToString (en)
  (HYDRO:Join (BAC:_ObjResumo en) "\n")
)

;;; ------------------------------------------------------------
;;; 8. TIPO NO CATALOGO (rotulos, eventos e declaracao)
;;; ------------------------------------------------------------
(HYDRO:SetLabel "HYDRO.BACIAS" "Bacias cadastradas (handles)" "")
(HYDRO:SetLabel "HYDRO.BACIA.METODO" "Ultimo metodo chuva-vazao usado" "")
(HYDRO:SetLabel "HYDRO.BACIA.TCMETODO" "Ultimo metodo de tc usado" "")
(HYDRO:SetLabel "xdata:DREN-BACIA:1005" "Talvegue relacionado" "")
(HYDRO:SetLabel "xdata:DREN-BACIA:1040" "Vazao de pico Qp" "m3/s")

(defun BAC:_ObjEh (en)
  (if (BAC:Ler en) T nil)
)

(defun BAC:_ObjNome (en)
  (BAC:_NomeExib (BAC:Ler en) (HYDRO:Handle en))
)

(defun BAC:_ObjResumo (en / dados linhas c)
  (setq dados (BAC:Ler en))
  (setq linhas (BAC:LinhasCadastro dados (HYDRO:Handle en)))
  (setq linhas (append linhas (list "" (strcat "Vazoes: " (itoa (length (BAC:Vazao dados)))))))
  (foreach c (BAC:Vazao dados)
    (setq linhas (append linhas (list (strcat "  " (BAC:RotuloVazao c)))))
  )
  (append linhas
    (list "" (strcat "Hidrogramas: " (itoa (length (BAC:Hidrogramas dados))))))
)

;; resultado do metodo desta bacia, reavaliado no tc dado (capacidade "VAZAO-EM"):
;; usa os parametros do calculo gravado para METODO e TR; nil se nao ha calculo
(defun BAC:_ObjVazaoEm (en metodo tr tc / dados c vaz m ctx res)
  (setq dados (BAC:Ler en))
  (foreach c (BAC:Vazao dados)
    (if (and (equal (BAC:_Val "METODO" c) metodo)
             (equal (BAC:_Val "TR" c) tr 1e-9))
      (setq vaz c)
    )
  )
  (setq m (HYDRO:RegGet "metodo-chuva-vazao" metodo))
  (if (and vaz m)
    (progn
      ;; reavalia SO esta bacia no tc dado, com os parametros do calculo dela
      (setq ctx
        (append
          (list (cons "TC" tc)
                (cons "TR" tr)
                (cons "DUR" (if (cdr (assoc "USA-DUR" m)) (BAC:_Val "DUR" vaz) tc)))
          (BAC:Caract dados)))
      (setq res (BAC:ExecutarMetodo metodo ctx (BAC:_Val "PARAMS" vaz)))
      (if (assoc "ERRO" res) nil res)
    )
    nil
  )
)

(defun BAC:_ObjArea (en)
  (BAC:_Val "AREA" (BAC:Caract (BAC:Ler en)))
)

;; destino padrao da bacia: o proprio talvegue
(defun BAC:_ObjTalvegue (en / h)
  (setq h (BAC:Talvegue (BAC:Ler en)))
  (if h (handent h) nil)
)

;; Remocao do cadastro de uma bacia: avisa o mecanismo de objetos, que
;; desfaz as ligacoes (a bacia nao conhece os plugins de objetos/ligacao)
(defun BAC:_ObjOnRemovida (dados)
  (HYDRO:Emit "objeto.removido" (list (cons "OBJETO" (cdr (assoc "BACIA" dados)))))
)

(HYDRO:On "bacia.removida" "bacia" 'BAC:_ObjOnRemovida)

;; regra da bacia sobre si mesma: so bacias descarregam em bacias
(defun BAC:_ObjRegra (tipo-origem tipo-destino)
  (if (and (equal tipo-destino "bacia") (not (equal tipo-origem "bacia")))
    "Somente bacias descarregam em bacias."
    nil
  )
)

(if (HYDRO:Has "objetos")
  (OBJ:RegistrarTipo
    "bacia"
    "Bacia"
    "Bacia hidrografica (contorno + talvegue). Cadastre com BACIACAD."
    '("LWPOLYLINE" "POLYLINE" "SPLINE");aceita
    nil;params
    T;recebe
    T;emite
    (list
      (cons "CADASTRAVEL" nil)
      (cons "DETECTA" 'BAC:_ObjEh)
      (cons "ARMAZENAMENTO"
        (list (cons "LER" 'BAC:Ler)
              (cons "GRAVAR" 'BAC:Gravar)
              (cons "LISTAR" 'BAC:Listar)
              (cons "REINDEXAR" 'BAC:Reindexar)
              (cons "REMOVER" 'BAC:Remover)))
      (cons "NOME-FN" 'BAC:_ObjNome)
      (cons "RESUMO" 'BAC:_ObjResumo)
      (cons "TOSTRING" 'BAC:ToString)
      (cons "VAZAO-EM" 'BAC:_ObjVazaoEm)
      (cons "TEMPO-MODO" "concentracao")
      (cons "AREA-PROPRIA" 'BAC:_ObjArea)
      (cons "DESTINO-PADRAO" 'BAC:_ObjTalvegue)
      (cons "REGRA" 'BAC:_ObjRegra)
      (cons "EDITAR" 'BAC:EditarCadastro)
    );extras
  )
)

;;; ------------------------------------------------------------
;;; 9. COMANDOS E INTERACAO (linha de comando)
;;; ------------------------------------------------------------
;; Comandos c: de linha de comando e as perguntas que eles fazem. Ficam aqui
;; para o objeto funcionar carregando so este arquivo. Texto inserido no
;; desenho fica em views/bacia_view.lsp e o dialogo em views/bacia_tabela.lsp.
;;
;; COMANDOS
;;   BACIACAD   cadastra/atualiza a bacia (sem calcular vazao)
;;   BACIA      calcula a vazao por um metodo cadastrado
;;   BACIAS     lista as bacias do desenho (a tabela esta em BACIATABELA)
;;   BACIAINFO  mostra a bacia (BAC:ToString)

;; Pede uma polilinha (contorno ou talvegue). Retorna o ename ou nil.
(defun BAC:_SelLinha (msg / ss)
  (princ msg)
  (if (setq ss (ssget "_:S" '((0 . "LWPOLYLINE,POLYLINE,SPLINE"))))
    (ssname ss 0)
    nil
  )
)

;; Mostra o tc pelo metodo padrao e permite aceitar, trocar de metodo ou
;; informar um valor. Retorna (tc origem params).
(defun BAC:_EscolheTc (caract id-padrao params-padrao /
                       tcmin id params res tcdef op lista idx m origem tc itens pos i)
  (setq tcmin (HYDRO:Get "HYDRO.TC.MINIMO" 10.0))
  (setq id
    (if (and id-padrao (BAC:_MetodoTcOk id-padrao))
      id-padrao
      (HYDRO:Get "HYDRO.BACIA.TCMETODO" "kirpich")
    )
  )
  (setq params
    (if (and params-padrao (equal id id-padrao))
      params-padrao
      (BAC:_ParamsTc id)
    )
  )
  (setq res (BAC:CalcularTc id caract params))
  (while (not origem)
    (setq tcdef
      (if (assoc "ERRO" res) tcmin (max (BAC:_Val "TC" res) tcmin)))
    (if (assoc "ERRO" res)
      (progn
        (princ (strcat "\n[BACIA] " (BAC:_Val "ERRO" res)))
        (setq op (if (BAC:_ListaTc) "Outro" "Informar"))
      )
      (progn
        (princ
          (strcat "\ntc (" (BAC:_NomeTc id) ") = " (rtos (BAC:_Val "TC" res) 2 2)
                  " min;  minimo " (rtos tcmin 2 1) " min  ->  " (rtos tcdef 2 2) " min"))
        (initget "Aceitar Outro Informar")
        (setq op
          (getkword "\nTempo de concentracao [Aceitar/Outro metodo/Informar valor] <Aceitar>: "))
      )
    )
    (cond
      ((equal op "Outro")
        (setq lista (BAC:_ListaTc))
        (if lista
          (progn
            (setq itens
              (mapcar
                (function
                  (lambda (x)
                    (strcat (cdr (assoc "NOME" (cdr x))) "  -  "
                            (cdr (assoc "DESC" (cdr x))))
                  )
                )
                lista
              )
            )
            (setq i 0 pos 0)
            (foreach m lista
              (if (equal (car m) id) (setq pos i))
              (setq i (1+ i))
            )
            (setq idx (HYDRO:Escolher "Metodos de tempo de concentracao:" itens pos))
            (setq id (car (nth idx lista)))
            (setq m (cdr (nth idx lista)))
            (setq params
              (HYDRO:AskParams (cdr (assoc "PARAMS" m))
                               (strcat "HYDRO.TC." id ".") nil))
            (setq res (BAC:CalcularTc id caract params))
            (if (not (assoc "ERRO" res))
              (HYDRO:Set "HYDRO.BACIA.TCMETODO" id)
            )
          )
          (princ "\nNenhum outro metodo de tc cadastrado.")
        )
      )
      ((equal op "Informar")
        (setq tc (HYDRO:AskReal "tc (min)" tcdef))
        (if (and tc (> tc 0.0))
          (progn (setq origem "usuario") (setq params nil))
          (princ "\ntc invalido.")
        )
      )
      (T
        (if (not (assoc "ERRO" res))
          (progn (setq tc tcdef) (setq origem id))
        )
      )
    )
  )
  (list tc origem params)
)

;; Pergunta o nome (Enter mantem o atual; sem nome, usa "B-<handle>")
(defun BAC:_PedeNome (atual / r)
  (setq r
    (getstring T
      (strcat "\nNome da bacia"
              (if atual (strcat " <" atual ">") " (Enter = automatico)")
              ": ")))
  (if (and r (/= r "")) r atual)
)

;; Pergunta os atributos C e CN (Enter mantem/pula)
(defun BAC:_PedeAtrib (atrib / c cn)
  (setq c  (HYDRO:AskReal "Coeficiente de escoamento C (Enter = manter/pular)" (BAC:_Val "C" atrib)))
  (setq cn (HYDRO:AskReal "Numero da curva CN (Enter = manter/pular)" (BAC:_Val "CN" atrib)))
  (if (and c (or (<= c 0.0) (> c 1.0)))
    (progn (princ "\nC deve estar entre 0 e 1: ignorado.") (setq c (BAC:_Val "C" atrib)))
  )
  (if (and cn (or (< cn 1.0) (> cn 100.0)))
    (progn (princ "\nCN deve estar entre 1 e 100: ignorado.") (setq cn (BAC:_Val "CN" atrib)))
  )
  (BAC:_Limpa (list (cons "C" c) (cons "CN" cn)))
)

;; Cadastro interativo (nome, tc por metodo, C e CN). Retorna o contexto
;; (BAC:_Ctx) ou (("ERRO" . msg)).
(defun BAC:CadastroInterativo (contorno talvegue /
                               dados caract old nome tcr atrib tc)
  (setq dados (BAC:Ler contorno))
  (setq old (BAC:Tc dados))
  (setq caract (BAC:Caracterizar contorno talvegue))
  (cond
    ((assoc "ERRO" caract) caract)
    (T
      (princ
        (strcat "\nArea " (rtos (/ (BAC:_Val "AREA" caract) 10000.0) 2 3) " ha;  talvegue "
                (rtos (BAC:_Val "COMP" caract) 2 1) " m;  declividade "
                (rtos (BAC:_Val "DECL" caract) 2 4) " m/m"))
      (setq nome (BAC:_PedeNome (BAC:Nome dados)))
      (setq tcr
        (BAC:_EscolheTc caract (BAC:_Val "ORIGEM" old) (BAC:_Val "PARAMS" old)))
      (setq atrib (BAC:_PedeAtrib (BAC:Atrib dados)))
      (setq tc
        (list (cons "MIN" (nth 0 tcr))
              (cons "ORIGEM" (nth 1 tcr))
              (cons "PARAMS" (nth 2 tcr))))
      (BAC:Cadastrar contorno talvegue nome atrib caract tc)
      (BAC:_Ctx (BAC:Ler contorno))
    )
  )
)

;; Talvegue: reaproveita o cadastrado ou pede a selecao
(defun BAC:_SelTalvegue (dados / h op)
  (setq h (BAC:Talvegue dados))
  (if (and h (handent h))
    (progn
      (initget "Usar Trocar")
      (setq op
        (getkword
          (strcat "\nTalvegue cadastrado (handle " h "). [Usar/Trocar] <Usar>: ")))
      (if (equal op "Trocar")
        (BAC:_SelLinha "\nSelecione a polilinha do TALVEGUE: ")
        (handent h)
      )
    )
    (BAC:_SelLinha "\nSelecione a polilinha do TALVEGUE: ")
  )
)

;; Edita o cadastro de uma bacia ja selecionada. Retorna T ou nil.
(defun BAC:EditarCadastro (en / dados talv cad)
  (setq dados (BAC:Ler en))
  (setq talv (BAC:_SelTalvegue dados))
  (if talv
    (progn
      (setq cad (BAC:CadastroInterativo en talv))
      (if (assoc "ERRO" cad)
        (progn (alert (strcat "Erro: " (BAC:_Val "ERRO" cad))) nil)
        T
      )
    )
    (progn (princ "\nTalvegue nao selecionado.") nil)
  )
)

(defun BAC:_IdxMetodoPadrao (lista / ult i pos m)
  (setq ult (HYDRO:Get "HYDRO.BACIA.METODO" nil))
  (setq i 0 pos 0)
  (foreach m lista
    (if (equal (car m) ult) (setq pos i))
    (setq i (1+ i))
  )
  pos
)

;; Menu dos metodos chuva-vazao cadastrados. Retorna o id ou nil.
(defun BAC:_EscolheMetodo (/ lista itens idx)
  (setq lista (HYDRO:RegList "metodo-chuva-vazao"))
  (if lista
    (progn
      (setq itens
        (mapcar
          (function
            (lambda (m)
              (strcat (cdr (assoc "NOME" (cdr m))) "  -  "
                      (cdr (assoc "DESC" (cdr m))))
            )
          )
          lista
        )
      )
      (setq idx
        (HYDRO:Escolher "Metodos chuva-vazao cadastrados:" itens
                        (BAC:_IdxMetodoPadrao lista))
      )
      (car (nth idx lista))
    )
    nil
  )
)

;; Pergunta TR, metodo, duracao e parametros. Retorna alist
;; (TR ID DUR PARAMS) ou nil.
(defun BAC:_PerguntasCalculo (cad / tr id m dur params)
  (setq tr (HYDRO:AskReal "Tempo de retorno (anos)" (HYDRO:Get "HYDRO.TR" nil)))
  (cond
    ((or (not tr) (<= tr 0.0))
      (alert "Tempo de retorno nao informado.")
      nil
    )
    (T
      (setq id (BAC:_EscolheMetodo))
      (if (not id)
        (progn (alert "Metodo nao escolhido.") nil)
        (progn
          (setq m (HYDRO:RegGet "metodo-chuva-vazao" id))
          (HYDRO:Set "HYDRO.TR" tr)
          (HYDRO:Set "HYDRO.BACIA.METODO" id)
          (setq dur
            (if (cdr (assoc "USA-DUR" m))
              (HYDRO:AskReal "Duracao da chuva (min)" (BAC:_Val "TC" cad))
              (BAC:_Val "TC" cad)
            )
          )
          (setq params
            (HYDRO:AskParams
              (cdr (assoc "PARAMS" m))
              (strcat "HYDRO.MET." id ".")
              (BAC:_Sobrescritas cad (cdr (assoc "PARAMS" m)))
            )
          )
          (list (cons "TR" tr) (cons "ID" id) (cons "DUR" dur) (cons "PARAMS" params))
        )
      )
    )
  )
)

;; Fluxo completo: contorno, talvegue, cadastro (se preciso), perguntas e
;; calculo. Retorna (contorno . calculo) ou nil.
(defun BAC:_FluxoCalculo (/ contorno dados talv cad perg calc)
  (setq contorno (BAC:_SelLinha "\nSelecione a polilinha do CONTORNO da bacia: "))
  (cond
    ((not contorno) nil)
    (T
      (if (not (BAC:_Fechada contorno))
        (princ "\nAviso: o contorno nao esta fechado; a area sera a da figura fechada pela corda.")
      )
      (setq dados (BAC:Ler contorno))
      (setq talv (BAC:_SelTalvegue dados))
      (cond
        ((not talv) (princ "\nTalvegue nao selecionado.") nil)
        ((not (HYDRO:RegList "metodo-chuva-vazao"))
          (alert "Nenhum metodo chuva-vazao cadastrado (plugin 'metodos').")
          nil
        )
        (T
          ;; sem cadastro (ou talvegue trocado): cadastra com perguntas;
          ;; com cadastro: reutiliza (e atualiza se a geometria mudou)
          (setq cad
            (if (or (not dados)
                    (not (equal (BAC:Talvegue dados) (HYDRO:Handle talv))))
              (BAC:CadastroInterativo contorno talv)
              (BAC:Obter contorno talv)
            )
          )
          (cond
            ((assoc "ERRO" cad)
              (alert (strcat "Erro: " (BAC:_Val "ERRO" cad)))
              nil
            )
            (T
              (princ
                (strcat "\nUsando tc = " (rtos (BAC:_Val "TC" cad) 2 2) " min ("
                        (BAC:_NomeTc (BAC:_Val "TC-ORIGEM" cad))
                        "). Para alterar: BACIACAD."))
              (setq perg (BAC:_PerguntasCalculo cad))
              (if perg
                (progn
                  (setq calc (BAC:_CalcularEGravar contorno talv cad perg))
                  (cond
                    ((assoc "ERRO" calc)
                      (alert (strcat "Erro: " (BAC:_Val "ERRO" calc)))
                      nil
                    )
                    (T (cons contorno calc))
                  )
                )
                nil
              )
            )
          )
        )
      )
    )
  )
)

;; Texto do alert apos um calculo: cadastro + o calculo recem feito
(defun BAC:_Resumo (contorno calc)
  (HYDRO:Join
    (BAC:LinhasTexto (BAC:Ler contorno) (HYDRO:Handle contorno) (list calc))
    "\n")
)

(defun c:BACIACAD (/ contorno)
  (setq contorno (BAC:_SelLinha "\nSelecione a polilinha do CONTORNO da bacia: "))
  (if contorno
    (if (BAC:EditarCadastro contorno)
      (alert (BAC:ToString contorno))
    )
  )
  (princ)
)

(defun c:BACIA (/ r)
  (setq r (BAC:_FluxoCalculo))
  (if r (alert (BAC:_Resumo (car r) (cdr r))))
  (princ)
)

;; Escolhe quais calculos entram no texto: um ou todos
(defun BAC:_EscolheCalculos (dados / calcs idx)
  (setq calcs (BAC:Vazao dados))
  (cond
    ((null calcs) nil)
    ((= (length calcs) 1) calcs)
    (T
      (setq idx
        (HYDRO:Escolher "Calculos da bacia:"
          (cons "Todos os calculos" (mapcar 'BAC:RotuloVazao calcs))
          (length calcs)))
      (if (= idx 0) calcs (list (nth (1- idx) calcs)))
    )
  )
)

;; Seleciona um contorno que ja tem cadastro
(defun BAC:_SelBaciaCad (/ en)
  (setq en (BAC:_SelLinha "\nSelecione o CONTORNO da bacia: "))
  (cond
    ((not en) nil)
    ((not (BAC:Ler en))
      (alert "Esta entidade nao tem cadastro de bacia. Use BACIACAD ou BACIA.")
      nil
    )
    (T en)
  )
)

(defun c:BACIAS (/ lista en dados)
  (setq lista (BAC:Listar))
  (if lista
    (progn
      (princ "\n=== BACIAS DO DESENHO ===")
      (princ "\nnome   handle   area(ha)   tc(min)   calculos   hidrogramas   Qp max (m3/s)")
      (foreach en lista
        (setq dados (BAC:Ler en))
        (princ
          (strcat "\n" (BAC:_NomeExib dados (HYDRO:Handle en))
                  "   " (HYDRO:Handle en)
                  "   " (rtos (/ (BAC:_Val "AREA" (BAC:Caract dados)) 10000.0) 2 3)
                  "   " (rtos (BAC:_Val "MIN" (BAC:Tc dados)) 2 1)
                  "   " (itoa (length (BAC:Vazao dados)))
                  "   " (itoa (length (BAC:Hidrogramas dados)))
                  "   " (rtos (BAC:_MaxQp dados) 2 3))
        )
      )
      (princ "\n(Tabela completa: BACIATABELA)")
    )
    (princ "\nNenhuma bacia cadastrada neste desenho (use BACIACAD).")
  )
  (princ)
)

(defun c:BACIAINFO (/ en)
  (setq en (BAC:_SelBaciaCad))
  (if en (alert (BAC:ToString en)))
  (princ)
)

;; Encontra uma bacia por nome ou handle, da zoom e a seleciona (fluxo padrao
;; de views/objetos_padrao_view.lsp)
(defun c:BACIAZOOM ()
  (if (HYDRO:Has "objetos-padrao-view")
    (OPV:Zoom "bacia")
    (alert "BACIAZOOM indisponivel: carregue objetos_padrao e a view dele.")
  )
  (princ)
)

(HYDRO:Provide "bacia" "3.0")
(princ)
