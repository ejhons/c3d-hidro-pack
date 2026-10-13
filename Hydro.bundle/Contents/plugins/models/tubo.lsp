;;; ============================================================
;;; models/tubo.lsp - MODELO TUBO / CANAL (TUB:)
;;;
;;; Tubo, galeria ou canal de seccao circular, retangular ou trapezoidal, calculado
;;; em ESCOAMENTO UNIFORME pela equacao de Manning: dadas a vazao (entrada, dos
;;; montantes), a declividade e a seccao, resolve a ALTURA da lamina d'agua.
;;;
;;; ENTIDADE: LINE, LWPOLYLINE ou POLYLINE 3D. Declividade = |cota inicial - cota
;;; final| / comprimento da entidade (so os pontos inicial e final e o comprimento
;;; contam; os vertices intermediarios nao). Linha 2D (cotas iguais) nao tem declividade
;;; no desenho: ela e digitada (CARACT-DEFS; TUBOEDITA). Sentido do escoamento: nao
;;; usado (a declividade e em modulo).
;;;
;;; ESTRUTURA DO ARQUIVO (padrao dos models; ver .claude/skills/hydro-model)
;;;   1. UTILITARIOS
;;;   2. GEOMETRIA (CARACTERIZACAO)
;;;   3. LER, GRAVAR, EDITAR, REMOVER
;;;   4. CAMPOS (CARACT, PARAMS e ATRIB)     inclui o CATALOGO de seccoes
;;;   5. RESULTADOS (RESULT)
;;;   6. CALCULOS                             Manning, area/perimetro, resolucao da altura
;;;   7. RESUMO E FORMATACAO
;;;   8. TIPO NO CATALOGO
;;;   9. COMANDOS E INTERACAO (TUBOCAD, TUBOEDITA, TUBOS, TUBOINFO, TUBOZOOM) e AUDITORIA
;;;   toString: TUB:ToString (secao 7), tambem a capacidade "TOSTRING" do tipo
;;;
;;; REGISTRO (formato padrao, docs/arquitetura.md secao 18)
;;;   ATRIB   SECAO  id de uma seccao do catalogo (CRIASECAOTUBO / SECAOTUBO)
;;;           N      rugosidade de Manning (0 = usar a da seccao)
;;;   CARACT  COMP, DECL (e COTA-INI, COTA-FIM) do desenho (CARACTERIZA) ou digitados
;;;           (CARACT-DEFS; chaves digitadas em CARACT "MANUAL")
;;;   PARAMS  so JUSANTE (ligacao)
;;;   RESULT  por CENARIO (docs/plano_resultados_cenarios.md). Grupos do tubo:
;;;           ENTRADA ("VALOR" . m3/s) ("TC" . min) ("AREA" . m2)     (core de ligacao)
;;;           VAZAO   ("VALOR" . m3/s) ("TC" . min) ("METODO" ..)      (saida; core)
;;;           ALTURA_LAMINA ("VALOR" . m) ("METODO" . "manning")
;;;           AREA_MOLHADA ("VALOR" . m2)   VELOCIDADE ("VALOR" . m/s)
;;;           RAZAO_ENCHIMENTO ("VALOR" . y/D ou y/H)   FROUDE ("VALOR" ..)
;;;           CAPACIDADE ("VALOR" . m3/s a seccao cheia) ["EXCEDIDA" . T]
;;;           PERCURSO ("VALOR" . min)   AVISOS ("VALOR" . lista de textos)
;;;           Seccao, n, COMP e DECL NAO sao copiados: estao em ATRIB/CARACT.
;;;
;;; CATALOGO DE SECCOES (HYDRO.SECOES.TUBO; como o das sarjetas, mas por forma)
;;;   seccao = (id ("forma" . "circular"|"retangular"|"trapezoidal")
;;;                ("d" . m)            circular: diametro
;;;                ("b" . m) ("h" . m)  retangular/trapezoidal: largura (base) e altura
;;;                ("z" . m/m)          trapezoidal: talude z H : 1 V
;;;                ("n" . manning))
;;;   GERENCIAMENTO em arquivo separado, como as sarjetas: plugins/secao_tubo.lsp (STB:Adicionar,
;;;   Editar, Remover, EmUso, UltimoCalculo...) e comandos em views/secao_tubo_view.lsp
;;;   (CRIASECAOTUBO, EDITASECAOTUBO, REMOVESECAOTUBO, SECAOTUBO). Aqui so a leitura
;;;   (TUB:Secoes) e o calculo. Seccao atual: HYDRO.SECAO.TUBO.ATUAL.
;;;
;;; CALCULO (comando CALCULAOBJETO; o tubo PRECISA de montante)
;;;   Manning (escoamento uniforme, regime permanente): Q = (1/n) A R^(2/3) S^(1/2),
;;;   R = A/P. Fonte: Chow, V.T. Open-Channel Hydraulics, 1959 (cap. 5 e 7).
;;;   Circular parcialmente cheia: theta = 2 acos(1 - 2y/D), A = D^2 (theta - sin theta)/8,
;;;   P = D theta / 2, T = D sin(theta/2). Trapezio: A = (b + z y) y, P = b + 2 y sqrt(1+z^2),
;;;   T = b + 2 z y. Retangulo: z = 0.
;;;   A altura y vem de BISSECAO em Q(y) = Q (60 iteracoes). Circular: Q(y) cresce ate
;;;   y = 0.9382 D (vazao maxima) e cai ate a seccao plena; se Q passa da maxima nao ha
;;;   lamina livre: y = D (escoamento sob pressao, AVISO). Retangular/trapezoidal: se Q
;;;   passa da capacidade em y = h, y = h (AVISO). Froude = V / sqrt(g A / T), g = 9.81.
;;;   FAIXA DE VALIDADE: S > 0, n > 0, Q > 0; escoamento uniforme e permanente; Froude
;;;   proximo de 1 (0.9 a 1.1) e instavel (AVISO). Nao ha limites de velocidade nem de
;;;   enchimento embutidos (dependem da norma do projeto).
;;;   tempo de percurso = COMP / V (modo "percurso", ligacao.lsp): tc de saida = max tc dos
;;;   montantes + percurso.
;;; ============================================================
(vl-load-com)


