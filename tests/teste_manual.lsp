;;; ============================================================
;;; tests/teste_manual.lsp - testes das funcoes puras do conjunto HYDRO
;;;
;;; Como usar (no AutoCAD/Civil 3D, com o Hydro ja carregado):
;;;   1. (load "C:/Dev/Hydro/tests/teste_manual.lsp")
;;;   2. comando  HYDROTESTE   (ou  (HT:Run) )
;;;
;;; Os testes gravam valores temporarios (chave TESTE.* e parametros IDF) e
;;; RESTAURAM os valores originais no fim. Valores esperados calculados fora
;;; do AutoCAD (Python).
;;; ============================================================
(vl-load-com)

;; Compara numeros com tolerancia
(defun HT:Near (a b tol)
  (and a b (< (abs (- a b)) tol))
)

;; Imprime e retorna T/nil
(defun HT:Check (nome ok)
  (princ (strcat "\n  [" (if ok "OK  " "FALHA") "] " nome))
  (if ok T nil)
)

;; conta quantas vezes o caractere ch aparece em str
(defun HT:Conta (str ch / n i)
  (setq n 0 i 1)
  (while (<= i (strlen str))
    (if (= (substr str i 1) ch) (setq n (1+ n)))
    (setq i (1+ i))
  )
  n
)

(defun HT:Section (titulo)
  (princ (strcat "\n" titulo))
)


;;; ------------------------------------------------------------
;;; Testes dos plugins metodos / bacia / hidrograma e utilitarios novos do core
;;; ------------------------------------------------------------
(defun HT:IdfSet (/ antigos n)
  (setq antigos
    (mapcar
      (function (lambda (n) (HYDRO:Get (strcat "HYDRO.IDF." n) nil)))
      '("K" "A" "B" "C" "S" "P")
    )
  )
  (HYDRO:Set "HYDRO.IDF.K" 1000.0) (HYDRO:Set "HYDRO.IDF.A" 0.15)
  (HYDRO:Set "HYDRO.IDF.B" 10.0)   (HYDRO:Set "HYDRO.IDF.C" 0.8)
  (HYDRO:Set "HYDRO.IDF.S" 0.0)    (HYDRO:Set "HYDRO.IDF.P" 0.0)
  antigos
)

(defun HT:IdfRestore (antigos / n)
  (foreach n '("K" "A" "B" "C" "S" "P")
    (if (car antigos)
      (HYDRO:Set (strcat "HYDRO.IDF." n) (car antigos))
      (HYDRO:Del (strcat "HYDRO.IDF." n))
    )
    (setq antigos (cdr antigos))
  )
)

;; grava linhas num arquivo temporario e devolve o caminho
(defun HT:TmpCsv (linhas / arq f l)
  (setq arq (vl-filename-mktemp "hydro" nil ".csv"))
  (setq f (open arq "w"))
  (foreach l linhas (write-line l f))
  (close f)
  arq
)