;;; ------------------------------------------------------------
;;; 1. UTILITARIOS
;;; ------------------------------------------------------------
(defun TUB:_Erro (msg)
  (list (cons "ERRO" msg))
)

;; valor de uma chave de uma seccao (id ("k" . v) ...)
(defun TUB:Val (chave sec)
  (cdr (assoc chave (cdr sec)))
)

;; arco-cosseno (AutoLISP nao tem), x em [-1, 1], resultado em [0, pi]
(defun TUB:_Acos (x)
  (cond
    ((>= x 1.0) 0.0)
    ((<= x -1.0) pi)
    ((equal x 0.0 1e-12) (/ pi 2.0))
    ((> x 0.0) (atan (/ (sqrt (- 1.0 (* x x))) x)))
    (T (+ pi (atan (/ (sqrt (- 1.0 (* x x))) x))))
  )
)


;;; ------------------------------------------------------------
;;; 2. GEOMETRIA (CARACTERIZACAO)
;;; ------------------------------------------------------------
;; comprimento da entidade (m), ou nil
(defun TUB:_Comprimento (en / r)
  (setq r
    (vl-catch-all-apply
      (function
        (lambda ()
          (vlax-curve-getDistAtParam en (vlax-curve-getEndParam en))))
      nil))
  (if (vl-catch-all-error-p r) nil r)
)

;; cota (Z) do ponto inicial (fim = nil) ou final (fim = T), ou nil
(defun TUB:_Cota (en fim / p)
  (setq p
    (vl-catch-all-apply
      (function
        (lambda ()
          (if fim (vlax-curve-getEndPoint en) (vlax-curve-getStartPoint en))))
      nil))
  (if (or (vl-catch-all-error-p p) (null p)) nil (caddr p))
)

;; (puro) declividade |z1 - z2| / comp; nil se falta dado, comp <= 0 ou cotas iguais
;; (linha 2D: sem declividade no desenho)
(defun TUB:_Decl (comp z1 z2)
  (if (and comp z1 z2 (> comp 0.0) (> (abs (- z1 z2)) 1e-9))
    (/ (abs (- z1 z2)) comp)
    nil
  )
)

;; CARACT do desenho: COMP e, se as cotas inicial e final diferem, DECL, COTA-INI, COTA-FIM.
;; vinculos: o tubo nao tem. O que nao der para ler nao entra (o cadastro pergunta).
(defun TUB:Caracterizar (en vinculos / comp z1 z2 decl)
  (setq comp (TUB:_Comprimento en))
  (setq z1 (TUB:_Cota en nil))
  (setq z2 (TUB:_Cota en T))
  (setq decl (TUB:_Decl comp z1 z2))
  (OBJ:_Limpa
    (list
      (cons "COMP" (if (and comp (> comp 0.0)) comp nil))
      (cons "DECL" decl)
      (cons "COTA-INI" (if decl z1 nil))
      (cons "COTA-FIM" (if decl z2 nil))
    )
  )
)


;;; ------------------------------------------------------------
;;; 3. LER, GRAVAR, EDITAR, REMOVER
;;; ------------------------------------------------------------
;; O tubo HERDA a porta de armazenamento da classe base (objetos.lsp):
;;   ler      OBJ:Ler / OBJ:Registro      gravar   OBJ:GravaRegistro
;;   cadastro generico (OBJ:CadastrarCom; TUBOCAD) e um campo (TUBOEDITA); remover OBJ:Remover
;; Nada proprio a declarar.


;;; ------------------------------------------------------------
;;; 4. CAMPOS (CARACT, PARAMS e ATRIB)
;;; ------------------------------------------------------------
;; GERENCIAMENTO do catalogo (criar, editar, remover, em uso, ultimo calculo): plugins/secao_tubo.lsp
;; (STB:) e comandos em views/secao_tubo_view.lsp. Aqui so a LEITURA usada pelo model.

;; seccoes de fabrica (usadas ate o usuario cadastrar as dele)
(defun TUB:_SecoesPadrao ()
  (list
    (list 0 (cons "forma" "circular") (cons "d" 0.6) (cons "n" 0.013))
    (list 1 (cons "forma" "retangular") (cons "b" 1.0) (cons "h" 1.0) (cons "n" 0.015))
    (list 2 (cons "forma" "trapezoidal") (cons "b" 1.0) (cons "h" 1.0) (cons "z" 1.5) (cons "n" 0.025))
  )
)

(defun TUB:Secoes ()
  (HYDRO:Get "HYDRO.SECOES.TUBO" (TUB:_SecoesPadrao))
)

(defun TUB:SecaoAtualId ()
  (HYDRO:Get "HYDRO.SECAO.TUBO.ATUAL" 0)
)

;; seccao (id ("k" . v) ...) pelo id, ou nil
(defun TUB:_Secao (id)
  (assoc id (TUB:Secoes))
)

;; texto curto de uma seccao
(defun TUB:RotuloSecao (sec / f)
  (setq f (TUB:Val "forma" sec))
  (strcat "Secao " (itoa (car sec)) "  |  "
          (cond
            ((equal f "circular")
              (strcat "circular  D=" (rtos (TUB:Val "d" sec) 2 3) " m"))
            ((equal f "retangular")
              (strcat "retangular  b=" (rtos (TUB:Val "b" sec) 2 3) " m  h="
                      (rtos (TUB:Val "h" sec) 2 3) " m"))
            (T
              (strcat "trapezoidal  b=" (rtos (TUB:Val "b" sec) 2 3) " m  h="
                      (rtos (TUB:Val "h" sec) 2 3) " m  z="
                      (rtos (TUB:Val "z" sec) 2 2)))
          )
          "  |  n=" (rtos (TUB:Val "n" sec) 2 4))
)

;; ATRIB (o usuario define): (chave rotulo padrao unidade [tipo [opcoes]])
(defun TUB:_AtribDefs ()
  (list
    (list "SECAO" "Id da secao (SECAOTUBO)" 0 "" "int")
    (list "N" "Rugosidade de Manning (0 = a da secao)" 0.0 "")
  )
)

;; CARACT-DEFS: o que se digita quando o desenho nao informa
(defun TUB:_CaractDefs ()
  (list
    (list "COMP" "Comprimento" 0.0 "m")
    (list "DECL" "Declividade" 0.0 "m/m")
  )
)

;; PADROES de ATRIB: a seccao atual do catalogo
(defun TUB:_Padroes (en)
  (list (cons "SECAO" (TUB:SecaoAtualId)))
)

;; rugosidade efetiva: a do objeto (se > 0) ou a da seccao
(defun TUB:_N (dados sec / n)
  (setq n (cdr (assoc "N" dados)))
  (if (and n (> n 0.0)) n (TUB:Val "n" sec))
)