(defun HT:RunNovos (/ r antigos ctx res hid arq arq2 prm)
  (setq r nil)

  (HT:Section "core (registro e utilitarios)")
  (HYDRO:RegAdd "teste.categoria" "a" '(("N" . 1)))
  (HYDRO:RegAdd "teste.categoria" "b" '(("N" . 2)))
  (HYDRO:RegAdd "teste.categoria" "a" '(("N" . 3)))
  (setq r
    (append r
      (list
        (HT:Check "HYDRO:RegGet"
          (= (cdr (assoc "N" (HYDRO:RegGet "teste.categoria" "b"))) 2))
        (HT:Check "HYDRO:RegAdd substitui o mesmo id"
          (= (cdr (assoc "N" (HYDRO:RegGet "teste.categoria" "a"))) 3))
        (HT:Check "HYDRO:RegList tem 2 itens"
          (= (length (HYDRO:RegList "teste.categoria")) 2))
        (HT:Check "HYDRO:RegGet inexistente -> nil"
          (null (HYDRO:RegGet "teste.categoria" "zzz")))
        (HT:Check "HYDRO:ParseReal 0,045" (HT:Near (HYDRO:ParseReal "0,045") 0.045 1e-9))
        (HT:Check "HYDRO:ParseReal vazio -> nil" (null (HYDRO:ParseReal "  ")))
        (HT:Check "HYDRO:FmtReal 781.0 -> 781" (= (HYDRO:FmtReal 781.0) "781"))
        (HT:Check "HYDRO:FmtReal 0.045" (= (HYDRO:FmtReal 0.045) "0.045"))
        (HT:Check "HYDRO:FmtReal nil -> vazio" (= (HYDRO:FmtReal nil) ""))
        (HT:Check "HYDRO:CsvNum 0.045 -> 0,045" (= (HYDRO:CsvNum 0.045) "0,045"))
        (HT:Check "HYDRO:ImgTextoLargura 0.15 = 29" (= (HYDRO:ImgTextoLargura "0.15") 29))
      )
    )
  )

  (if (HYDRO:Has "idf")
    (progn
      (HT:Section "idf (duracao)")
      (setq antigos (HT:IdfSet))
      (setq r
        (append r
          (list
            (HT:Check "PREC:Intensidade duracao+b = 0 -> nil"
              (null (PREC:Intensidade -10.0 10.0)))
            (HT:Check "PREC:Intensidade (dur=20, TR=10) = 92.9615"
              (HT:Near (PREC:Intensidade 20.0 10.0) 92.96147 0.001))
          )
        )
      )
      (HT:IdfRestore antigos)
    )
  )

  (if (and (HYDRO:Has "precipitacao") (HYDRO:Has "hietograma-tipos"))
    (progn
      (HT:Section "precipitacao (hietogramas)")
      (setq antigos (HT:IdfSet))
      ;; IDF do teste: K=1000 a=0.15 b=10 c=0.8 s=0 p=0; TR=10; D=60; DT=10
      (setq r
        (append r
          (list
            (HT:Check "HIET:Profundidade (60 min, TR 10) = 47.1978 mm"
              (HT:Near (HIET:Profundidade 60.0 10.0) 47.19778 1e-4))
            (HT:Check "HIET:Profundidade duracao 0 -> 0" (= (HIET:Profundidade 0.0 10.0) 0.0))
            (HT:Check "HIET:_Alterna (1 5 3 2 4), pico no centro -> (1 3 5 4 2)"
              (equal (HIET:_Alterna '(1 5 3 2 4) 0.5) '(1 3 5 4 2)))
            (HT:Check "HIET:_Alterna preserva valores repetidos"
              (equal (HIET:_Alterna '(2 2 1) 0.5) '(1 2 2)))
            (HT:Check "HIET:_Passo ajusta DT para dividir a duracao (60, 25 -> 2 x 30)"
              (and (= (car (HIET:_Passo 60.0 '(("DT" . 25.0)))) 2)
                   (HT:Near (cadr (HIET:_Passo 60.0 '(("DT" . 25.0)))) 30.0 1e-9)))
            (HT:Check "HIET:_Passo sem DT -> um bloco"
              (and (= (car (HIET:_Passo 60.0 nil)) 1)
                   (HT:Near (cadr (HIET:_Passo 60.0 nil)) 60.0 1e-9)))
            (HT:Check "HIET:Gerar tipo inexistente -> ERRO"
              (assoc "ERRO" (HIET:Gerar "nao-existe" 10.0 60.0 nil)))
            (HT:Check "HIET:Gerar duracao <= 0 -> ERRO"
              (assoc "ERRO" (HIET:Gerar "bloco-unico" 10.0 0.0 nil)))
            (HT:Check "HIET:Gerar chicago com R = 1 -> ERRO"
              (assoc "ERRO" (HIET:Gerar "chicago" 10.0 60.0 '(("DT" . 10.0) ("R" . 1.0)))))
            (HT:Check "HIET:Gerar bloco-alternado com R fora de 0..1 -> ERRO"
              (assoc "ERRO" (HIET:Gerar "bloco-alternado" 10.0 60.0 '(("DT" . 10.0) ("R" . 1.5)))))
          )
        )
      )
      (setq res (HIET:Gerar "bloco-unico" 10.0 60.0 nil))
      (setq r
        (append r
          (list
            (HT:Check "bloco-unico: 1 bloco com a chuva total da IDF"
              (and (= (length (cdr (assoc "BLOCOS" res))) 1)
                   (HT:Near (cdr (assoc "TOTAL" res)) 47.19778 1e-4)
                   (HT:Near (nth 3 (car (cdr (assoc "BLOCOS" res)))) 47.19778 1e-4))))
        )
      )
      (setq res (HIET:Gerar "bloco-alternado" 10.0 60.0 '(("DT" . 10.0) ("R" . 0.5))))
      (setq r
        (append r
          (list
            (HT:Check "bloco-alternado: 6 blocos e total = IDF"
              (and (= (length (cdr (assoc "BLOCOS" res))) 6)
                   (HT:Near (cdr (assoc "TOTAL" res)) 47.19778 1e-4)))
            (HT:Check "bloco-alternado: ordem 2.704 3.309 5.938 21.430 9.557 4.259"
              (vl-every
                (function (lambda (a b) (HT:Near a b 1e-4)))
                (mapcar 'caddr (cdr (assoc "BLOCOS" res)))
                '(2.70416 3.30922 5.93797 21.43013 9.55703 4.25927)))
            (HT:Check "bloco-alternado: intensidade do bloco = mm / (dt/60)"
              (HT:Near (nth 3 (nth 3 (cdr (assoc "BLOCOS" res)))) 128.58076 1e-3))
          )
        )
      )
      (setq res (HIET:Gerar "chicago" 10.0 60.0 '(("DT" . 10.0) ("R" . 0.4))))
      (setq r
        (append r
          (list
            (HT:Check "chicago: 6 blocos e total = IDF (preserva o volume)"
              (and (= (length (cdr (assoc "BLOCOS" res))) 6)
                   (HT:Near (cdr (assoc "TOTAL" res)) 47.19778 1e-4)))
            (HT:Check "chicago (r=0.4): 3.197 7.110 21.430 8.255 4.310 2.896"
              (vl-every
                (function (lambda (a b) (HT:Near a b 1e-4)))
                (mapcar 'caddr (cdr (assoc "BLOCOS" res)))
                '(3.19692 7.11014 21.43013 8.25500 4.30970 2.89588)))
          )
        )
      )
      (HT:IdfRestore antigos)
    )
  )

  (if (HYDRO:Has "metodos-chuva-vazao")
    (progn
      (HT:Section "metodos-chuva-vazao")
      (setq antigos (HT:IdfSet))
      (setq res
        (MET:Racional '(("AREA" . 10000.0) ("TC" . 20.0) ("TR" . 10.0)) '(("C" . 0.8))))
      (setq r
        (append r
          (list
            (HT:Check "catalogo: racional, scs-cn, vazao-informada cadastrados"
              (and (HYDRO:RegGet "metodo-chuva-vazao" "racional")
                   (HYDRO:RegGet "metodo-chuva-vazao" "scs-cn")
                   (HYDRO:RegGet "metodo-chuva-vazao" "vazao-informada")))
            (HT:Check "MET:Racional Qp = 0.206581 m3/s"
              (HT:Near (cdr (assoc "QP" res)) 0.206581 0.00001))
            (HT:Check "MET:Racional Pe = 24.7897 mm"
              (HT:Near (cdr (assoc "PE" res)) 24.78973 0.0001))
            (HT:Check "MET:Racional volume = 247.897 m3"
              (HT:Near (cdr (assoc "VOLUME" res)) 247.8973 0.001))
            (HT:Check "MET:Racional C invalido -> ERRO"
              (assoc "ERRO" (MET:Racional '(("AREA" . 1.0) ("TC" . 20.0) ("TR" . 10.0)) '(("C" . 1.5)))))
          )
        )
      )
      (setq res
        (MET:ScsCn
          '(("AREA" . 1000000.0) ("TC" . 30.0) ("TR" . 10.0) ("DUR" . 30.0))
          '(("CN" . 80.0) ("LAMBDA" . 0.2))))
      (setq r
        (append r
          (list
            (HT:Check "MET:ScsCn Pe = 6.68972 mm" (HT:Near (cdr (assoc "PE" res)) 6.68972 0.0001))
            (HT:Check "MET:ScsCn tp = 33 min" (HT:Near (cdr (assoc "TP" res)) 33.0 1e-9))
            (HT:Check "MET:ScsCn Qp = 2.52993 m3/s" (HT:Near (cdr (assoc "QP" res)) 2.52993 0.0001))
            (HT:Check "MET:ScsCn CN invalido -> ERRO"
              (assoc "ERRO" (MET:ScsCn '(("AREA" . 1.0) ("TC" . 30.0) ("TR" . 10.0) ("DUR" . 30.0))
                                       '(("CN" . 0.0) ("LAMBDA" . 0.2)))))
            (HT:Check "MET:VazaoInformada"
              (HT:Near (cdr (assoc "QP" (MET:VazaoInformada '(("TC" . 15.0)) '(("QP" . 1.5))))) 1.5 1e-9))
          )
        )
      )
      (HT:IdfRestore antigos)
    )
  )

  (if (HYDRO:Has "bacia")
    (progn
      (HT:Section "bacia")
      (setq r
        (append r
          (list
            (HT:Check "BAC:TcKirpich (L=500, S=0.02) = 10.5484"
              (HT:Near (BAC:TcKirpich 500.0 0.02) 10.54837 0.001))
            (HT:Check "BAC:TcKirpich declividade 0 -> nil" (null (BAC:TcKirpich 500.0 0.0)))
            (HT:Check "BAC:_AddVazao substitui mesmo metodo e TR"
              (= (length
                   (BAC:_AddVazao
                     '((("METODO" . "racional") ("TR" . 10.0) ("QP" . 1.0))
                       (("METODO" . "racional") ("TR" . 25.0)))
                     '(("METODO" . "racional") ("TR" . 10.0) ("QP" . 2.0))))
                 2))
            (HT:Check "BAC:_SetChave troca valor existente"
              (equal (BAC:_Val "X" (BAC:_SetChave '(("X" . 1) ("Y" . 2)) "X" 9)) 9))
            (HT:Check "BAC:ExecutarMetodo metodo inexistente -> ERRO"
              (assoc "ERRO" (BAC:ExecutarMetodo "nao-existe" nil nil)))
          )
        )
      )
      (if (HYDRO:Has "metodos-chuva-vazao")
        (progn
          (setq antigos (HT:IdfSet))
          (setq res
            (BAC:ExecutarMetodo "racional"
              '(("AREA" . 10000.0) ("TC" . 20.0) ("TR" . 10.0)) '(("C" . 0.8))))
          (setq r
            (append r
              (list
                (HT:Check "BAC:ExecutarMetodo racional -> Qp 0.206581"
                  (HT:Near (cdr (assoc "QP" res)) 0.206581 0.00001))
              )
            )
          )
          (HT:IdfRestore antigos)
        )
      )
    )
  )

  (if (HYDRO:Has "hidrograma")
    (progn
      (HT:Section "hidrograma")
      (setq ctx
        '(("AREA" . 1000000.0) ("TC" . 30.0) ("TR" . 10.0) ("DUR" . 30.0)
          ("METODO" . "scs-cn") ("PE" . 6.689723) ("VOLUME" . 6689.723)))
      (setq r
        (append r
          (list
            (HT:Check "HID:_NiceMax 60 -> 60" (HT:Near (HID:_NiceMax 60.0) 60.0 1e-9))
            (HT:Check "HID:_NiceMax 0.3 -> 0.3" (HT:Near (HID:_NiceMax 0.3) 0.3 1e-9))
            (HT:Check "HID:_NiceMax 2.4 -> 2.5" (HT:Near (HID:_NiceMax 2.4) 2.5 1e-9))
            (HT:Check "HID:_NiceMax 0 -> 1" (HT:Near (HID:_NiceMax 0.0) 1.0 1e-9))
            (HT:Check "HID:_DtAuto 88.11 -> 5" (HT:Near (HID:_DtAuto 88.11) 5.0 1e-9))
            (HT:Check "HID:_DtAuto 20 -> 0.5" (HT:Near (HID:_DtAuto 20.0) 0.5 1e-9))
            (HT:Check "HID:_Interp no meio da subida"
              (HT:Near (HID:_Interp '((0.0 . 0.0) (10.0 . 10.0) (20.0 . 0.0)) 5.0) 5.0 1e-9))
            (HT:Check "HID:_Interp na descida"
              (HT:Near (HID:_Interp '((0.0 . 0.0) (10.0 . 10.0) (20.0 . 0.0)) 15.0) 5.0 1e-9))
            (HT:Check "HID:_Interp depois do fim = ultimo valor"
              (HT:Near (HID:_Interp '((0.0 . 0.0) (10.0 . 10.0) (20.0 . 0.0)) 25.0) 0.0 1e-9))
            (HT:Check "HID:_Volume triangulo = 1800 m3"
              (HT:Near (HID:_Volume '((0.0 . 0.0) (10.0 . 2.0) (30.0 . 0.0))) 1800.0 1e-6))
            (HT:Check "HID:_AreaAdim da tabela SCS = 1.31265"
              (HT:Near (HID:_AreaAdim (HID:_TabelaScs)) 1.31265 0.0001))
            (HT:Check "HID:_Amostra mantem o pico e o volume"
              (and (= (length (HID:_Amostra '((0.0 . 0.0) (12.0 . 3.0) (36.0 . 0.0)) 5.0 '(12.0))) 10)
                   (HT:Near (HID:_Volume (HID:_Amostra '((0.0 . 0.0) (12.0 . 3.0) (36.0 . 0.0)) 5.0 '(12.0)))
                            3240.0 1e-6)))
            (HT:Check "HID:_ParseLinha 0;0,5"
              (equal (HID:_ParseLinha "0;0,5") '(0.0 . 0.5)))
            (HT:Check "HID:_ParseLinha 1,5;2"
              (equal (HID:_ParseLinha "1,5;2") '(1.5 . 2.0)))
            (HT:Check "HID:_ParseLinha espacos"
              (equal (HID:_ParseLinha "10   0.25") '(10.0 . 0.25)))
            (HT:Check "HID:_ParseLinha virgula como separador"
              (equal (HID:_ParseLinha "5,0.5") '(5.0 . 0.5)))
            (HT:Check "HID:_ParseLinha cabecalho -> nil" (null (HID:_ParseLinha "t;q")))
            (HT:Check "HID:_ParseLinha comentario -> nil" (null (HID:_ParseLinha "# teste")))
            (HT:Check "tipos cadastrados"
              (and (HYDRO:RegGet "hidrograma-tipo" "triangular-scs")
                   (HYDRO:RegGet "hidrograma-tipo" "adimensional-scs")
                   (HYDRO:RegGet "hidrograma-tipo" "racional-trapezoidal")
                   (HYDRO:RegGet "hidrograma-tipo" "triangular-usuario")
                   (HYDRO:RegGet "hidrograma-tipo" "tabela-usuario")))
          )
        )
      )

      ;; triangular SCS: Qp = 2V/tb, volume conservado
      (setq hid (HID:Gerar "triangular-scs" ctx '(("TBTP" . 2.67) ("DT" . 0.0))))
      (setq r
        (append r
          (list
            (HT:Check "HID triangular-scs: Qp = 2.53082"
              (HT:Near (cdr (assoc "QP" hid)) 2.53082 0.0005))
            (HT:Check "HID triangular-scs: tp = 33 e tb = 88.11"
              (and (HT:Near (cdr (assoc "TP" hid)) 33.0 1e-6)
                   (HT:Near (cdr (assoc "TB" hid)) 88.11 1e-6)))
            (HT:Check "HID triangular-scs: volume conservado"
              (HT:Near (cdr (assoc "VOLUME" hid)) 6689.723 1.0))
          )
        )
      )

      ;; adimensional SCS: volume conservado (tolerancia da reamostragem)
      (setq hid (HID:Gerar "adimensional-scs" ctx '(("DT" . 0.0))))
      (setq r
        (append r
          (list
            (HT:Check "HID adimensional-scs: Qp = 2.57391"
              (HT:Near (cdr (assoc "QP" hid)) 2.57391 0.001))
            (HT:Check "HID adimensional-scs: volume ~ 6689.7 (1%)"
              (HT:Near (cdr (assoc "VOLUME" hid)) 6689.723 67.0))
          )
        )
      )

      ;; trapezoidal racional: V = Qp * D * 60
      (setq hid
        (HID:Gerar "racional-trapezoidal"
          '(("AREA" . 10000.0) ("TC" . 20.0) ("TR" . 10.0) ("DUR" . 30.0)
            ("METODO" . "racional") ("QP" . 0.2))
          '(("DT" . 0.0))))
      (setq r
        (append r
          (list
            (HT:Check "HID racional-trapezoidal: Qp = 0.2 e tb = 50"
              (and (HT:Near (cdr (assoc "QP" hid)) 0.2 1e-9)
                   (HT:Near (cdr (assoc "TB" hid)) 50.0 1e-6)))
            (HT:Check "HID racional-trapezoidal: volume = 360 m3"
              (HT:Near (cdr (assoc "VOLUME" hid)) 360.0 1e-6))
          )
        )
      )

      ;; triangular do usuario
      (setq hid
        (HID:Gerar "triangular-usuario"
          '(("METODO" . "vazao-informada") ("TR" . 10.0) ("DUR" . 20.0))
          '(("QP" . 2.0) ("TP" . 10.0) ("TBTP" . 3.0) ("DT" . 0.0))))
      (setq r
        (append r
          (list
            (HT:Check "HID triangular-usuario: Qp 2, tp 10, tb 30"
              (and (HT:Near (cdr (assoc "QP" hid)) 2.0 1e-9)
                   (HT:Near (cdr (assoc "TP" hid)) 10.0 1e-9)
                   (HT:Near (cdr (assoc "TB" hid)) 30.0 1e-9)))
            (HT:Check "HID triangular-usuario: volume = 1800 m3"
              (HT:Near (cdr (assoc "VOLUME" hid)) 1800.0 1e-6))
          )
        )
      )

      ;; erros esperados
      (setq r
        (append r
          (list
            (HT:Check "HID triangular-scs sem PE/volume -> ERRO"
              (assoc "ERRO"
                (HID:Gerar "triangular-scs"
                  '(("AREA" . 1.0e6) ("TC" . 30.0) ("TR" . 10.0) ("DUR" . 30.0) ("METODO" . "racional"))
                  '(("TBTP" . 2.67)))))
            (HT:Check "HID triangular-scs sem DUR no calculo -> ERRO"
              (assoc "ERRO"
                (HID:Gerar "triangular-scs"
                  '(("AREA" . 1.0e6) ("TC" . 30.0) ("TR" . 10.0) ("VOLUME" . 100.0))
                  '(("TBTP" . 2.67)))))
            (HT:Check "HID tipo inexistente -> ERRO"
              (assoc "ERRO" (HID:Gerar "nao-existe" ctx nil)))
          )
        )
      )

      ;; tabela do usuario (arquivo CSV temporario)
      (setq arq  (HT:TmpCsv '("t;q" "0;0" "10;2,5" "20;0")))
      (setq arq2 (HT:TmpCsv '("0;0" "1;1" "3;0")))
      (setq r
        (append r
          (list
            (HT:Check "HID:_LerTabela le 3 pontos (cabecalho ignorado)"
              (= (length (HID:_LerTabela arq)) 3))
          )
        )
      )
      (setq hid
        (HID:Gerar "tabela-usuario" '(("METODO" . "vazao-informada") ("TR" . 10.0) ("DUR" . 20.0))
          (list (cons "ARQ" arq) (cons "MODO" "absoluto") (cons "DT" 0.0))))
      (setq r
        (append r
          (list
            (HT:Check "HID tabela-usuario absoluta: pico 2.5 em t = 10"
              (and (HT:Near (cdr (assoc "QP" hid)) 2.5 1e-9)
                   (HT:Near (cdr (assoc "TP" hid)) 10.0 1e-9)))
          )
        )
      )
      (setq hid
        (HID:Gerar "tabela-usuario" '(("METODO" . "vazao-informada") ("TR" . 10.0) ("DUR" . 20.0))
          (list (cons "ARQ" arq2) (cons "MODO" "adimensional")
                (cons "TPU" 20.0) (cons "QPU" 5.0) (cons "DT" 0.0))))
      (setq r
        (append r
          (list
            (HT:Check "HID tabela-usuario adimensional: Qp 5 em tp 20, tb 60"
              (and (HT:Near (cdr (assoc "QP" hid)) 5.0 1e-9)
                   (HT:Near (cdr (assoc "TP" hid)) 20.0 1e-9)
                   (HT:Near (cdr (assoc "TB" hid)) 60.0 1e-9)))
            (HT:Check "HID tabela-usuario sem arquivo -> ERRO"
              (assoc "ERRO"
                (HID:Gerar "tabela-usuario" nil
                  '(("ARQ" . "nao-existe.csv") ("MODO" . "absoluto") ("DT" . 0.0)))))
          )
        )
      )
      (vl-file-delete arq)
      (vl-file-delete arq2)
    )
  )
  r
)


;;; ------------------------------------------------------------
;;; Testes: metodos de tc, cadastro comum de bacias, textos e tabela
;;; ------------------------------------------------------------
(defun HT:RunBacias (/ r ctx dados calc linhas reg)
  (setq r nil)
  (setq ctx '(("AREA" . 1000000.0) ("COMP" . 2000.0) ("DESNIVEL" . 20.0) ("DECL" . 0.01)))

  (if (HYDRO:Has "tempo-conc")
    (progn
      (HT:Section "tempo_conc")
      (setq r
        (append r
          (list
            (HT:Check "TCM: ao menos os 8 metodos incluidos"
              (>= (length (HYDRO:RegList "metodo-tc")) 8))
            (HT:Check "TCM:Kirpich = 40.0560 min"
              (HT:Near (cdr (assoc "TC" (TCM:Calcular "kirpich" ctx nil))) 40.05603 0.0001))
            (HT:Check "TCM:Ventura = 76.2 min"
              (HT:Near (cdr (assoc "TC" (TCM:Calcular "ventura" ctx nil))) 76.2 0.0001))
            (HT:Check "TCM:Pasini = 80.8869 min"
              (HT:Near (cdr (assoc "TC" (TCM:Calcular "pasini" ctx nil))) 80.88693 0.0001))
            (HT:Check "TCM:Corps = 46.5551 min"
              (HT:Near (cdr (assoc "TC" (TCM:Calcular "corps-engineers" ctx nil))) 46.55512 0.0001))
            (HT:Check "TCM:Giandotti (Hm=20) = 117.3936 min"
              (HT:Near (cdr (assoc "TC" (TCM:Calcular "giandotti" ctx '(("HM" . 20.0))))) 117.39357 0.0001))
            (HT:Check "TCM:George Ribeiro (p=0.2) = 31.6832 min"
              (HT:Near (cdr (assoc "TC" (TCM:Calcular "george-ribeiro" ctx '(("P" . 0.2))))) 31.68317 0.0001))
            (HT:Check "TCM:Velocidade (1 m/s) = 33.3333 min"
              (HT:Near (cdr (assoc "TC" (TCM:Calcular "velocidade" ctx '(("V" . 1.0))))) 33.33333 0.0001))
            (HT:Check "TCM:Informado = 25"
              (HT:Near (cdr (assoc "TC" (TCM:Calcular "informado" ctx '(("TC" . 25.0))))) 25.0 1e-9))
            (HT:Check "TCM: declividade nula -> ERRO"
              (assoc "ERRO" (TCM:Calcular "ventura" '(("AREA" . 1.0e6) ("COMP" . 2000.0) ("DECL" . 0.0)) nil)))
            (HT:Check "TCM: Giandotti sem Hm valido -> ERRO"
              (assoc "ERRO" (TCM:Calcular "giandotti" ctx '(("HM" . 0.0)))))
            (HT:Check "TCM: George Ribeiro p fora de 0-1 -> ERRO"
              (assoc "ERRO" (TCM:Calcular "george-ribeiro" ctx '(("P" . 1.5)))))
            (HT:Check "TCM: metodo inexistente -> ERRO"
              (assoc "ERRO" (TCM:Calcular "nao-existe" ctx nil)))
            (HT:Check "TCM:Kirpich = BAC:TcKirpich (mesma formula)"
              (HT:Near (cdr (assoc "TC" (TCM:Calcular "kirpich" ctx nil)))
                       (BAC:TcKirpich 2000.0 0.01) 0.0001))
          )
        )
      )
    )
  )

  (if (HYDRO:Has "bacia")
    (progn
      (HT:Section "bacia (registro padrao)")
      (setq dados
        '(("VERSAO" . 2) ("TIPO" . "bacia") ("NOME" . "B1")
          ("PARAMS" . (("TALVEGUE" . "2F")))
          ("ATRIB" . (("C" . 0.6)))
          ("CARACT" . (("AREA" . 100.0)))
          ("RESULT" . (("TC" . (("MIN" . 12.0) ("ORIGEM" . "kirpich")))
                       ("VAZAO" . ((("METODO" . "racional"))))))))
      (setq r
        (append r
          (list
            (HT:Check "BAC: registro padrao tem TIPO bacia e VERSAO 2"
              (and (equal (BAC:_Val "TIPO" dados) "bacia")
                   (equal (BAC:_Val "VERSAO" dados) 2)))
            (HT:Check "BAC:Talvegue vem de PARAMS" (equal (BAC:Talvegue dados) "2F"))
            (HT:Check "BAC:Atrib / BAC:Caract"
              (and (equal (BAC:Atrib dados) '(("C" . 0.6)))
                   (equal (BAC:Caract dados) '(("AREA" . 100.0)))))
            (HT:Check "BAC:Tc vem de RESULT"
              (and (HT:Near (BAC:_Val "MIN" (BAC:Tc dados)) 12.0 1e-9)
                   (equal (BAC:_Val "ORIGEM" (BAC:Tc dados)) "kirpich")))
            (HT:Check "BAC:Vazao vem de RESULT"
              (equal (BAC:Vazao dados) '((("METODO" . "racional")))))
            (HT:Check "BAC:Hidrogramas sem hidrograma -> nil" (null (BAC:Hidrogramas dados)))
            (HT:Check "BAC:_SetResult acrescenta sem perder o resto de RESULT"
              (and (equal (BAC:Hidrogramas (BAC:_SetResult dados "HIDROGRAMAS" '((("TIPO" . "x")))))
                          '((("TIPO" . "x"))))
                   (equal (BAC:Vazao (BAC:_SetResult dados "HIDROGRAMAS" '((("TIPO" . "x")))))
                          '((("METODO" . "racional"))))
                   (equal (BAC:Atrib (BAC:_SetResult dados "HIDROGRAMAS" '((("TIPO" . "x")))))
                          '(("C" . 0.6)))))
            (HT:Check "BAC:_SetResult com nil remove so aquele item"
              (and (null (BAC:Vazao (BAC:_SetResult dados "VAZAO" nil)))
                   (BAC:Tc (BAC:_SetResult dados "VAZAO" nil))))
          )
        )
      )
    )
  )

  (if (HYDRO:Has "bacia")
    (progn
      (HT:Section "bacia (cadastro comum)")
      (setq dados
        '(("VERSAO" . 2) ("TIPO" . "bacia") ("NOME" . "B1")
          ("PARAMS" . (("TALVEGUE" . "2F")))
          ("ATRIB" . (("C" . 0.6) ("CN" . 80.0)))
          ("CARACT" . (("AREA" . 120000.0) ("COMP" . 850.0) ("DESNIVEL" . 10.2)
                       ("DECL" . 0.012)))
          ("RESULT" . (("TC" . (("MIN" . 14.2) ("ORIGEM" . "kirpich")))
                       ("VAZAO" . ((("METODO" . "racional") ("TR" . 10.0) ("DUR" . 14.2) ("TC" . 14.2)
                                    ("QP" . 3.123) ("I" . 150.2) ("P" . 35.5) ("PE" . 21.3) ("VOLUME" . 2556.0))))))))
      (setq calc (car (BAC:Vazao dados)))
      (setq r
        (append r
          (list
            (HT:Check "BAC:_Limpa remove pares nil"
              (equal (BAC:_Limpa '(("A" . 1) ("B") ("C" . "x"))) '(("A" . 1) ("C" . "x"))))
            (HT:Check "BAC:_Prox tolera 1e-9 relativo" (BAC:_Prox 1000.0 1000.000001))
            (HT:Check "BAC:_Prox diferente -> nil" (null (BAC:_Prox 1000.0 1001.0)))
            (HT:Check "BAC:_GeomIgual"
              (BAC:_GeomIgual '(("AREA" . 10.0) ("COMP" . 5.0) ("DESNIVEL" . 1.0))
                              '(("AREA" . 10.0) ("COMP" . 5.0) ("DESNIVEL" . 1.0))))
            (HT:Check "BAC:_GeomIgual com desnivel diferente -> nil"
              (null (BAC:_GeomIgual '(("AREA" . 10.0) ("COMP" . 5.0) ("DESNIVEL" . 1.0))
                                    '(("AREA" . 10.0) ("COMP" . 5.0) ("DESNIVEL" . 2.0)))))
            (HT:Check "BAC:_Ctx traz caracteristicas, tc, NOME e atributos"
              (and (equal (cdr (assoc "NOME" (BAC:_Ctx dados))) "B1")
                   (equal (cdr (assoc "CN" (BAC:_Ctx dados))) 80.0)
                   (equal (cdr (assoc "AREA" (BAC:_Ctx dados))) 120000.0)
                   (HT:Near (cdr (assoc "TC" (BAC:_Ctx dados))) 14.2 1e-9)
                   (equal (cdr (assoc "TC-ORIGEM" (BAC:_Ctx dados))) "kirpich")))
            (HT:Check "BAC:_Sobrescritas: CN do cadastro preenche o parametro CN"
              (equal (BAC:_Sobrescritas '(("C" . 0.6) ("CN" . 80.0))
                                        '(("CN" "CN" 75.0 "") ("LAMBDA" "L" 0.2 "")))
                     '(("CN" . 80.0))))
            (HT:Check "BAC:_SetChave com nil remove o item"
              (null (assoc "X" (BAC:_SetChave '(("X" . 1) ("Y" . 2)) "X" nil))))
            (HT:Check "BAC:Contexto: TC do calculo vem antes do TC da bacia"
              (HT:Near (cdr (assoc "TC" (BAC:Contexto
                          '(("CARACT" . (("AREA" . 1.0)))
                            ("RESULT" . (("TC" . (("MIN" . 99.0))))))
                          '(("METODO" . "racional") ("TR" . 10.0) ("DUR" . 12.0) ("TC" . 12.0)
                            ("QP" . 1.0))))
                       ) 12.0 1e-9))
            (HT:Check "BAC:_NomeExib sem nome -> B-handle"
              (= (BAC:_NomeExib '(("CARACT")) "2F3") "B-2F3"))
            (HT:Check "BAC:_NomeTc usuario -> informado" (= (BAC:_NomeTc "usuario") "informado"))
            (HT:Check "BAC:_NomeTc nil -> -" (= (BAC:_NomeTc nil) "-"))
          )
        )
      )
      (setq linhas (BAC:LinhasCadastro dados "2F"))
      (setq r
        (append r
          (list
            (HT:Check "BAC:LinhasCadastro: titulo com o nome" (= (car linhas) "BACIA B1"))
            (HT:Check "BAC:LinhasCadastro: area em ha" (= (cadr linhas) "Area: 12.000 ha"))
            (HT:Check "BAC:LinhasCadastro: inclui C e CN"
              (vl-some (function (lambda (x) (and (vl-string-search "C = 0.6" x) (vl-string-search "CN = 80" x)))) linhas))
            (HT:Check "BAC:LinhasVazao: cabecalho e Qp"
              (and (vl-string-search "TR 10 anos]" (car (BAC:LinhasVazao calc)))
                   (member "Qp = 3.123 m3/s" (BAC:LinhasVazao calc))
                   (member "Volume = 2556 m3" (BAC:LinhasVazao calc))))
            (HT:Check "BAC:LinhasTexto = cadastro + calculo"
              (= (length (BAC:LinhasTexto dados "2F" (list calc)))
                 (+ (length linhas) (length (BAC:LinhasVazao calc)))))
          )
        )
      )
    )
  )

  (if (HYDRO:Has "bacia-tabela")
    (progn
      (HT:Section "bacia_tabela")
      (setq reg
        (BTB:_Registro nil
          '(("NOME" . "Bacia Norte")
            ("CARACT" . (("AREA" . 120000.0) ("COMP" . 850.0) ("DESNIVEL" . 10.2)
                         ("DECL" . 0.012)))
            ("RESULT" . (("TC" . (("MIN" . 14.2) ("ORIGEM" . "usuario")))
                         ("VAZAO" . ((("METODO" . "racional") ("TR" . 10.0) ("DUR" . 14.2) ("TC" . 14.2)
                                      ("QP" . 3.123))
                                     (("METODO" . "racional") ("TR" . 25.0) ("DUR" . 14.2) ("TC" . 14.2)
                                      ("QP" . 4.5)))))))
          "2F"))
      (setq r
        (append r
          (list
            (HT:Check "BTB:_Trunc" (= (BTB:_Trunc "Bacia Norte do Rio" 12) "Bacia Nort.."))
            (HT:Check "BTB:_Num nil -> -" (= (BTB:_Num nil 2) "-"))
            (HT:Check "BTB:_Registro: linha tem 10 colunas (9 tabs)"
              (= (HT:Conta (cdr (assoc "LINHA" reg)) "\t") 9))
            (HT:Check "BTB:_Registro: Qp max = maior dos calculos"
              (HT:Near (BAC:_MaxQp
                         '(("RESULT" . (("VAZAO" . ((("QP" . 3.123)) (("QP" . 4.5))))))))
                       4.5 1e-9))
            (HT:Check "BTB:_Registro: CSV de calculos tem 2 linhas"
              (= (length (cdr (assoc "CSV-CALC" reg))) 2))
            (HT:Check "BTB:_Registro: metodo tc 'informado'"
              (equal (cdr (assoc "Metodo tc" (cdr (assoc "CSV" reg)))) "informado"))
            (HT:Check "BTB:_Filtra acha por parte do nome"
              (= (length (BTB:_Filtra (list reg) "norte")) 1))
            (HT:Check "BTB:_Filtra sem correspondencia"
              (= (length (BTB:_Filtra (list reg) "zzz")) 0))
            (HT:Check "BTB:_Celula real -> virgula decimal" (= (BTB:_Celula 0.045) "0,045"))
            (HT:Check "BTB:_Celula texto com ; -> aspas" (= (BTB:_Celula "a;b") "\"a;b\""))
          )
        )
      )
    )
  )
  r
)


;;; ------------------------------------------------------------
;;; Testes: objetos hidraulicos, ligacoes (grafo puro), tipos e tabela
;;; ------------------------------------------------------------
(defun HT:RunObjetos (/ r mapa existe prob ids comp)
  (setq r nil)

  (if (HYDRO:Has "objetos")
    (progn
      (HT:Section "objetos")
      (OBJ:RegistrarTipo "teste-tipo" "Tipo de teste" "so para testes"
        '("LWPOLYLINE") (list (list "X" "Parametro X" 1.0 "m")) T nil
        (list (cons "CADASTRAVEL" T)))
      (setq r
        (append r
          (list
            (HT:Check "HYDRO:EntValida nil -> nil" (null (HYDRO:EntValida nil)))
            (HT:Check "HYDRO:EntValida string -> nil" (null (HYDRO:EntValida "x")))
            (HT:Check "OBJ: tipo de teste cadastrado e com capacidades"
              (and (OBJ:TipoDados "teste-tipo")
                   (OBJ:Cap "teste-tipo" "RECEBE")
                   (null (OBJ:Cap "teste-tipo" "EMITE"))))
            (HT:Check "OBJ:TiposPara acha o tipo de teste em LWPOLYLINE"
              (assoc "teste-tipo" (OBJ:TiposPara "LWPOLYLINE")))
            (HT:Check "OBJ:TiposPara nao acha em CIRCLE"
              (null (assoc "teste-tipo" (OBJ:TiposPara "CIRCLE"))))
            (HT:Check "OBJ:_Cadastravel: ausente -> T" (OBJ:_Cadastravel '(("X" . 1))))
            (HT:Check "OBJ:_Cadastravel: presente e nil -> nil" (null (OBJ:_Cadastravel '(("CADASTRAVEL")))))
            (HT:Check "OBJ:OpsFaltando: sem ARMAZENAMENTO usa o padrao"
              (null (OBJ:OpsFaltando '(("CADASTRAVEL" . T)))))
            (HT:Check "OBJ:OpsFaltando: ARMAZENAMENTO vazio -> as 5 operacoes"
              (= (length (OBJ:OpsFaltando '(("ARMAZENAMENTO")))) 5))
            (HT:Check "OBJ:OpsFaltando: lista so as que faltam"
              (equal (OBJ:OpsFaltando
                       '(("ARMAZENAMENTO" . (("LER" . A) ("GRAVAR" . B) ("LISTAR" . C)))))
                     '("REINDEXAR" "REMOVER")))
            (HT:Check "OBJ:OpsFaltando: completo -> nada falta"
              (null (OBJ:OpsFaltando
                      '(("ARMAZENAMENTO" . (("LER" . A) ("GRAVAR" . B) ("LISTAR" . C)
                                            ("REINDEXAR" . D) ("REMOVER" . E)))))))
            (HT:Check "OBJ:RegistrarTipo recusa armazenamento incompleto"
              (null (OBJ:RegistrarTipo "teste-incompleto" "X" "x" '("LINE") nil nil nil
                      '(("ARMAZENAMENTO" . (("LER" . A)))))))
            (HT:Check "OBJ:TipoDados: tipo recusado nao entra no catalogo"
              (null (OBJ:TipoDados "teste-incompleto")))
            (HT:Check "OBJ:Op: tipo sem armazenamento proprio -> nil (usa o padrao)"
              (null (OBJ:Op "teste-tipo" "LER")))
            (HT:Check "OBJ:Cap NOME continua sendo o nome do TIPO (sem colisao com o contrato)"
              (= (OBJ:Cap "teste-tipo" "NOME") "Tipo de teste"))
            (HT:Check "OBJ:Cap ATRIB-DEFS guarda a descricao dos campos de ATRIB"
              (equal (car (car (OBJ:Cap "teste-tipo" "ATRIB-DEFS"))) "X"))
            (HT:Check "OBJ:_NomeTipo nil -> -" (= (OBJ:_NomeTipo nil) "-"))
            (HT:Check "OBJ:_NomeTipo desconhecido avisa"
              (vl-string-search "tipo ausente" (OBJ:_NomeTipo "nao-existe-xyz")))
            (HT:Check "OBJ:_NomeTipo conhecido -> nome" (= (OBJ:_NomeTipo "teste-tipo") "Tipo de teste"))
            (HT:Check "OBJ:_SetChave troca e remove"
              (and (= (OBJ:_Val "A" (OBJ:_SetChave '(("A" . 1)) "A" 2)) 2)
                   (null (assoc "A" (OBJ:_SetChave '(("A" . 1)) "A" nil)))))
            (HT:Check "OBJ:_MesmaEntrada compara metodo e TR"
              (and (OBJ:_MesmaEntrada '(("METODO" . "m") ("TR" . 10.0)) '(("METODO" . "m") ("TR" . 10.0)))
                   (null (OBJ:_MesmaEntrada '(("METODO" . "m") ("TR" . 10.0)) '(("METODO" . "m") ("TR" . 25.0))))))
            (HT:Check "OBJ:_FmtVal real/int/nil"
              (and (= (OBJ:_FmtVal 0.5) "0.5") (= (OBJ:_FmtVal 3) "3") (= (OBJ:_FmtVal nil) "-")))
            (HT:Check "OBJ:_RotuloParam com unidade"
              (= (OBJ:_RotuloParam "teste-tipo" "X") "Parametro X (m)"))
            (HT:Check "OBJ:Cap de tipo inexistente -> nil" (null (OBJ:Cap "nao-existe-xyz" "RECEBE")))
          )
        )
      )
      (HYDRO:RegDel "objeto-hidraulico" "teste-tipo")
      (setq r
        (append r
          (list
            (HT:Check "HYDRO:RegDel remove o tipo de teste" (null (OBJ:TipoDados "teste-tipo")))
          )
        )
      )
    )
  )

  (if (HYDRO:Has "objetos-tipos")
    (progn
      (HT:Section "objetos_tipos")
      (setq r
        (append r
          (list
            (HT:Check "tipos basicos cadastrados"
              (and (OBJ:TipoDados "trecho") (OBJ:TipoDados "estrutura") (OBJ:TipoDados "tubo-c3d")))
            (HT:Check "estrutura aceita AECC_STRUCTURE e bloco"
              (and (assoc "estrutura" (OBJ:TiposPara "AECC_STRUCTURE"))
                   (assoc "estrutura" (OBJ:TiposPara "INSERT"))))
            (HT:Check "tubo-c3d aceita AECC_PIPE"
              (assoc "tubo-c3d" (OBJ:TiposPara "AECC_PIPE")))
            (HT:Check "trecho aceita LINE e LWPOLYLINE"
              (and (assoc "trecho" (OBJ:TiposPara "LINE"))
                   (assoc "trecho" (OBJ:TiposPara "LWPOLYLINE"))))
            (HT:Check "regra da bacia: so bacia descarrega em bacia"
              (and (= (type (LIG:_Regra '(("REGRA" . BAC:_ObjRegra)) "sarjeta" "bacia")) 'STR)
                   (null (LIG:_Regra '(("REGRA" . BAC:_ObjRegra)) "bacia" "bacia"))
                   (null (LIG:_Regra '(("REGRA" . BAC:_ObjRegra)) "bacia" "sarjeta"))))
          )
        )
      )
      (if (OBJ:TipoDados "bacia")
        (setq r
          (append r
            (list
              (HT:Check "bacia nao e cadastravel por OBJETO"
                (null (assoc "bacia" (OBJ:TiposPara "LWPOLYLINE"))))
              (HT:Check "bacia: emite, recebe, detecta e tem vazao e area"
                (and (OBJ:Cap "bacia" "EMITE") (OBJ:Cap "bacia" "RECEBE")
                     (OBJ:Cap "bacia" "DETECTA") (OBJ:Cap "bacia" "VAZAO-EM")
                     (equal (OBJ:Cap "bacia" "TEMPO-MODO") "concentracao")
                     (OBJ:Cap "bacia" "AREA-PROPRIA") (OBJ:Cap "bacia" "DESTINO-PADRAO")))
            )
          )
        )
      )
    )
  )

  (if (HYDRO:Has "ligacao")
    (progn
      (HT:Section "ligacao (grafo puro)")
      ;; mapa receptor -> afluentes: A recebe B e D; B recebe C; D recebe C
      (setq mapa '(("A" "B" "D") ("B" "C") ("D" "C")))
      (setq ids (LIG:_MontanteH "A" (function (lambda (x) (cdr (assoc x mapa))))))
      (setq r
        (append r
          (list
            (HT:Check "LIG:_AddAfl em lista vazia (flag nil)"
              (equal (LIG:_AddAfl nil "2F" nil) '(("2F"))))
            (HT:Check "LIG:_AddAfl com flag T"
              (equal (LIG:_AddAfl '(("30")) "2F" T) '(("30") ("2F" . T))))
            (HT:Check "LIG:_AddAfl nao duplica"
              (equal (LIG:_AddAfl '(("2F")) "2F" nil) '(("2F"))))
            (HT:Check "LIG:_AddAfl atualiza o flag mantendo a posicao"
              (equal (LIG:_AddAfl '(("2F") ("30")) "2F" T) '(("2F" . T) ("30"))))
            (HT:Check "LIG:_RemAfl remove so a origem pedida"
              (equal (LIG:_RemAfl '(("2F" . T) ("30")) "2F") '(("30"))))
            (HT:Check "LIG:_HandlesDe" (equal (LIG:_HandlesDe '(("1" . T) ("2"))) '("1" "2")))
            ;; tempo de saida (valores calculados a mao; docs/arquitetura.md 15.4)
            ;; bacia, tp = 30: montante que NAO contribui ao talvegue corre em paralelo (max)
            (HT:Check "LIG:_TcPuro concentracao: nao contribui, tc_k=20 -> max(30,20) = 30"
              (HT:Near (LIG:_TcPuro "concentracao" 30.0 '((20.0))) 30.0 1e-9))
            (HT:Check "LIG:_TcPuro concentracao: nao contribui, tc_k=50 -> 50"
              (HT:Near (LIG:_TcPuro "concentracao" 30.0 '((50.0))) 50.0 1e-9))
            ;; contribui diretamente ao talvegue: serie (soma)
            (HT:Check "LIG:_TcPuro concentracao: contribui, tc_k=20 -> 20+30 = 50"
              (HT:Near (LIG:_TcPuro "concentracao" 30.0 '((20.0 . T))) 50.0 1e-9))
            (HT:Check "LIG:_TcPuro concentracao: contribui, tc_k=50 -> 80"
              (HT:Near (LIG:_TcPuro "concentracao" 30.0 '((50.0 . T))) 80.0 1e-9))
            (HT:Check "LIG:_TcPuro concentracao: (40 nao) e (10 sim) -> max(30,40,40) = 40"
              (HT:Near (LIG:_TcPuro "concentracao" 30.0 '((40.0) (10.0 . T))) 40.0 1e-9))
            (HT:Check "LIG:_TcPuro concentracao: sem montante = tp"
              (HT:Near (LIG:_TcPuro "concentracao" 30.0 nil) 30.0 1e-9))
            (HT:Check "LIG:_TcPuro percurso: max(20,35)+2.5 = 37.5"
              (HT:Near (LIG:_TcPuro "percurso" 2.5 '((20.0) (35.0))) 37.5 1e-9))
            (HT:Check "LIG:_TcPuro percurso: sem montante = nil"
              (null (LIG:_TcPuro "percurso" 2.5 nil)))
            ;; flag geral: maior vazao entre entrada e saida
            (HT:Check "LIG:Preserva: entrada 8 > calculada 5.5, flag ligada -> (8 T)"
              (equal (LIG:Preserva 8.0 5.5 T) '(8.0 T)))
            (HT:Check "LIG:Preserva: flag desligada -> calculada (5.5 nil)"
              (equal (LIG:Preserva 8.0 5.5 nil) '(5.5 nil)))
            (HT:Check "LIG:Preserva: calculada maior que a entrada -> calculada"
              (equal (LIG:Preserva 5.0 6.0 T) '(6.0 nil)))
            (HT:Check "LIG:Preserva: sem calculada -> entrada"
              (equal (LIG:Preserva 5.0 nil T) '(5.0 nil)))
            (HT:Check "LIG:Preserva: sem entrada -> calculada"
              (equal (LIG:Preserva nil 6.0 T) '(6.0 nil)))
            (HT:Check "BAC:_Compoe soma QP e VOLUME e guarda o proprio"
              (progn
                (setq comp
                  (BAC:_Compoe '(("QP" . 1.0) ("VOLUME" . 100.0))
                               '(("QP" . 2.5) ("VOLUME" . 300.0) ("AREA" . 50000.0))
                               20000.0 30.0))
                (and (HT:Near (cdr (assoc "QP" comp)) 3.5 1e-9)
                     (HT:Near (cdr (assoc "VOLUME" comp)) 400.0 1e-9)
                     (HT:Near (cdr (assoc "QP-PROPRIO" comp)) 1.0 1e-9)
                     (HT:Near (cdr (assoc "AREA-TOTAL" comp)) 70000.0 1e-9)
                     (HT:Near (cdr (assoc "TC-PROPRIO" comp)) 30.0 1e-9))))
            (HT:Check "BAC:_Compoe sem VOLUME nos montantes descarta o volume"
              (null (assoc "VOLUME"
                      (BAC:_Compoe '(("QP" . 1.0) ("VOLUME" . 100.0))
                                   '(("QP" . 2.5) ("AREA" . 1.0)) 1.0 30.0))))
            (HT:Check "LIG:_MontanteH: B, D e C (C uma vez so)"
              (and (= (length ids) 3) (member "B" ids) (member "D" ids) (member "C" ids)))
            (HT:Check "LIG:_MontanteH de folha = nada"
              (null (LIG:_MontanteH "C" (function (lambda (x) (cdr (assoc x mapa)))))))
            (HT:Check "LIG:_MontanteH nao entra em loop com ciclo"
              (= (length (LIG:_MontanteH "A" (function (lambda (x) (cdr (assoc x '(("A" "B") ("B" "A")))))))) 2))
            (HT:Check "LIG:_Indent" (= (LIG:_Indent 2) "        "))
          )
        )
      )
      ;; analise de integridade
      (setq existe (function (lambda (h) (if (= h "B3") nil T))))
      (setq prob (LIG:_Analisa '(("R1" "B1" "B2") ("R2" "B2" "B3")) existe))
      (setq r
        (append r
          (list
            (HT:Check "LIG:_Analisa: acha afluente apagado"
              (member '("PENDENTE" "R2" "B3") prob))
            (HT:Check "LIG:_Analisa: acha origem em dois receptores"
              (member '("DUPLICADA" "B2" ("R1" "R2")) prob))
            (HT:Check "LIG:_Analisa: so esses dois problemas" (= (length prob) 2))
            (HT:Check "LIG:_Analisa: sem problemas -> nil"
              (null (LIG:_Analisa '(("R1" "B1") ("R2" "B2")) (function (lambda (h) T)))))
            (HT:Check "LIG:_Analisa: detecta ciclo nos dois lados"
              (= (length (vl-remove-if-not
                           (function (lambda (p) (equal (car p) "CICLO")))
                           (LIG:_Analisa '(("A" "B") ("B" "A")) (function (lambda (h) T)))))
                 2))
          )
        )
      )
    )
  )

  (if (HYDRO:Has "sarjeta-obj")
    (progn
      (HT:Section "sarjeta_obj")
      (setq r
        (append r
          (list
            (HT:Check "tipo sarjeta cadastrado e aceita polilinha"
              (and (OBJ:TipoDados "sarjeta") (assoc "sarjeta" (OBJ:TiposPara "LWPOLYLINE"))))
            (HT:Check "sarjeta recebe, emite e calcula"
              (and (OBJ:Cap "sarjeta" "RECEBE") (OBJ:Cap "sarjeta" "EMITE") (OBJ:Cap "sarjeta" "CALCULA")))
            (HT:Check "SOB:_N usa a rugosidade do objeto quando > 0"
              (HT:Near (SOB:_N '(("N" . 0.02)) '(("n" . 0.013))) 0.02 1e-9))
            (HT:Check "SOB:_N cai na da secao quando 0 ou ausente"
              (and (HT:Near (SOB:_N '(("N" . 0.0)) '(("n" . 0.013))) 0.013 1e-9)
                   (HT:Near (SOB:_N nil '(("n" . 0.013))) 0.013 1e-9)))
          )
        )
      )
    )
  )

  (if (HYDRO:Has "objetos-tabela")
    (progn
      (HT:Section "objetos_tabela")
      (setq r
        (append r
          (list
            (HT:Check "OBT:_Trunc" (= (OBT:_Trunc "Sarjeta da Rua Norte" 14) "Sarjeta da R.."))
            (HT:Check "OBT:_Celula texto com ; -> aspas" (= (OBT:_Celula "a;b") "\"a;b\""))
            (HT:Check "OBT:_Celula nil -> vazio" (= (OBT:_Celula nil) ""))
            (HT:Check "OBT:_Filtra por parte do nome"
              (and (= (length (OBT:_Filtra '((("LINHA" . "Sarjeta S1\tSarjeta"))) "s1")) 1)
                   (= (length (OBT:_Filtra '((("LINHA" . "Sarjeta S1\tSarjeta"))) "zzz")) 0)))
          )
        )
      )
    )
  )
  r
)

;; apoio dos testes de auditoria (verificacoes falsas)
(defun HT:_AudV () (list (list "FAKE" 1) (list "FAKE" 2)))
(defun HT:_AudR (probs) (length probs))
(defun HT:_AudErro () (/ 1 0))

(defun HT:Run (/ r hits n antigos hid hid2 res defs)
  (princ "\n=== TESTES HYDRO ===")
  (setq r nil)

  (HT:Section "core")
  (setq r
    (append r
      (list
        (HT:Check "HYDRO:Has core" (HYDRO:Has "core"))
        (HT:Check "HYDRO:FmtNum 5.0 -> 5" (= (HYDRO:FmtNum 5.0) "5"))
        (HT:Check "HYDRO:FmtNum 2.5 -> 2.50" (= (HYDRO:FmtNum 2.5) "2.50"))
        (HT:Check "HYDRO:Join" (= (HYDRO:Join '("a" "b" "c") ";") "a;b;c"))
        (HT:Check "HYDRO:Join lista vazia" (= (HYDRO:Join nil ";") ""))
        (HT:Check "HYDRO:_Flatten"
          (equal (HYDRO:_Flatten '(("A" ("B" . 1) ("C" . "x")) ("D" . 2.5)) "")
                 '(("A.B" . 1) ("A.C" . "x") ("D" . 2.5)))
        )
        (HT:Check "HYDRO:FindFile viewer.dcl devolve caminho (string)"
          (= (type (HYDRO:FindFile "viewer.dcl")) 'STR))
        (HT:Check "HYDRO:FindModule plugins/idf devolve caminho (string)"
          (= (type (HYDRO:FindModule "plugins/idf")) 'STR))
        (HT:Check "HYDRO:FindModule inexistente -> nil"
          (null (HYDRO:FindModule "plugins/nao-existe-xyz")))
        (HT:Check "HYDRO:FirstFile lista sem arquivos -> nil"
          (null (HYDRO:FirstFile '("nao-existe-1.xyz" "nao-existe-2.xyz"))))
        (HT:Check "HYDRO:FirstFile devolve o 1o existente (string)"
          (= (type (HYDRO:FirstFile
                     (list "nao-existe-1.xyz"
                           (HYDRO:FindModule "plugins/idf"))))
             'STR))
      )
    )
  )

  (HYDRO:Set "TESTE.CHAVE" 42.5)
  (setq r
    (append r
      (list
        (HT:Check "HYDRO:Set/Get" (equal (HYDRO:Get "TESTE.CHAVE" nil) 42.5))
        (HT:Check "HYDRO:Get padrao" (= (HYDRO:Get "TESTE.NAO.EXISTE" "pad") "pad"))
      )
    )
  )
  (HYDRO:Del "TESTE.CHAVE")

  (setq hits 0)
  (HYDRO:On "teste.evento" "t1" '(lambda (d) (setq hits (+ hits (cdr (assoc "N" d))))))
  (HYDRO:Emit "teste.evento" '(("N" . 3)))
  (HYDRO:Off "teste.evento" "t1")
  (HYDRO:Emit "teste.evento" '(("N" . 3)))
  (setq r (append r (list (HT:Check "HYDRO:On/Emit/Off" (= hits 3)))))

  (if (HYDRO:Has "persistencia")
    (progn
      (HT:Section "persistencia")
      (setq r
        (append r
          (list
            (HT:Check "DB:_Chunk" (equal (DB:_Chunk "abcdefghij" 4) '("abcd" "efgh" "ij")))
            (HT:Check "DB:_PathToList" (equal (DB:_PathToList "A.B.C") '("A" "B" "C")))
            (HT:Check "DB:_SetNode/_GetNode"
              (= (DB:_GetNode (DB:_SetNode nil '("A" "B") 5) '("A" "B")) 5))
            (HT:Check "DB:_DeleteNode"
              (null (DB:_GetNode (DB:_DeleteNode (DB:_SetNode nil '("A" "B") 5) '("A" "B")) '("A" "B"))))
          )
        )
      )
    )
  )

  (if (HYDRO:Has "idf")
    (progn
      (HT:Section "idf")
      ;; guarda os parametros IDF reais para restaurar depois
      (setq antigos
        (mapcar
          (function (lambda (n) (HYDRO:Get (strcat "HYDRO.IDF." n) nil)))
          '("K" "A" "B" "C" "S" "P")
        )
      )
      (HYDRO:Set "HYDRO.IDF.K" 1000.0) (HYDRO:Set "HYDRO.IDF.A" 0.15)
      (HYDRO:Set "HYDRO.IDF.B" 10.0)   (HYDRO:Set "HYDRO.IDF.C" 0.8)
      (HYDRO:Set "HYDRO.IDF.S" 0.0)    (HYDRO:Set "HYDRO.IDF.P" 0.0)
      (setq r
        (append r
          (list
            (HT:Check "PREC:Intensidade (tc=20, TR=10) = 92.9615"
              (HT:Near (PREC:Intensidade 20.0 10.0) 92.96147 0.001))
          )
        )
      )
      ;; restaura os parametros originais
      (foreach n '("K" "A" "B" "C" "S" "P")
        (if (car antigos)
          (HYDRO:Set (strcat "HYDRO.IDF." n) (car antigos))
          (HYDRO:Del (strcat "HYDRO.IDF." n))
        )
        (setq antigos (cdr antigos))
      )
    )
  )

  (if (HYDRO:Has "sarjetas")
    (progn
      (HT:Section "sarjetas")
      (setq r
        (append r
          (list
            (HT:Check "SARJ:TcKirpich (L=500, S=0.02) = 10.5484 min"
              (HT:Near (SARJ:TcKirpich 500.0 0.02) 10.54837 0.001))
            (HT:Check "SARJ:TcKirpich declividade 0 -> nil"
              (null (SARJ:TcKirpich 500.0 0.0)))
            (HT:Check "SARJ:VazaoRacional (C=0.8, i=150, 1 ha) = 0.33333 m3/s"
              (HT:Near (SARJ:VazaoRacional 0.8 150.0 10000.0) 0.333333 0.00001))
            (HT:Check "SOB:LaminaIzzard (Q=0.05, z=33.33, n=0.016, S=0.01) = 0.063433 m"
              (HT:Near (SOB:LaminaIzzard 0.05 (/ 100.0 3.0) 0.016 0.01) 0.063433 0.00001))
          )
        )
      )
    )
  )

  (if (HYDRO:Has "secao")
    (progn
      (HT:Section "secao")
      (setq r
        (append r
          (list
            (HT:Check "SJT:Val" (equal (SJT:Val "w" '(1 ("h" . 0.15) ("w" . 3.5))) 3.5))
            (HT:Check "SJT:TextoLargura 0.15 = 29" (= (SJT:TextoLargura "0.15") 29))
            (HT:Check "SJT:TextoLargura vazio = 0" (= (SJT:TextoLargura "") 0))
            (HT:Check "SJT:_Real 0,045 -> 0.045" (HT:Near (SJT:_Real "0,045") 0.045 1e-9))
            (HT:Check "SJT:_Real vazio -> nil" (null (SJT:_Real "")))
            (HT:Check "SJT:_IndiceSecao acha o id"
              (= (SJT:_IndiceSecao '((0 ("w" . 1.0)) (3 ("w" . 2.0))) 3 0) 1))
            (HT:Check "SJT:_IndiceSecao id inexistente -> padrao"
              (= (SJT:_IndiceSecao '((0 ("w" . 1.0))) 9 0) 0))
            (HT:Check "SJT:_MaxW"
              (HT:Near (SJT:_MaxW '((0 ("w" . 1.0)) (1 ("w" . 3.5)))) 3.5 1e-9))
          )
        )
      )
      (if (HYDRO:Has "sarjetas")
        (progn
          (setq hid
            (SJT:Hidraulica
              '(1 ("h" . 0.15) ("s" . 3.0) ("w" . 3.5) ("n" . 0.016)) 0.05 0.01))
          (setq hid2
            (SJT:Hidraulica
              '(1 ("h" . 0.15) ("s" . 3.0) ("w" . 3.5) ("n" . 0.016)) 0.5 0.01))
          (setq r
            (append r
              (list
                (HT:Check "SJT:Hidraulica y = 0.063433"
                  (HT:Near (cdr (assoc "Y" hid)) 0.063433 0.00001))
                (HT:Check "SJT:Hidraulica T = 2.114444"
                  (HT:Near (cdr (assoc "T" hid)) 2.114444 0.00001))
                (HT:Check "SJT:Hidraulica velocidade = 0.745566 m/s"
                  (HT:Near (cdr (assoc "V" hid)) 0.745566 0.00001))
                (HT:Check "SJT:Hidraulica Q baixo: contido na secao"
                  (and (null (cdr (assoc "EXCEDE-H" hid)))
                       (null (cdr (assoc "EXCEDE-W" hid)))))
                (HT:Check "SJT:Hidraulica Q alto: excede h e w"
                  (and (cdr (assoc "EXCEDE-H" hid2))
                       (cdr (assoc "EXCEDE-W" hid2))))
                (HT:Check "SJT:Hidraulica sem Q -> nil"
                  (null (SJT:Hidraulica '(1 ("h" . 0.15) ("s" . 3.0) ("w" . 3.5) ("n" . 0.016)) nil 0.01)))
              )
            )
          )
        )
      )
    )
  )

  (if (HYDRO:Has "visualizador")
    (progn
      (HT:Section "visualizador")
      (setq r
        (append r
          (list
            (HT:Check "VIEW:_Real 781.0 -> 781" (= (VIEW:_Real 781.0) "781"))
            (HT:Check "VIEW:_Real 0.045 -> 0.045" (= (VIEW:_Real 0.045) "0.045"))
            (HT:Check "VIEW:_CsvCelula 0.045 -> 0,045" (= (VIEW:_CsvCelula "0.045") "0,045"))
            (HT:Check "VIEW:_CsvCelula a;b -> aspas" (= (VIEW:_CsvCelula "a;b") "\"a;b\""))
            (HT:Check "VIEW:_Replace" (= (VIEW:_Replace "a.b.c" "." "-") "a-b-c"))
          )
        )
      )
    )
  )

  (if (HYDRO:Has "objetos-padrao")
    (progn
      (HT:Section "objetos-padrao")
      (setq r
        (append r
          (list
            (HT:Check "OPD:Casa: texto vazio casa tudo" (OPD:Casa "" "Bacia 1" "2F"))
            (HT:Check "OPD:Casa: parte do nome, sem diferenciar maiusculas"
              (OPD:Casa "acia" "Bacia 1" "2F"))
            (HT:Check "OPD:Casa: handle igual" (OPD:Casa "2f" "Bacia 1" "2F"))
            (HT:Check "OPD:Casa: handle parcial nao casa" (null (OPD:Casa "2" "Bacia 1" "2F")))
            (HT:Check "OPD:Casa: nome diferente nao casa" (null (OPD:Casa "xyz" "Bacia 1" "2F")))
          )
        )
      )
    )
  )

  (HT:Section "etiquetas (substituicao de campos)")
  (setq r
    (append r
      (list
        (HT:Check "ETQ:Substitui troca os campos"
          (equal (ETQ:Substitui "A={A} B={B}" (function (lambda (n) (cdr (assoc n '(("A" . "1") ("B" . "xx")))))))
                 "A=1 B=xx"))
        (HT:Check "ETQ:Substitui: campo desconhecido vira ?"
          (equal (ETQ:Substitui "x{Z}y" (function (lambda (n) nil))) "x?y"))
        (HT:Check "ETQ:Substitui: campos colados e texto sem campo"
          (equal (ETQ:Substitui "{A}{B}!" (function (lambda (n) n))) "AB!"))
        (HT:Check "ETQ:Substitui: chave sem fechar fica como esta"
          (equal (ETQ:Substitui "a {A" (function (lambda (n) "1"))) "a {A"))
        (HT:Check "ETQ:_CI ignora maiusculas"
          (equal (ETQ:_CI "cn" '(("C" . 0.6) ("CN" . 80.0))) '("CN" . 80.0)))
        (HT:Check "ETQ:_Fmt: real<1 com 4 casas, real>=1 com 3, T = sim"
          (and (equal (ETQ:_Fmt 0.0123) "0.0123") (equal (ETQ:_Fmt 3.14159) "3.142")
               (equal (ETQ:_Fmt T) "sim")))
      )
    )
  )

  (HT:Section "padroes do projeto")
  (setq r
    (append r
      (list
        (HT:Check "HYDRO:PadraoKey troca HYDRO. por HYDRO.PADRAO."
          (equal (HYDRO:PadraoKey "HYDRO.MET.racional." "C") "HYDRO.PADRAO.MET.racional.C"))
        (HT:Check "HYDRO:ParamsPadrao: sem nada = padrao do metodo"
          (progn
            (setq defs '(("C" "x" 0.6 "")))
            (HT:Near (cdr (car (HYDRO:ParamsPadrao defs "HYDRO.TST." nil))) 0.6 1e-9)))
        (HT:Check "HYDRO:ParamsPadrao: ultimo usado vence o padrao do metodo"
          (progn
            (HYDRO:Set "HYDRO.TST.C" 0.5)
            (HT:Near (cdr (car (HYDRO:ParamsPadrao defs "HYDRO.TST." nil))) 0.5 1e-9)))
        (HT:Check "HYDRO:ParamsPadrao: padrao do projeto vence o ultimo usado"
          (progn
            (HYDRO:Set "HYDRO.PADRAO.TST.C" 0.4)
            (HT:Near (cdr (car (HYDRO:ParamsPadrao defs "HYDRO.TST." nil))) 0.4 1e-9)))
        (HT:Check "HYDRO:ParamsPadrao: sobrescrita (atributo) vence tudo"
          (HT:Near (cdr (car (HYDRO:ParamsPadrao defs "HYDRO.TST." '(("C" . 0.3))))) 0.3 1e-9))
        (HT:Check "HYDRO:CalcAuto: desligado por padrao e liga com 1"
          (progn
            (HYDRO:Del "HYDRO.CALC.AUTO")
            (and (null (HYDRO:CalcAuto))
                 (progn (HYDRO:Set "HYDRO.CALC.AUTO" 1) (HYDRO:CalcAuto)))))
      )
    )
  )
  (HYDRO:Del "HYDRO.TST.C")
  (HYDRO:Del "HYDRO.PADRAO.TST.C")
  (HYDRO:Del "HYDRO.CALC.AUTO")

  (if (HYDRO:Has "auditoria")
    (progn
      (HT:Section "auditoria")
      (HYDRO:RegAdd "auditoria" "teste-aud"
        (list (cons "NOME" "Teste") (cons "VERIFICA" 'HT:_AudV)
              (cons "TEXTO" (function (lambda (p) "x"))) (cons "REPARA" 'HT:_AudR)))
      (HYDRO:RegAdd "auditoria" "teste-erro"
        (list (cons "NOME" "Erro") (cons "VERIFICA" 'HT:_AudErro)))
      (setq res (AUD:Verificar))
      (setq r
        (append r
          (list
            (HT:Check "AUD:Verificar acha os 2 problemas da verificacao de teste"
              (= (length (cadr (assoc "teste-aud" res))) 2))
            (HT:Check "AUD:Verificar: verificacao que da erro vira ERRO-VERIFICACAO"
              (equal (car (car (cadr (assoc "teste-erro" res)))) "ERRO-VERIFICACAO"))
            (HT:Check "AUD:Reparar devolve quantos corrigiu"
              (= (AUD:Reparar "teste-aud" (cadr (assoc "teste-aud" res))) 2))
            (HT:Check "AUD:Reparar sem REPARA devolve 0"
              (= (AUD:Reparar "teste-erro" (cadr (assoc "teste-erro" res))) 0))
            (HT:Check "AUD:PodeReparar" (and (AUD:PodeReparar "teste-aud")
                                             (null (AUD:PodeReparar "teste-erro"))))
          )
        )
      )
      (HYDRO:RegDel "auditoria" "teste-aud")
      (HYDRO:RegDel "auditoria" "teste-erro")
    )
  )

  (setq r (append r (HT:RunNovos)))
  (setq r (append r (HT:RunBacias)))
  (setq r (append r (HT:RunObjetos)))

  (princ
    (strcat "\n=== "
            (itoa (length (vl-remove nil r))) "/" (itoa (length r))
            " verificacoes OK ==="
    )
  )
  (if (member nil r) nil T)
)

(defun c:HYDROTESTE ()
  (HT:Run)
  (princ)
)

(princ "\nTestes carregados. Digite HYDROTESTE.")
(princ)