;;; ------------------------------------------------------------
;;; 5. RESULTADOS (RESULT)
;;; ------------------------------------------------------------
;; "VALOR" de um grupo do cenario (ou nil); para AVISOS, a lista de textos
(defun TUB:_V (en cenario grupo)
  (OBJ:_Val "VALOR" (OBJ:ResultGrupoDe en cenario grupo))
)

(defun TUB:Lamina (en cenario) (TUB:_V en cenario "ALTURA_LAMINA"))


;;; ------------------------------------------------------------
;;; 6. CALCULOS
;;; ------------------------------------------------------------
;; altura maxima da seccao: D (circular) ou h
(defun TUB:_YMax (sec)
  (if (equal (TUB:Val "forma" sec) "circular") (TUB:Val "d" sec) (TUB:Val "h" sec))
)

;; (puro) geometria hidraulica na altura y: (("A" . m2) ("P" . m) ("T" . m)); y e limitado a altura maxima
(defun TUB:_Geom (sec y / forma d b z th)
  (setq forma (TUB:Val "forma" sec))
  (setq y (min y (TUB:_YMax sec)))
  (cond
    ((equal forma "circular")
      (setq d (TUB:Val "d" sec))
      (setq th (* 2.0 (TUB:_Acos (- 1.0 (/ (* 2.0 y) d)))))
      (list (cons "A" (* (/ (* d d) 8.0) (- th (sin th))))
            (cons "P" (* d (/ th 2.0)))
            (cons "T" (* d (sin (/ th 2.0)))))
    )
    (T
      (setq b (TUB:Val "b" sec))
      (setq z (if (TUB:Val "z" sec) (TUB:Val "z" sec) 0.0))
      (list (cons "A" (* (+ b (* z y)) y))
            (cons "P" (+ b (* 2.0 y (sqrt (+ 1.0 (* z z))))))
            (cons "T" (+ b (* 2.0 z y))))
    )
  )
)

;; (puro) Manning: Q = (1/n) A R^(2/3) S^(1/2); 0 se a geometria e degenerada
(defun TUB:_Q (geom n s / a p)
  (setq a (cdr (assoc "A" geom)))
  (setq p (cdr (assoc "P" geom)))
  (if (and a p (> a 0.0) (> p 0.0))
    (* (/ 1.0 n) a (expt (/ a p) (/ 2.0 3.0)) (sqrt s))
    0.0
  )
)

;; (puro) Resolve a altura y do escoamento uniforme para a vazao q.
;;   sec : seccao do catalogo; s : declividade (m/m); n : Manning; q : vazao (m3/s)
;;   retorno: (("Y" . m) ("A" . m2) ("P" . m) ("T" . m) ("V" . m/s) ("RAZAO" . y/ymax)
;;             ("FR" . Froude|nil) ("QCAP" . m3/s a seccao cheia) ("QMAX" . maior vazao
;;             com lamina livre) ("CHEIO" . T se q passa do limite) ("AVISOS" . lista))
;;   ou (("ERRO" . msg)).
(defun TUB:Resolver (sec s n q /
                     ymax ylim qlim qcap lo hi mid i y g a p tt v fr cheio avisos circ)
  (setq ymax (TUB:_YMax sec))
  (setq circ (equal (TUB:Val "forma" sec) "circular"))
  (cond
    ((not ymax) (TUB:_Erro "Seccao invalida."))
    ((or (not s) (<= s 0.0)) (TUB:_Erro "Declividade ausente ou nula."))
    ((or (not n) (<= n 0.0)) (TUB:_Erro "Rugosidade de Manning invalida."))
    ((or (not q) (<= q 0.0)) (TUB:_Erro "Nao ha vazao afluente."))
    (T
      ;; limite da lamina livre: circular, y = 0.9382 D (vazao maxima); demais, y = h
      (setq ylim (if circ (* 0.9382 ymax) ymax))
      (setq qlim (TUB:_Q (TUB:_Geom sec ylim) n s))
      (setq qcap (TUB:_Q (TUB:_Geom sec ymax) n s))
      (if (> q qlim)
        (progn (setq y ymax) (setq cheio T))
        (progn
          (setq lo (* 1e-6 ymax))
          (setq hi ylim)
          (setq i 0)
          (while (< i 60)
            (setq mid (/ (+ lo hi) 2.0))
            (if (< (TUB:_Q (TUB:_Geom sec mid) n s) q)
              (setq lo mid)
              (setq hi mid))
            (setq i (1+ i))
          )
          (setq y (/ (+ lo hi) 2.0))
        )
      )
      (setq g (TUB:_Geom sec y))
      (setq a (cdr (assoc "A" g)))
      (setq p (cdr (assoc "P" g)))
      (setq tt (cdr (assoc "T" g)))
      (setq v (/ q a))
      (setq fr (if (> tt 1e-9) (/ v (sqrt (/ (* 9.81 a) tt))) nil))
      (if cheio
        (setq avisos
          (append avisos
            (list
              (if circ
                "vazao maior que a maxima com lamina livre: escoamento sob pressao (a altura e o diametro)"
                "vazao maior que a capacidade da seccao: altura limitada a h"))))
      )
      (if (and fr (> fr 0.9) (< fr 1.1))
        (setq avisos
          (append avisos (list "Froude proximo de 1: regime instavel, resultado incerto")))
      )
      (list
        (cons "Y" y) (cons "A" a) (cons "P" p) (cons "T" tt) (cons "V" v)
        (cons "RAZAO" (/ y ymax)) (cons "FR" fr)
        (cons "QCAP" qcap) (cons "QMAX" qlim) (cons "CHEIO" cheio) (cons "AVISOS" avisos)
      )
    )
  )
)

;; Capacidade CALCULA: devolve GRUPOS ((grupo . campos) ...) ou (("ERRO" . msg)).
;; Quem grava e LIG:CalcularCore (junto com ENTRADA e VAZAO). ctx tem ("ENTRADA" ("QP" ..) ..).
(defun TUB:Calcular (en ctx params / dados id sec q cr decl comp n r)
  (setq dados (OBJ:AtribDe en))
  (setq id (cdr (assoc "SECAO" dados)))
  (setq sec (if id (TUB:_Secao id) nil))
  (setq q (cdr (assoc "QP" (cdr (assoc "ENTRADA" ctx)))))
  (setq cr (OBJ:CaractDe en))
  (setq decl (cdr (assoc "DECL" cr)))
  (setq comp (cdr (assoc "COMP" cr)))
  (cond
    ((not sec)
      (TUB:_Erro
        (strcat "Secao " (if id (itoa id) "?")
                " nao cadastrada. Edite o objeto (TUBOEDITA) ou crie a secao (CRIASECAOTUBO).")))
    ((or (not q) (<= q 0.0))
      (TUB:_Erro "Nao ha vazao afluente: ligue bacias ou outros objetos calculados a este tubo (LIGAR)."))
    ((or (not decl) (<= decl 0.0))
      (TUB:_Erro
        "Declividade ausente: use polilinha 3D / linha com cotas diferentes ou digite-a (TUBOEDITA)."))
    ((or (not comp) (<= comp 0.0))
      (TUB:_Erro "Comprimento ausente. Digite-o (TUBOEDITA)."))
    (T
      (setq n (TUB:_N dados sec))
      (setq r (TUB:Resolver sec decl n q))
      (if (assoc "ERRO" r)
        r
        (list
          (cons "ALTURA_LAMINA"
            (list (cons "VALOR" (cdr (assoc "Y" r))) (cons "METODO" "manning")))
          (cons "AREA_MOLHADA" (list (cons "VALOR" (cdr (assoc "A" r)))))
          (cons "VELOCIDADE" (list (cons "VALOR" (cdr (assoc "V" r)))))
          (cons "RAZAO_ENCHIMENTO" (list (cons "VALOR" (cdr (assoc "RAZAO" r)))))
          (cons "FROUDE" (list (cons "VALOR" (cdr (assoc "FR" r)))))
          (cons "CAPACIDADE"
            (list (cons "VALOR" (cdr (assoc "QCAP" r)))
                  (cons "EXCEDIDA" (cdr (assoc "CHEIO" r)))))
          (cons "PERCURSO" (list (cons "VALOR" (/ comp (cdr (assoc "V" r)) 60.0))))
          (cons "AVISOS" (list (cons "VALOR" (cdr (assoc "AVISOS" r)))))
        )
      )
    )
  )
)


;;; ------------------------------------------------------------
;;; 7. RESUMO E FORMATACAO (linhas de texto; quem desenha e a view)
;;; ------------------------------------------------------------
;; linhas do resultado de um cenario (capacidade FORMATA: (fn en cenario))
(defun TUB:Formata (en cenario / dados sec n fr linhas av)
  (setq dados (OBJ:AtribDe en))
  (setq sec (TUB:_Secao (cdr (assoc "SECAO" dados))))
  (setq n (if sec (TUB:_N dados sec) nil))
  (setq fr (TUB:_V en cenario "FROUDE"))
  (setq linhas
    (list
      (strcat "Q = " (rtos (TUB:_V en cenario "VAZAO") 2 3) " m3/s   "
              (if sec (TUB:RotuloSecao sec) "Secao ?")
              (if n (strcat "   n = " (rtos n 2 4)) ""))
      (strcat "Altura da lamina: " (rtos (TUB:_V en cenario "ALTURA_LAMINA") 2 3) " m   "
              "enchimento " (rtos (* 100.0 (TUB:_V en cenario "RAZAO_ENCHIMENTO")) 2 1) " %")
      (strcat "Velocidade: " (rtos (TUB:_V en cenario "VELOCIDADE") 2 2) " m/s   "
              "Area molhada: " (rtos (TUB:_V en cenario "AREA_MOLHADA") 2 3) " m2"
              (if fr (strcat "   Fr = " (rtos fr 2 2)) ""))
      (strcat "Capacidade (seccao cheia): " (rtos (TUB:_V en cenario "CAPACIDADE") 2 3) " m3/s")
      (strcat "Percurso: " (rtos (TUB:_V en cenario "PERCURSO") 2 2) " min")
    )
  )
  (foreach av (TUB:_V en cenario "AVISOS")
    (setq linhas (append linhas (list (strcat "ATENCAO: " av))))
  )
  linhas
)

(defun TUB:Resumo (en / dados id sec linhas cr c)
  (setq dados (OBJ:AtribDe en))
  (setq id (cdr (assoc "SECAO" dados)))
  (setq sec (if id (TUB:_Secao id) nil))
  (setq cr (OBJ:CaractDe en))
  (setq linhas
    (list
      (strcat "Tubo/canal: " (OBJ:Nome en))
      (strcat "Handle: " (HYDRO:Handle en))
      (if sec
        (strcat (TUB:RotuloSecao sec) "   n efetivo = " (rtos (TUB:_N dados sec) 2 4))
        (strcat "Secao " (if id (itoa id) "?") " (nao cadastrada)"))
      (if (and (assoc "COMP" cr) (assoc "DECL" cr))
        (strcat "L = " (rtos (cdr (assoc "COMP" cr)) 2 1) " m   S = "
                (rtos (cdr (assoc "DECL" cr)) 2 4) " m/m"
                (if (member "DECL" (cdr (assoc "MANUAL" cr))) "  (manual)" ""))
        "Geometria indisponivel (use TUBOEDITA para digitar comprimento/declividade)")
      (strcat "Afluentes: " (itoa (length (LIG:Afluentes en))))
    )
  )
  (setq linhas (append linhas (OBJ:LinhasAtrib en)))
  (foreach c (OBJ:CenariosDe en)
    (if (TUB:_V en c "ALTURA_LAMINA")
      (setq linhas
        (append linhas
          (list
            (strcat "Cenario " c (if (OBJ:Obsoleto en c) " (DESATUALIZADO)" "")
                    ":  y = " (rtos (TUB:_V en c "ALTURA_LAMINA") 2 3)
                    " m   V = " (rtos (TUB:_V en c "VELOCIDADE") 2 2) " m/s")))
      )
    )
  )
  linhas
)

;; toString do tubo: texto multilinha. Capacidade "TOSTRING" do tipo.
(defun TUB:ToString (en)
  (HYDRO:Join (TUB:Resumo en) "\n")
)


;;; ------------------------------------------------------------
;;; 8. TIPO NO CATALOGO (declaracao e rotulos)
;;; ------------------------------------------------------------
(HYDRO:SetLabel "HYDRO.SECOES.TUBO" "Secoes de tubo/canal cadastradas" "")
(HYDRO:SetLabel "HYDRO.SECAO.TUBO.ATUAL" "Secao de tubo/canal atual (id)" "")

(if (HYDRO:Has "objetos")
  (OBJ:RegistrarTipo
    "tubo"
    "Tubo / canal"
    "Tubo, galeria ou canal (circular, retangular, trapezoidal); altura da lamina por Manning."
    '("LINE" "LWPOLYLINE" "POLYLINE")
    (TUB:_AtribDefs)
    T
    T
    (list
      (cons "CARACTERIZA" 'TUB:Caracterizar)
      (cons "CARACT-DEFS" (TUB:_CaractDefs))
      (cons "PADROES" 'TUB:_Padroes)
      (cons "RESUMO" 'TUB:Resumo)
      (cons "TOSTRING" 'TUB:ToString)
      (cons "CALCULA" 'TUB:Calcular)
      (cons "TEMPO-MODO" "percurso")
      (cons "FORMATA" 'TUB:Formata)
    )
  )
)


;;; ------------------------------------------------------------
;;; 9. COMANDOS E INTERACAO (linha de comando)
;;; ------------------------------------------------------------
;; Comandos padrao do objeto (docs/arquitetura.md secao 18b): fluxos genericos de
;; views/objetos_padrao_view.lsp; aqui so se diz de que tipo e. Calculo e ligacoes usam
;; CALCULAOBJETO e LIGAR. Comandos do catalogo de seccoes: views/secao_tubo_view.lsp.
(defun TUB:_Padrao (fn)
  (if (HYDRO:Has "objetos-padrao-view")
    (apply fn (list "tubo"))
    (alert "Comandos de objeto indisponiveis: carregue objetos_padrao e a view dele.")
  )
  (princ)
)

(defun c:TUBOCAD ()   (TUB:_Padrao 'OPV:Cadastrar))
(defun c:TUBOEDITA () (TUB:_Padrao 'OPV:EditaCampo))
(defun c:TUBOS ()     (TUB:_Padrao 'OPV:Listar))
(defun c:TUBOINFO ()  (TUB:_Padrao 'OPV:Info))
(defun c:TUBOZOOM ()  (TUB:_Padrao 'OPV:Zoom))

;;; ------------------------------------------------------------
;;; AUDITORIA (catalogo "auditoria"; ver plugins/auditoria.lsp)
;;; ------------------------------------------------------------
;; problemas: ("SECAO-INEXISTENTE" ename id) - tubo cuja seccao nao esta cadastrada
(defun TUB:_AudSecao (/ out en id)
  (foreach en (OBJ:ListaTipo "tubo")
    (setq id (cdr (assoc "SECAO" (OBJ:AtribDe en))))
    (if (and id (not (TUB:_Secao id)))
      (setq out (append out (list (list "SECAO-INEXISTENTE" en id))))
    )
  )
  out
)

(defun TUB:_TxtSecao (p)
  (strcat "Tubo " (OBJ:Nome (nth 1 p)) " usa a secao " (itoa (nth 2 p))
          ", que nao esta cadastrada")
)

;; Pergunta UMA seccao existente para todos os tubos com problema
(defun TUB:_ReparaSecao (problemas / secs idx id n p en)
  (setq secs (TUB:Secoes))
  (setq idx
    (HYDRO:Escolher
      (strcat "Secao a usar nos " (itoa (length problemas)) " tubo(s) com secao inexistente:")
      (mapcar 'TUB:RotuloSecao secs)
      0))
  (setq id (car (nth idx secs)))
  (setq n 0)
  (foreach p problemas
    (setq en (nth 1 p))
    (if (OBJ:CadastrarCom en "tubo" (OBJ:_SetChave (OBJ:AtribDe en) "SECAO" id)
          (OBJ:NomeGravado en) nil nil)
      (setq n (1+ n))
    )
  )
  (if (> n 0)
    (princ "\nRode CALCULAOBJETO nesses tubos: os resultados antigos usaram outra secao.")
  )
  n
)

(HYDRO:RegAdd "auditoria" "secao-tubo"
  (list (cons "NOME" "Secao dos tubos")
        (cons "VERIFICA" 'TUB:_AudSecao)
        (cons "TEXTO" 'TUB:_TxtSecao)
        (cons "REPARA" 'TUB:_ReparaSecao)))

(HYDRO:Provide "tubo-obj" "1.0")
(princ)
