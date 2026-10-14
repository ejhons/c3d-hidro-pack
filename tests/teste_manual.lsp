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

(defun HT:RunNovos (/ r antigos ctx res hid arq arq2 prm vz gr back)
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
            (HT:Check "BAC:_Grupos separa PRECIPITACAO e VAZAO; _CalcFlat e o inverso"
              (progn
                (setq vz '(("CENARIO" . "TR10") ("METODO" . "racional") ("TR" . 10.0) ("DUR" . 14.2)
                           ("TC" . 14.2) ("PARAMS" . (("C" . 0.6))) ("I" . 150.2) ("P" . 35.5)
                           ("PE" . 21.3) ("QP" . 3.123) ("VOLUME" . 2556.0) ("QP-PROPRIO" . 3.0)))
                (setq gr (BAC:_Grupos vz))
                (setq back
                  (BAC:_CalcFlat "TR10"
                    (list (cons "CENARIO" (list (cons "TR" 10.0)))
                          (assoc "PRECIPITACAO" gr) (assoc "VAZAO" gr))))
                (and (equal (HYDRO:Val "VALOR" (HYDRO:Val "VAZAO" gr)) 3.123)
                     (equal (HYDRO:Val "INPUT" (HYDRO:Val "VAZAO" gr)) '(("C" . 0.6)))
                     (equal (HYDRO:Val "VALOR" (HYDRO:Val "PRECIPITACAO" gr)) 35.5)
                     (equal (HYDRO:Val "UNIDADE" (HYDRO:Val "PRECIPITACAO" gr)) "mm")
                     (null (assoc "TR" (HYDRO:Val "VAZAO" gr)))
                     (vl-every (function (lambda (x) (equal (cdr (assoc (car x) back)) (cdr x)))) vz))))
            (HT:Check "OBJ:_SetChave troca valor existente"
              (equal (HYDRO:Val "X" (OBJ:_SetChave '(("X" . 1) ("Y" . 2)) "X" 9)) 9))
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
(defun HT:RunBacias (/ r ctx dados calc linhas reg ctxb hf hg hb)
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
          ("RESULT" . (("TR10" ("CENARIO" ("TR" . 10.0))
                               ("TC" ("VALOR" . 12.0) ("METODO" . "kirpich"))
                               ("VAZAO" ("VALOR" . 1.0) ("METODO" . "racional")))))))
      (setq r
        (append r
          (list
            (HT:Check "BAC: registro padrao tem TIPO bacia e VERSAO 2"
              (and (equal (HYDRO:Val "TIPO" dados) "bacia")
                   (equal (HYDRO:Val "VERSAO" dados) 2)))
            (HT:Check "BAC:Talvegue vem de PARAMS" (equal (BAC:Talvegue dados) "2F"))
            (HT:Check "BAC:Atrib / BAC:Caract"
              (and (equal (BAC:Atrib dados) '(("C" . 0.6)))
                   (equal (BAC:Caract dados) '(("AREA" . 100.0)))))
            (HT:Check "BAC:Tc vem do grupo TC do cenario"
              (and (HT:Near (HYDRO:Val "MIN" (BAC:Tc dados)) 12.0 1e-9)
                   (equal (HYDRO:Val "ORIGEM" (BAC:Tc dados)) "kirpich")
                   (HT:Near (HYDRO:Val "MIN" (BAC:TcDeCenario dados "TR10")) 12.0 1e-9)
                   (null (BAC:TcDeCenario dados "TR99"))))
            (HT:Check "BAC:Vazao: uma vazao plana por cenario com VAZAO"
              (and (= (length (BAC:Vazao dados)) 1)
                   (equal (HYDRO:Val "METODO" (car (BAC:Vazao dados))) "racional")
                   (equal (HYDRO:Val "CENARIO" (car (BAC:Vazao dados))) "TR10")
                   (HT:Near (HYDRO:Val "QP" (BAC:CalcDe dados "TR10")) 1.0 1e-9)
                   (null (BAC:CalcDe dados "TR99"))))
            (HT:Check "BAC:Hidrogramas sem hidrograma -> nil" (null (BAC:Hidrogramas dados)))
            (HT:Check "HID:_Grupo / BAC:_HidFlat: ida e volta do hidrograma por cenario"
              (progn
                (setq hf '(("CENARIO" . "TR10") ("TIPO" . "triangular-scs") ("METODO" . "racional")
                           ("TR" . 10.0) ("DUR" . 14.2) ("PARAMS" . (("DT" . 1.0))) ("QP" . 3.1)
                           ("TP" . 12.0) ("TB" . 32.0) ("VOLUME" . 2500.0)
                           ("PONTOS" . ((0.0 . 0.0) (12.0 . 3.1) (32.0 . 0.0)))))
                (setq hg (HID:_Grupo hf))
                (setq hb
                  (BAC:_HidFlat "TR10"
                    (list (cons "CENARIO" (list (cons "TR" 10.0)))
                          (cons "VAZAO" (list (cons "VALOR" 3.0) (cons "METODO" "racional")))
                          (cons "HIDROGRAMA" hg))))
                (and (equal (HYDRO:Val "VALOR" hg) 3.1)
                     (null (assoc "TR" hg)) (null (assoc "METODO" hg))
                     (equal (HYDRO:Val "INPUT" hg) '(("DT" . 1.0)))
                     (vl-every (function (lambda (x) (equal (cdr (assoc (car x) hb)) (cdr x)))) hf))))
            (HT:Check "BAC:_HidFlat sem PONTOS -> nil"
              (null (BAC:_HidFlat "TR10" '(("HIDROGRAMA" ("VALOR" . 1.0))))))
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
          ("RESULT" . (("TR10" ("CENARIO" ("TR" . 10.0))
                               ("TC" ("VALOR" . 14.2) ("METODO" . "kirpich"))
                               ("PRECIPITACAO" ("VALOR" . 35.5) ("UNIDADE" . "mm") ("I" . 150.2)
                                               ("P" . 35.5) ("PE" . 21.3))
                               ("VAZAO" ("VALOR" . 3.123) ("METODO" . "racional") ("DUR" . 14.2)
                                        ("TC" . 14.2) ("VOLUME" . 2556.0)))))))
      (setq calc (car (BAC:Vazao dados)))
      (setq ctxb (BAC:_Ctx dados (BAC:TcDeCenario dados "TR10")))
      (setq r
        (append r
          (list
            (HT:Check "OBJ:_Limpa remove pares nil"
              (equal (OBJ:_Limpa '(("A" . 1) ("B") ("C" . "x"))) '(("A" . 1) ("C" . "x"))))
            (HT:Check "BAC:TcDe: TC-USUARIO > 0 vale como esta"
              (and (HT:Near (cdr (assoc "MIN" (BAC:TcDe '(("ATRIB" ("TC-USUARIO" . 25.0)))))) 25.0 1e-9)
                   (equal (cdr (assoc "ORIGEM" (BAC:TcDe '(("ATRIB" ("TC-USUARIO" . 25.0)))))) "usuario")))
            (HT:Check "BAC:TcDe: sem declividade -> ERRO"
              (assoc "ERRO"
                (BAC:TcDe '(("ATRIB" ("TC-METODO" . "kirpich")) ("CARACT" ("COMP" . 1000.0))))))
            (HT:Check "BAC:_CaractCalc deriva DESNIVEL = DECL * COMP"
              (HT:Near
                (cdr (assoc "DESNIVEL"
                       (BAC:_CaractCalc '(("CARACT" ("COMP" . 1000.0) ("DECL" . 0.05))))))
                50.0 1e-9))
            (HT:Check "BAC:_Ctx traz caracteristicas, tc, NOME e atributos"
              (and (equal (cdr (assoc "NOME" ctxb)) "B1")
                   (equal (cdr (assoc "CN" ctxb)) 80.0)
                   (equal (cdr (assoc "AREA" ctxb)) 120000.0)
                   (HT:Near (cdr (assoc "TC" ctxb)) 14.2 1e-9)
                   (equal (cdr (assoc "TC-ORIGEM" ctxb)) "kirpich")))
            (HT:Check "BAC:_Sobrescritas: CN do cadastro preenche o parametro CN"
              (equal (BAC:_Sobrescritas '(("C" . 0.6) ("CN" . 80.0))
                                        '(("CN" "CN" 75.0 "") ("LAMBDA" "L" 0.2 "")))
                     '(("CN" . 80.0))))
            (HT:Check "OBJ:_SetChave com nil remove o item"
              (null (assoc "X" (OBJ:_SetChave '(("X" . 1) ("Y" . 2)) "X" nil))))
            (HT:Check "BAC:Contexto: TC do calculo vem antes do TC da bacia"
              (HT:Near (cdr (assoc "TC" (BAC:Contexto
                          '(("CARACT" . (("AREA" . 1.0)))
                            ("RESULT" . (("TR10" ("TC" ("VALOR" . 99.0))))))
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
            ("RESULT" . (("TR10" ("CENARIO" ("TR" . 10.0))
                                 ("TC" ("VALOR" . 14.2) ("METODO" . "usuario"))
                                 ("VAZAO" ("VALOR" . 3.123) ("METODO" . "racional") ("DUR" . 14.2)
                                          ("TC" . 14.2)))
                         ("TR25" ("CENARIO" ("TR" . 25.0))
                                 ("VAZAO" ("VALOR" . 4.5) ("METODO" . "racional") ("DUR" . 14.2)
                                          ("TC" . 14.2))))))
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
                         '(("RESULT" . (("TR10" ("VAZAO" ("VALOR" . 3.123)))
                                        ("TR25" ("VAZAO" ("VALOR" . 4.5)))))))
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
(defun HT:RunObjetos (/ r mapa existe prob ids comp ro)
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
              (and (= (HYDRO:Val "A" (OBJ:_SetChave '(("A" . 1)) "A" 2)) 2)
                   (null (assoc "A" (OBJ:_SetChave '(("A" . 1)) "A" nil)))))
            (HT:Check "OBJ:CenarioPadrao: 25.0 -> TR25, 2.5 -> TR2.5, nil -> nil"
              (and (equal (OBJ:CenarioPadrao 25.0) "TR25")
                   (equal (OBJ:CenarioPadrao 2.5) "TR2.5")
                   (equal (OBJ:CenarioPadrao 100) "TR100")
                   (null (OBJ:CenarioPadrao nil))))
            (HT:Check "OBJ:CenarioNome: TR e nome opcional"
              (and (equal (OBJ:CenarioNome 25.0 nil) "TR25")
                   (equal (OBJ:CenarioNome 25.0 "") "TR25")
                   (equal (OBJ:CenarioNome 25.0 "Urbanizado") "TR25-Urbanizado")
                   (null (OBJ:CenarioNome nil "X"))))
            (HT:Check "OBJ:_ResultCalculo: TR, limpa OBSOLETO, grava grupos, preserva outros cenarios"
              (equal
                (OBJ:_ResultCalculo
                  '(("TR25" ("CENARIO" ("TR" . 25.0) ("OBSOLETO" . T)) ("VAZAO" ("VALOR" . 1.0)))
                    ("TR10" ("VAZAO" ("VALOR" . 5.0))))
                  "TR25" 25.0
                  '(("ENTRADA" ("VALOR" . 4.0)) ("VAZAO" ("VALOR" . 9.88))))
                '(("TR25" ("CENARIO" ("TR" . 25.0)) ("ENTRADA" ("VALOR" . 4.0)) ("VAZAO" ("VALOR" . 9.88)))
                  ("TR10" ("VAZAO" ("VALOR" . 5.0))))))
            (HT:Check "OBJ:_ResultCalculo cria o cenario novo com TR"
              (equal (OBJ:_ResultCalculo nil "TR50-X" 50.0 '(("VAZAO" ("VALOR" . 2.0))))
                     '(("TR50-X" ("CENARIO" ("TR" . 50.0)) ("VAZAO" ("VALOR" . 2.0))))))
            (HT:Check "OBJ:_ResultSetGrupo cria cenario e grupo"
              (equal (OBJ:_ResultSetGrupo nil "TR25" "VAZAO" '(("VALOR" . 9.88)))
                     '(("TR25" ("VAZAO" ("VALOR" . 9.88))))))
            (HT:Check "OBJ:_ResultSetGrupo substitui so o grupo do cenario"
              (equal
                (OBJ:_ResultSetGrupo
                  '(("TR25" ("TC" ("VALOR" . 15.0)) ("VAZAO" ("VALOR" . 1.0))) ("TR10" ("VAZAO" ("VALOR" . 5.0))))
                  "TR25" "VAZAO" '(("VALOR" . 9.88)))
                '(("TR25" ("TC" ("VALOR" . 15.0)) ("VAZAO" ("VALOR" . 9.88))) ("TR10" ("VAZAO" ("VALOR" . 5.0))))))
            (HT:Check "OBJ:_ResultSetGrupo com campos nil remove o grupo e o cenario vazio"
              (null (OBJ:_ResultSetGrupo '(("TR25" ("VAZAO" ("VALOR" . 1.0)))) "TR25" "VAZAO" nil)))
            (HT:Check "OBJ:_ResultObsoleto marca todos os cenarios; _ObsoletoR/_TodosObsoletosR"
              (progn
                (setq ro (OBJ:_ResultObsoleto '(("TR25" ("CENARIO" ("TR" . 25.0)) ("VAZAO" ("VALOR" . 1.0))) ("TR10" ("VAZAO" ("VALOR" . 5.0))))))
                (and (OBJ:_ObsoletoR ro "TR25") (OBJ:_ObsoletoR ro "TR10") (OBJ:_ObsoletoR ro nil)
                     (OBJ:_TodosObsoletosR ro)
                     (equal (HYDRO:Val "TR" (HYDRO:Val "CENARIO" (cdr (assoc "TR25" ro)))) 25.0))))
            (HT:Check "obsoleto por cenario: so um marcado -> _ObsoletoR sim, _Todos nao"
              (and (OBJ:_ObsoletoR '(("A" ("CENARIO" ("OBSOLETO" . T))) ("B" ("VAZAO" ("VALOR" . 1.0)))) nil)
                   (null (OBJ:_ObsoletoR '(("A" ("CENARIO" ("OBSOLETO" . T))) ("B" ("VAZAO" ("VALOR" . 1.0)))) "B"))
                   (null (OBJ:_TodosObsoletosR '(("A" ("CENARIO" ("OBSOLETO" . T))) ("B" ("VAZAO" ("VALOR" . 1.0))))))
                   (null (OBJ:_TodosObsoletosR nil))))
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
              (HT:Check "bacia e cadastravel por OBJETO (cadastro generico)"
                (assoc "bacia" (OBJ:TiposPara "LWPOLYLINE")))
              (HT:Check "bacia declara talvegue (PARAMS-DEFS), CARACT-DEFS e CARACTERIZA"
                (and (assoc "TALVEGUE" (OBJ:Cap "bacia" "PARAMS-DEFS"))
                     (assoc "COMP" (OBJ:Cap "bacia" "CARACT-DEFS"))
                     (OBJ:Cap "bacia" "CARACTERIZA")))
              (HT:Check "bacia: emite, recebe e tem vazao e area"
                (and (OBJ:Cap "bacia" "EMITE") (OBJ:Cap "bacia" "RECEBE")
                     (OBJ:Cap "bacia" "VAZAO-EM")
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
            ;; pares (origem destino flag): B,D -> A ; C -> B ; C2 -> D (B contribui ao talvegue de A)
            (HT:Check "LIG:_AflDe: montantes de A com o flag da origem"
              (equal (LIG:_AflDe '(("B" "A" T) ("D" "A" nil) ("C" "B" nil)) "A")
                     '(("B" . T) ("D"))))
            (HT:Check "LIG:_AflDe: destino sem afluentes = nil"
              (null (LIG:_AflDe '(("B" "A" T)) "B")))
            (HT:Check "LIG:_MapaAfl agrupa origens por destino"
              (equal (LIG:_MapaAfl '(("B" "A" T) ("C" "B" nil) ("D" "A" nil)))
                     '(("A" "B" "D") ("B" "C"))))
            (HT:Check "LIG:_MapaAfl sem ligacoes = nil" (null (LIG:_MapaAfl nil)))
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
      (setq existe (function (lambda (h) (if (= h "B3x") nil T))))
      (setq prob (LIG:_Analisa '(("B1" "R1" nil) ("B2" "R2" nil) ("B3" "B3x" nil)) existe))
      (setq r
        (append r
          (list
            (HT:Check "LIG:_Analisa: acha destino apagado"
              (member '("PENDENTE" "B3" "B3x") prob))
            (HT:Check "LIG:_Analisa: so esse problema" (= (length prob) 1))
            (HT:Check "LIG:_Analisa: sem problemas -> nil"
              (null (LIG:_Analisa '(("B1" "R1" nil) ("B2" "R2" T)) (function (lambda (h) T)))))
            (HT:Check "LIG:_Analisa: detecta ciclo nos dois lados"
              (= (length (vl-remove-if-not
                           (function (lambda (p) (equal (car p) "CICLO")))
                           (LIG:_Analisa '(("A" "B" nil) ("B" "A" nil)) (function (lambda (h) T)))))
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

;;; ------------------------------------------------------------
;;; Obsolescencia (funcoes puras de objetos.lsp)
;;; ------------------------------------------------------------
(defun HT:RunObsoleto (/ a b r)
  (HT:Section "Obsolescencia (OBJ:_Igual, OBJ:_MudouCadastro)")
  (setq a (list (cons "ATRIB" (list (cons "DIAM" 0.8) (cons "N" 0.013)))
                (cons "PARAMS" (list (cons "JUSANTE" (cons "2A" T))))
                (cons "CARACT" (list (cons "COMP" 100.0) (cons "MANUAL" (list "COMP"))))))
  (setq r
    (list
      (HT:Check "_Igual: reais com tolerancia" (OBJ:_Igual 0.8 (+ 0.8 1e-12)))
      (HT:Check "_Igual: reais diferentes" (null (OBJ:_Igual 0.8 0.9)))
      (HT:Check "_Igual: par pontilhado" (OBJ:_Igual (cons "2A" T) (cons "2A" T)))
      (HT:Check "_Igual: par com flag nil diferente" (null (OBJ:_Igual (cons "2A" T) (list "2A"))))
      (HT:Check "_IgualAlist ignora a ordem"
        (OBJ:_IgualAlist (list (cons "A" 1.0) (cons "B" 2.0)) (list (cons "B" 2.0) (cons "A" 1.0))))
      (HT:Check "_IgualAlist: tamanhos diferentes"
        (null (OBJ:_IgualAlist (list (cons "A" 1.0)) (list (cons "A" 1.0) (cons "B" 2.0)))))
      (HT:Check "_MudouCadastro: igual (outra ordem) = nil"
        (null (OBJ:_MudouCadastro a
                (list (cons "CARACT" (list (cons "MANUAL" (list "COMP")) (cons "COMP" 100.0)))
                      (cons "PARAMS" (list (cons "JUSANTE" (cons "2A" T))))
                      (cons "ATRIB" (list (cons "N" 0.013) (cons "DIAM" 0.8)))))))
    )
  )
  (setq b (OBJ:_SetChave a "ATRIB" (list (cons "DIAM" 1.0) (cons "N" 0.013))))
  (append r
    (list
      (HT:Check "_MudouCadastro: ATRIB diferente = T" (OBJ:_MudouCadastro a b))
      (HT:Check "_MudouCadastro: so RESULT/NOME diferente = nil"
        (null (OBJ:_MudouCadastro a (append a (list (cons "NOME" "x") (cons "RESULT" (list (cons "VAZAO" nil))))))))
    )
  )
)

;;; ------------------------------------------------------------
;;; Tubo / canal (models/tubo.lsp): Manning, geometria e seccoes. Valores calculados em Python.
;;; ------------------------------------------------------------
(defun HT:RunTubo (/ r circ ret trp rs rc)
  (HT:Section "tubo / canal (Manning)")
  (setq circ (STB:_NovaSecao 0 "circular" 0.8 nil nil nil 0.013))
  (setq ret (STB:_NovaSecao 1 "retangular" nil 1.0 1.0 nil 0.015))
  (setq trp (STB:_NovaSecao 2 "trapezoidal" nil 1.0 1.0 1.5 0.025))
  (setq rs (TUB:Resolver circ 0.01 0.013 0.3))
  (setq rc (TUB:Resolver circ 0.01 0.013 5.0))
  (list
    (HT:Check "TUB:_Acos: 0 -> pi/2, 1 -> 0, -1 -> pi, 0.5 -> 1.047198"
      (and (HT:Near (TUB:_Acos 0.0) (/ pi 2.0) 1e-9) (HT:Near (TUB:_Acos 1.0) 0.0 1e-9)
           (HT:Near (TUB:_Acos -1.0) pi 1e-9) (HT:Near (TUB:_Acos 0.5) 1.047198 1e-5)
           (HT:Near (TUB:_Acos -0.5) 2.094395 1e-5)))
    (HT:Check "TUB:_Q circular D=0.8 cheio, S=0.01, n=0.013 = 1.32235 m3/s"
      (HT:Near (TUB:_Q (TUB:_Geom circ 0.8) 0.013 0.01) 1.32235 1e-4))
    (HT:Check "TUB:_Geom/_Q circular D=0.8 meia secao: A = 0.25133, P = 1.25664, Q = 0.66118"
      (and (HT:Near (cdr (assoc "A" (TUB:_Geom circ 0.4))) 0.251327 1e-5)
           (HT:Near (cdr (assoc "P" (TUB:_Geom circ 0.4))) 1.256637 1e-5)
           (HT:Near (TUB:_Q (TUB:_Geom circ 0.4) 0.013 0.01) 0.661175 1e-4)))
    (HT:Check "TUB:_Q retangular b=1, y=0.5, n=0.015, S=0.001 = 0.41832 m3/s"
      (HT:Near (TUB:_Q (TUB:_Geom ret 0.5) 0.015 0.001) 0.418317 1e-4))
    (HT:Check "TUB:_Geom trapezio b=1, z=1.5, y=0.6: A=1.14, P=3.16333, T=2.8"
      (and (HT:Near (cdr (assoc "A" (TUB:_Geom trp 0.6))) 1.14 1e-6)
           (HT:Near (cdr (assoc "P" (TUB:_Geom trp 0.6))) 3.163331 1e-5)
           (HT:Near (cdr (assoc "T" (TUB:_Geom trp 0.6))) 2.8 1e-6)))
    (HT:Check "TUB:Resolver retangular devolve y = 0.5 para Q = 0.418317"
      (HT:Near (cdr (assoc "Y" (TUB:Resolver ret 0.001 0.015 0.4183169))) 0.5 1e-4))
    (HT:Check "TUB:Resolver trapezio: y = 0.6, V = 0.64057, Fr = 0.32052 para Q = 0.73025"
      (progn
        (setq r (TUB:Resolver trp 0.001 0.025 0.7302502))
        (and (HT:Near (cdr (assoc "Y" r)) 0.6 1e-4)
             (HT:Near (cdr (assoc "V" r)) 0.640570 1e-4)
             (HT:Near (cdr (assoc "FR" r)) 0.320523 1e-4))))
    (HT:Check "TUB:Resolver circular D=0.8, S=0.01, Q=0.3: y = 0.25907 (lamina livre)"
      (and (HT:Near (cdr (assoc "Y" rs)) 0.259067 1e-4) (null (cdr (assoc "CHEIO" rs)))
           (HT:Near (cdr (assoc "QCAP" rs)) 1.32235 1e-4)))
    (HT:Check "TUB:Resolver circular com Q > maxima (1.42246): y = D, CHEIO e aviso"
      (and (cdr (assoc "CHEIO" rc)) (HT:Near (cdr (assoc "Y" rc)) 0.8 1e-9)
           (HT:Near (cdr (assoc "QMAX" rc)) 1.42246 1e-3) (cdr (assoc "AVISOS" rc))))
    (HT:Check "TUB:Resolver: declividade nula, n invalido e Q nulo -> ERRO"
      (and (assoc "ERRO" (TUB:Resolver circ 0.0 0.013 0.3))
           (assoc "ERRO" (TUB:Resolver circ 0.01 0.0 0.3))
           (assoc "ERRO" (TUB:Resolver circ 0.01 0.013 0.0))))
    (HT:Check "TUB:_Decl: |dz|/L; cotas iguais ou L nulo -> nil"
      (and (HT:Near (TUB:_Decl 100.0 10.0 8.5) 0.015 1e-9)
           (HT:Near (TUB:_Decl 100.0 8.5 10.0) 0.015 1e-9)
           (null (TUB:_Decl 100.0 0.0 0.0)) (null (TUB:_Decl 0.0 1.0 2.0))
           (null (TUB:_Decl nil 1.0 2.0))))
    (HT:Check "STB:_NovaSecao valida e rejeita dimensoes invalidas"
      (and circ ret trp
           (null (STB:_NovaSecao 9 "circular" 0.0 nil nil nil 0.013))
           (null (STB:_NovaSecao 9 "retangular" nil 1.0 nil nil 0.013))
           (null (STB:_NovaSecao 9 "trapezoidal" nil 1.0 1.0 -1.0 0.025))
           (null (STB:_NovaSecao 9 "circular" 0.6 nil nil nil 0.0))
           (null (STB:_NovaSecao 9 "oval" 0.6 nil nil nil 0.013))))
    (HT:Check "TUB:_N: do objeto se > 0, senao da seccao"
      (and (HT:Near (TUB:_N '(("N" . 0.02)) circ) 0.02 1e-9)
           (HT:Near (TUB:_N '(("N" . 0.0)) circ) 0.013 1e-9)
           (HT:Near (TUB:_N nil ret) 0.015 1e-9)))
  )
)

;;; Visualizador de secoes de tubo (funcoes puras de views/secao_tubo_view.lsp)
(defun HT:RunTuboView (/ circ ret trp pts)
  (HT:Section "visualizador de secoes de tubo")
  (setq circ (STB:_NovaSecao 0 "circular" 0.8 nil nil nil 0.013))
  (setq ret (STB:_NovaSecao 1 "retangular" nil 1.0 1.0 nil 0.015))
  (setq trp (STB:_NovaSecao 2 "trapezoidal" nil 1.0 1.0 1.5 0.025))
  (setq pts (STB:_PontosLaminaCirc 0.4 0.4))
  (list
    (HT:Check "STB:_Dim: circular (D D), retangular (b h), trapezio (b+2zh h)"
      (and (equal (STB:_Dim circ) '(0.8 0.8)) (equal (STB:_Dim ret) '(1.0 1.0))
           (HT:Near (car (STB:_Dim trp)) 4.0 1e-9) (HT:Near (cadr (STB:_Dim trp)) 1.0 1e-9)))
    (HT:Check "STB:_MaxDim pega a maior largura e a maior altura"
      (and (HT:Near (car (STB:_MaxDim (list circ ret trp))) 4.0 1e-9)
           (HT:Near (cadr (STB:_MaxDim (list circ ret trp))) 1.0 1e-9)))
    (HT:Check "STB:_IndiceSecao: acha o id, senao o padrao"
      (and (= (STB:_IndiceSecao (list circ ret trp) 2 9) 2) (= (STB:_IndiceSecao (list circ ret trp) 7 9) 9)))
    (HT:Check "STB:_Real: virgula decimal e vazio"
      (and (HT:Near (STB:_Real "0,045") 0.045 1e-9) (HT:Near (STB:_Real "1.5") 1.5 1e-9)
           (null (STB:_Real "")) (null (STB:_Real nil))))
    (HT:Check "STB:_PontosLaminaCirc meia secao: parte de (-r, r), passa por (0, 0), termina em (r, r)"
      (and (= (length pts) 33)
           (HT:Near (car (car pts)) -0.4 1e-9) (HT:Near (cadr (car pts)) 0.4 1e-9)
           (HT:Near (car (nth 16 pts)) 0.0 1e-9) (HT:Near (cadr (nth 16 pts)) 0.0 1e-9)
           (HT:Near (car (last pts)) 0.4 1e-9) (HT:Near (cadr (last pts)) 0.4 1e-9)))
    (HT:Check "STB:Hidraulica: so com Q e S positivos; devolve y do Manning"
      (and (null (STB:Hidraulica circ nil 0.01)) (null (STB:Hidraulica circ 0.3 0.0))
           (HT:Near (cdr (assoc "Y" (STB:Hidraulica circ 0.3 0.01))) 0.259067 1e-4)))
  )
)

;;; Ligacoes temporarias na tela (funcoes puras de views/ligacao_visual_view.lsp)
(defun HT:RunLigVisual (/ tr s)
  (HT:Section "ligacoes temporarias (LIGACOESVER)")
  (setq tr (LVW:_Tracos 10.0 1.0 1.0 300))
  (setq s (LVW:_Seta '(0.0 0.0 0.0) '(10.0 0.0 0.0) 1.0))
  (list
    (HT:Check "LVW:_Tracos d=10, traco 1, vazio 1: 5 tracos de 0-1 ate 8-9"
      (and (= (length tr) 5) (HT:Near (car (car tr)) 0.0 1e-9) (HT:Near (cdr (car tr)) 1.0 1e-9)
           (HT:Near (car (last tr)) 8.0 1e-9) (HT:Near (cdr (last tr)) 9.0 1e-9)))
    (HT:Check "LVW:_Tracos: ultimo traco nao passa do comprimento; linha curta = 1 traco; d<=0 = nil"
      (and (HT:Near (cdr (last (LVW:_Tracos 9.5 1.0 1.0 300))) 9.5 1e-9)
           (= (length (LVW:_Tracos 0.4 1.0 1.0 300)) 1)
           (null (LVW:_Tracos 0.0 1.0 1.0 300))))
    (HT:Check "LVW:_Tracos: limita a quantidade (linha muito longa)"
      (<= (length (LVW:_Tracos 100000.0 1.0 1.0 300)) 301))
    (HT:Check "LVW:_Seta: duas pontas a 25 graus, a distancia `tam` da ponta, para tras"
      (and (= (length s) 2)
           (HT:Near (distance (car s) '(10.0 0.0 0.0)) 1.0 1e-9)
           (HT:Near (distance (cadr s) '(10.0 0.0 0.0)) 1.0 1e-9)
           (< (car (car s)) 10.0) (< (car (cadr s)) 10.0)
           (HT:Near (+ (cadr (car s)) (cadr (cadr s))) 0.0 1e-9)
           (HT:Near (abs (cadr (car s))) (sin (* 25.0 (/ pi 180.0))) 1e-9)))
    (HT:Check "LVW:_Seta com origem = destino -> nil" (null (LVW:_Seta '(1.0 1.0 0.0) '(1.0 1.0 0.0) 1.0)))
  )
)

;;; Estrutura: catalogo de tipos (plugins/tipo_estrutura.lsp), classes (registry/estrutura_*.lsp)
;;; e metodos de captacao (registry/captacao.lsp). Valores calculados fora do AutoCAD.
(defun HT:RunEstrutura (/ bl r1 r2 r3)
  (HT:Section "estrutura (poco, caixa, ala, boca de lobo)")
  (setq bl (TES:_NovoTipo 5 "BL combinada" "boca-lobo" '(("metodo" . "unitaria") ("cap" . 0.05))))
  (setq r1 (EBL:Captacao bl 2 0.08 nil))
  (setq r2 (EBL:Captacao bl 2 0.15 nil))
  (setq r3 (EBL:Captacao bl 3 0.12 0.1))
  (list
    (HT:Check "classes cadastradas: passagem e boca-lobo; metodo de captacao unitaria"
      (and (TES:Classe "passagem") (TES:Classe "boca-lobo") (HYDRO:RegGet "metodo-captacao" "unitaria")))
    (HT:Check "ESP:PerdaCarga: K=0.5, V=2 m/s -> 0.10194 m; K=0, sem V ou V<0 -> nil"
      (and (HT:Near (ESP:PerdaCarga 0.5 2.0) 0.101937 1e-5)
           (null (ESP:PerdaCarga 0.0 2.0)) (null (ESP:PerdaCarga 0.5 nil))
           (null (ESP:PerdaCarga 0.5 -1.0))))
    (HT:Check "TES:_NovoTipo valida pela classe: passagem (K >= 0) e boca de lobo (cap > 0, metodo)"
      (and bl
           (TES:_NovoTipo 1 "PV" "passagem" '(("k" . 0.0))) (TES:_NovoTipo 1 "PV" "passagem" '(("k" . 0.3)))
           (null (TES:_NovoTipo 1 "PV" "passagem" '(("k" . -0.1)))) (null (TES:_NovoTipo 1 "PV" "passagem" nil))
           (null (TES:_NovoTipo 1 "" "passagem" '(("k" . 0.0))))
           (null (TES:_NovoTipo 1 "BL" "boca-lobo" '(("metodo" . "unitaria") ("cap" . 0.0))))
           (null (TES:_NovoTipo 1 "BL" "boca-lobo" '(("cap" . 0.05))))
           (null (TES:_NovoTipo 1 "X" "oval" '(("k" . 0.0))))))
    (HT:Check "TES:_NovoTipo guarda so os campos da classe"
      (equal (TES:_NovoTipo 1 "PV" "passagem" '(("k" . 0.3) ("cap" . 9.0)))
             '(1 ("nome" . "PV") ("classe" . "passagem") ("k" . 0.3))))
    (HT:Check "EBL:Captacao dupla (2 x 0.05 = 0.10 m3/s) com Q = 0.08: capta tudo, sem aviso"
      (and (HT:Near (cdr (assoc "QCAP" r1)) 0.10 1e-9) (HT:Near (cdr (assoc "CAPTADA" r1)) 0.08 1e-9)
           (HT:Near (cdr (assoc "PASSAGEM" r1)) 0.0 1e-9) (HT:Near (cdr (assoc "RAZAO" r1)) 0.8 1e-9)
           (null (cdr (assoc "AFOGADA" r1))) (null (cdr (assoc "AVISOS" r1)))))
    (HT:Check "EBL:Captacao dupla com Q = 0.15: afogada, capta 0.10, passam 0.05, razao 1.5, aviso"
      (and (cdr (assoc "AFOGADA" r2)) (HT:Near (cdr (assoc "CAPTADA" r2)) 0.10 1e-9)
           (HT:Near (cdr (assoc "PASSAGEM" r2)) 0.05 1e-9) (HT:Near (cdr (assoc "RAZAO" r2)) 1.5 1e-9)
           (vl-string-search "Boca de lobo afogada" (car (cdr (assoc "AVISOS" r2))))))
    (HT:Check "EBL:Captacao tripla e proporcional (3 x 0.05 = 0.15), aceita lamina sem usa-la"
      (and (HT:Near (cdr (assoc "QCAP" r3)) 0.15 1e-9) (null (cdr (assoc "AFOGADA" r3)))))
    (HT:Check "EBL:Captacao: capacidade 0, metodo inexistente, qtd 0 e Q nulo -> ERRO"
      (and (assoc "ERRO" (EBL:Captacao '(9 ("nome" . "BL") ("classe" . "boca-lobo") ("metodo" . "unitaria") ("cap" . 0.0)) 1 0.1 nil))
           (assoc "ERRO" (EBL:Captacao '(9 ("nome" . "BL") ("classe" . "boca-lobo") ("metodo" . "nao-existe") ("cap" . 0.05)) 1 0.1 nil))
           (assoc "ERRO" (EBL:Captacao bl 0 0.1 nil))
           (assoc "ERRO" (EBL:Captacao bl 1 0.0 nil))))
    (HT:Check "classe passagem calcula pelo ctx: dH com V dos montantes; sem V, aviso; K = 0, sem grupo de perda"
      (and (HT:Near (cdr (assoc "VALOR" (cdr (assoc "PERDA_CARGA"
             (ESP:_Calcula nil '(("MONTANTES" ("V" . 2.0))) '(1 ("nome" . "PV") ("classe" . "passagem") ("k" . 0.5)) nil)))))
             0.101937 1e-5)
           (cdr (assoc "VALOR" (cdr (assoc "AVISOS"
             (ESP:_Calcula nil '(("MONTANTES" ("V"))) '(1 ("nome" . "PV") ("classe" . "passagem") ("k" . 0.5)) nil)))))
           (null (assoc "PERDA_CARGA"
             (ESP:_Calcula nil '(("MONTANTES" ("V" . 2.0))) '(1 ("nome" . "PV") ("classe" . "passagem") ("k" . 0.0)) nil)))))
  )
)

;;; Escada hidraulica (models/escada.lsp) e dissipador (registry/estrutura_dissipador.lsp).
;;; Valores calculados fora do AutoCAD (Python).
(defun HT:RunEscada (/ d1 d2 tp)
  (HT:Section "escada hidraulica")
  (setq d1 (ESC:Degraus 3.0 0.3 (sqrt 409.0)))
  (setq d2 (ESC:Degraus 3.0 0.35 (sqrt 409.0)))
  (list
    (HT:Check "ESC:AlturaCritica: Q=2, b=2 -> 0.46714; Q=3, b=1.5 -> 0.74153; Q ou b nulos -> nil"
      (and (HT:Near (ESC:AlturaCritica 2.0 2.0) 0.467136 1e-5)
           (HT:Near (ESC:AlturaCritica 3.0 1.5) 0.741533 1e-5)
           (null (ESC:AlturaCritica 0.0 2.0)) (null (ESC:AlturaCritica 2.0 0.0))))
    (HT:Check "ESC:Degraus dz=3, h=0.3, L=sqrt(409): 10 degraus de 0.3, piso 2.0, teta 8.5308 graus (sem erro de ponto flutuante)"
      (and (= (cdr (assoc "NDEG" d1)) 10) (HT:Near (cdr (assoc "ALTURA" d1)) 0.3 1e-9)
           (HT:Near (cdr (assoc "PISO" d1)) 2.0 1e-9) (HT:Near (cdr (assoc "LH" d1)) 20.0 1e-9)
           (HT:Near (cdr (assoc "TETA" d1)) 8.530766 1e-5)))
    (HT:Check "ESC:Degraus h=0.35: arredonda para cima (9 degraus de 0.3333, piso 2.2222)"
      (and (= (cdr (assoc "NDEG" d2)) 9) (HT:Near (cdr (assoc "ALTURA" d2)) (/ 3.0 9.0) 1e-9)
           (HT:Near (cdr (assoc "PISO" d2)) (/ 20.0 9.0) 1e-9)))
    (HT:Check "ESC:Degraus: desnivel nulo, h nulo e comprimento <= desnivel -> ERRO"
      (and (assoc "ERRO" (ESC:Degraus 0.0 0.3 20.0)) (assoc "ERRO" (ESC:Degraus 3.0 0.0 20.0))
           (assoc "ERRO" (ESC:Degraus 3.0 0.3 3.0)) (assoc "ERRO" (ESC:Degraus 3.0 0.3 nil))))
    (HT:Check "ESC:_Decl e ESC:_Desnivel: |dz|/L; cotas iguais -> nil; DECL x COMP se so digitados"
      (and (HT:Near (ESC:_Decl 20.0 5.0 2.0) 0.15 1e-9) (null (ESC:_Decl 20.0 0.0 0.0))
           (HT:Near (ESC:_Desnivel '(("DESNIVEL" . 3.0))) 3.0 1e-9)
           (HT:Near (ESC:_Desnivel '(("DECL" . 0.15) ("COMP" . 20.0))) 3.0 1e-9)
           (null (ESC:_Desnivel '(("COMP" . 20.0))))))
    (HT:Check "ESC:_IdsMetodo: sempre comeca por nenhum"
      (equal (car (ESC:_IdsMetodo)) "nenhum"))
  )
)

(defun HT:RunDissipador (/ tp b)
  (HT:Section "dissipador de energia")
  (setq tp (TES:_NovoTipo 7 "Dissipador" "dissipador" '(("metodo" . "informado") ("eficiencia" . 0.6))))
  (setq b (EDI:Balanco tp 2.0 1.0 5.0 nil))
  (list
    (HT:Check "classe dissipador e metodos informado, usbr e enrocamento cadastrados"
      (and (TES:Classe "dissipador") (HYDRO:RegGet "metodo-dissipacao" "informado")
           (HYDRO:RegGet "metodo-dissipacao" "usbr") (HYDRO:RegGet "metodo-dissipacao" "enrocamento")))
    (HT:Check "EDI:EnergiaEspecifica y=1, V=5 -> 2.27421 m; EDI:Potencia Q=2, dE=1.364526 -> 26.772 kW"
      (and (HT:Near (EDI:EnergiaEspecifica 1.0 5.0) 2.27421 1e-5)
           (HT:Near (EDI:Potencia 2.0 1.364526) 26.772 1e-3)
           (null (EDI:EnergiaEspecifica nil 5.0)) (null (EDI:EnergiaEspecifica 1.0 -1.0))))
    (HT:Check "EDI:Balanco informado 60%: Ein 2.27421, Eout 0.90968, dissipada 1.36453, 26.772 kW"
      (and tp (HT:Near (cdr (assoc "EIN" b)) 2.27421 1e-5) (HT:Near (cdr (assoc "EOUT" b)) 0.909684 1e-5)
           (HT:Near (cdr (assoc "DISSIPADA" b)) 1.364526 1e-5) (HT:Near (cdr (assoc "EFICIENCIA" b)) 0.6 1e-9)
           (HT:Near (cdr (assoc "POTENCIA" b)) 26.772 1e-3)))
    (HT:Check "EDI:Balanco informado sem lamina/velocidade de montante -> ERRO"
      (and (assoc "ERRO" (EDI:Balanco tp 2.0 nil 5.0 nil)) (assoc "ERRO" (EDI:Balanco tp 2.0 1.0 nil nil))))
    (HT:Check "TES:_NovoTipo dissipador: campos do metodo (eficiencia), valida pelo metodo"
      (and (null (TES:_NovoTipo 7 "D" "dissipador" '(("metodo" . "informado") ("eficiencia" . 1.2))))
           (null (TES:_NovoTipo 7 "D" "dissipador" '(("metodo" . "informado") ("eficiencia" . -0.1))))
           (null (TES:_NovoTipo 7 "D" "dissipador" '(("eficiencia" . 0.5))))
           (null (TES:_NovoTipo 7 "D" "dissipador" '(("metodo" . "nao-existe") ("eficiencia" . 0.5))))
           (TES:_NovoTipo 7 "D" "dissipador" '(("metodo" . "informado") ("eficiencia" . 0.0)))
           (equal (TES:_NovoTipo 7 "D" "dissipador" '(("metodo" . "informado") ("eficiencia" . 0.5) ("lixo" . 1)))
                  '(7 ("nome" . "D") ("classe" . "dissipador") ("metodo" . "informado") ("eficiencia" . 0.5)))))
  )
)

;; Bacias de dissipacao (registry/dissipacao_usbr.lsp e dissipacao_enrocamento.lsp): exemplos 4.6 e
;; 4.7 do manual SisCCoH 1.1 (docs/referencia-dissipadores-siscooh.md). Valores do proprio manual
;; (e do codigo de referencia dele), tolerancia de ~1%.
(defun HT:RunBaciasDissipacao (/ r tpu tpe m)
  (HT:Section "bacias de dissipacao (USBR e enrocamento)")
  (setq r (DUS:Bacia 10.0 2.5 0.215))
  (setq tpu (TES:_NovoTipo 8 "USBR" "dissipador" '(("metodo" . "usbr") ("largura" . 2.5))))
  (setq tpe (TES:_NovoTipo 9 "Enroc" "dissipador"
              '(("metodo" . "enrocamento") ("largura" . 2.44) ("d50" . 0.55) ("tw" . 0.85) ("hs" . 1.147)
                ("curva" . "envelope") ("talude" . 2.0))))
  (setq m (DEN:Bacia 22.713 2.44 1.22 0.55 0.85 7.63 1.147 "envelope" 2.0))
  (list
    (HT:Check "DUS:Tipo: 1.5 -> I; 3 -> IV; Fr 5 com V >= 20 -> II; Fr 5 com V < 20 -> III; Fr < 1.2 -> nil"
      (and (equal (DUS:Tipo 1.5 5.0) "I") (equal (DUS:Tipo 3.0 5.0) "IV") (equal (DUS:Tipo 5.0 25.0) "II")
           (equal (DUS:Tipo 5.0 10.0) "III") (null (DUS:Tipo 1.0 3.0)) (equal (DUS:Tipo 4.5 5.0) "IV")))
    (HT:Check "DUS:Bacia exemplo 4.6: V1 18.6, Fr1 12.81, tipo III, D2 3.79, L 10.23, dE 14.01, U 1.06"
      (and (HT:Near (cdr (assoc "V1" r)) 18.6047 1e-3) (HT:Near (cdr (assoc "FR" r)) 12.8106 1e-3)
           (equal (cdr (assoc "TIPO" r)) "III") (HT:Near (cdr (assoc "D2" r)) 3.7891 1e-3)
           (HT:Near (cdr (assoc "L" r)) 10.2306 1e-3) (HT:Near (cdr (assoc "DE" r)) 14.0109 1e-3)
           (HT:Near (cdr (assoc "U" r)) 1.05566 1e-4)))
    (HT:Check "DUS:Bacia exemplo 4.6: borda livre 2.24, parede 6.03, h3 0.6005, h4 0.3679, Ein 17.857, Eout 3.846"
      (and (HT:Near (cdr (assoc "BL" r)) 2.23938 1e-3) (HT:Near (cdr (assoc "H" r)) 6.02848 1e-3)
           (HT:Near (cdr (assoc "H3" r)) 0.600517 1e-4) (HT:Near (cdr (assoc "H4" r)) 0.367872 1e-4)
           (HT:Near (cdr (assoc "EIN" r)) 17.8568 1e-3) (HT:Near (cdr (assoc "EOUT" r)) 3.84591 1e-3)))
    (HT:Check "DUS:Bacia tipo I: D2 = 2 D1, L = 4 D2; Fr < 1.2 e dado nulo -> ERRO"
      (and (progn (setq r (DUS:Bacia 1.0 2.0 0.2))
                  (and (equal (cdr (assoc "TIPO" r)) "I") (HT:Near (cdr (assoc "D2" r)) 0.4 1e-9)
                       (HT:Near (cdr (assoc "L" r)) 1.6 1e-9)))
           (assoc "ERRO" (DUS:Bacia 1.0 2.0 1.0)) (assoc "ERRO" (DUS:Bacia 0.0 2.0 0.2))
           (assoc "ERRO" (DUS:Bacia 1.0 nil 0.2))))
    (HT:Check "metodo usbr pelo catalogo: grupos da bacia e energia (tipo com largura); sem largura invalida"
      (and tpu
           (progn (setq r (EDI:Balanco tpu 10.0 0.215 18.6047 nil))
                  (and (HT:Near (cdr (assoc "EOUT" r)) 3.84591 1e-3)
                       (equal (cdr (assoc "VALOR" (cdr (assoc "BACIA_USBR" (cdr (assoc "GRUPOS" r)))))) "III")))
           (null (TES:_NovoTipo 8 "USBR" "dissipador" '(("metodo" . "usbr") ("largura" . 0.0))))))
    (HT:Check "DEN:Co: tabela do HEC-14 (best 1.4/0.7; envelope 2.0/1.0; fora -> nil)"
      (and (HT:Near (DEN:Co 0.5 "best") 1.4 1e-9) (HT:Near (DEN:Co 0.9 "best") 0.7 1e-9)
           (HT:Near (DEN:Co 0.5 "envelope") 2.0 1e-9) (HT:Near (DEN:Co 0.9 "envelope") 1.0 1e-9)
           (null (DEN:Co 1.2 "envelope")) (null (DEN:Co -0.1 "best"))))
    (HT:Check "DEN:Bacia exemplo 4.7: Dmin 0.346, Dmax 0.873, Co 2, D50/ye 0.451, Fr0 2.206, hs/D50 2.085"
      (and (HT:Near (cdr (assoc "DMIN" m)) 0.346478 1e-4) (HT:Near (cdr (assoc "DMAX" m)) 0.873071 1e-4)
           (HT:Near (cdr (assoc "CO" m)) 2.0 1e-9) (HT:Near (cdr (assoc "D50-YE" m)) 0.45082 1e-4)
           (HT:Near (cdr (assoc "FR0" m)) 2.20552 1e-4) (HT:Near (cdr (assoc "HS-D50" m)) 2.08545 1e-4)))
    (HT:Check "DEN:Bacia exemplo 4.7: Ls 11.47, LB 17.205, LA 5.735, WB 13.91, espessuras 1.31 e 1.65"
      (and (HT:Near (cdr (assoc "LS" m)) 11.47 1e-3) (HT:Near (cdr (assoc "LB" m)) 17.205 1e-3)
           (HT:Near (cdr (assoc "LA" m)) 5.735 1e-3) (HT:Near (cdr (assoc "WB" m)) 13.91 1e-3)
           (HT:Near (cdr (assoc "E1" m)) 1.30961 1e-4) (HT:Near (cdr (assoc "E2" m)) 1.65 1e-9)))
    (HT:Check "DEN:ProfSaida: y3 satisfaz Q^2/g = A^3/T (verificacao de consistencia da eq. 4.68)"
      (progn (setq r (DEN:ProfSaida 22.713 13.91 2.0))
             (HT:Near (/ (expt (* (+ 13.91 (* 2.0 r)) r) 3.0) (+ 13.91 (* 4.0 r)))
                      (/ (* 22.713 22.713) 9.81) 1e-3)))
    (HT:Check "DEN:Bacia: D50/ye fora de 0.1 a 0.7, hs/D50 < 2, TW/ye > 1 e dados nulos -> ERRO"
      (and (assoc "ERRO" (DEN:Bacia 22.7 2.44 1.22 0.05 0.85 7.63 1.147 "envelope" 2.0))
           (assoc "ERRO" (DEN:Bacia 22.7 2.44 1.22 0.9 0.85 7.63 3.0 "envelope" 2.0))
           (assoc "ERRO" (DEN:Bacia 22.7 2.44 1.22 0.55 0.85 7.63 0.9 "envelope" 2.0))
           (assoc "ERRO" (DEN:Bacia 22.7 2.44 1.22 0.55 1.5 7.63 1.147 "envelope" 2.0))
           (assoc "ERRO" (DEN:Bacia 22.7 nil 1.22 0.55 0.85 7.63 1.147 "envelope" 2.0))))
    (HT:Check "metodo enrocamento: sem energia de saida (so grupos); tipo valido so com curva best/envelope"
      (and tpe
           (progn (setq r (EDI:Balanco tpe 22.713 1.22 7.63 nil))
                  (and (null (cdr (assoc "EOUT" r))) (assoc "COMPRIMENTO_BACIA" (cdr (assoc "GRUPOS" r)))))
           (null (TES:_NovoTipo 9 "E" "dissipador"
                   '(("metodo" . "enrocamento") ("largura" . 2.44) ("d50" . 0.55) ("tw" . 0.85) ("hs" . 1.147)
                     ("curva" . "outra") ("talude" . 2.0))))))
  )
)

;; Escada hidraulica, metodo SisCCoH (registry/escada_siscooh.lsp): exemplos 4.1, 4.2 e 4.3 do manual
;; (docs/referencia-escadas-hidraulicas-siscooh.md).
(defun HT:RunEscadaSiscooh (/ rg lm nap sk g)
  (HT:Section "escada hidraulica - metodo SisCCoH (exemplos 4.1 a 4.3)")
  (setq rg (ESS:Regime 0.5 1.0 (ESS:Yc 4.0)))
  (setq lm (ESS:LimitesVazao 2.5 0.5 1.0))
  (setq nap (ESS:Nappe 2.0 4.0 0.5 2.5 5.0 10 "ressalto-parcial"))
  (setq sk (ESS:Skimming 10.0 2.5 0.5 1.0 50.0))
  (setq g (ESS:Metodo (list (cons "Q" 10.0) (cons "B" 2.5) (cons "YC" (ESS:Yc 4.0)) (cons "H" 0.5)
                            (cons "L" 1.0) (cons "NDEG" 100) (cons "DESNIVEL" 50.0))))
  (list
    (HT:Check "metodo siscooh cadastrado no catalogo metodo-escada"
      (HYDRO:RegGet "metodo-escada" "siscooh"))
    (HT:Check "ESS:Yc: q=4 -> 1.17711 m; q=0.5 -> 0.29428 m"
      (and (HT:Near (ESS:Yc 4.0) 1.17711 1e-4) (HT:Near (ESS:Yc 0.5) 0.294277 1e-5)))
    (HT:Check "Ex 4.1: regime skimming tipo A, teta 26.57, S/yc 0.425"
      (and (equal (cdr (assoc "TIPO" rg)) "skimming") (equal (cdr (assoc "SUBTIPO" rg)) "A")
           (HT:Near (cdr (assoc "TETA" rg)) 26.565 1e-2) (HT:Near (cdr (assoc "SY" rg)) 0.42478 1e-3)))
    (HT:Check "Ex 4.1: faixas de vazao: nappe ate 1.724, skimming a partir de 2.613 m3/s"
      (and (HT:Near (cdr (assoc "NAPPE" lm)) 1.72407 1e-3) (HT:Near (cdr (assoc "SKIMMING" lm)) 2.61256 1e-3)))
    (HT:Check "Ex 4.2: faixas 2.973 / 5.256 e regime nappe com ressalto parcial (teta 11.31)"
      (and (HT:Near (cdr (assoc "NAPPE" (ESS:LimitesVazao 4.0 0.5 2.5))) 2.97272 1e-3)
           (HT:Near (cdr (assoc "SKIMMING" (ESS:LimitesVazao 4.0 0.5 2.5))) 5.25620 1e-3)
           (equal (cdr (assoc "SUBTIPO" (ESS:Regime 0.5 2.5 (ESS:Yc 0.5)))) "ressalto-parcial")
           (equal (cdr (assoc "TIPO" (ESS:Regime 0.5 2.5 (ESS:Yc 0.5)))) "nappe")))
    (HT:Check "Ex 4.2 nappe: DN 0.204, Ld 1.399, Lj 2.808, Hmax 5.441, parede 0.762"
      (and (HT:Near (cdr (assoc "DN" nap)) 0.203874 1e-4) (HT:Near (cdr (assoc "LD" nap)) 1.39948 1e-3)
           (HT:Near (cdr (assoc "LJ" nap)) 2.80820 1e-3) (HT:Near (cdr (assoc "HMAX" nap)) 5.44142 1e-4)
           (HT:Near (cdr (assoc "PAREDE" nap)) 0.762075 1e-3)))
    (HT:Check "Ex 4.2 nappe: Hr 0.859, eficiencia 84.2 %, d 0.132, V 3.774, Fr 3.31"
      (and (HT:Near (cdr (assoc "HR" nap)) 0.858585 1e-3) (HT:Near (cdr (assoc "ETA" nap)) 0.842213 1e-4)
           (HT:Near (cdr (assoc "D" nap)) 0.13247 5e-4) (HT:Near (cdr (assoc "V" nap)) 3.77444 5e-3)
           (HT:Near (cdr (assoc "FR" nap)) 3.3110 5e-3)))
    (HT:Check "Ex 4.3 skimming: He 23.39, f 0.172, dw 0.428, Er 4.838, Cmed 0.369, Y0.9 0.678, parede 0.95"
      (and (HT:Near (cdr (assoc "HE" sk)) 23.3883 1e-3) (HT:Near (cdr (assoc "F" sk)) 0.17176 1e-3)
           (HT:Near (cdr (assoc "DW" sk)) 0.427815 1e-4) (HT:Near (cdr (assoc "ER" sk)) 4.83827 1e-3)
           (HT:Near (cdr (assoc "CMED" sk)) 0.369397 1e-4) (HT:Near (cdr (assoc "Y09" sk)) 0.678422 1e-4)
           (HT:Near (cdr (assoc "HW" sk)) 0.949791 1e-3) (cdr (assoc "UNIFORME" sk))))
    (HT:Check "Ex 4.3 skimming: Va 5.90, Vf 9.35, inicio da aeracao 15.29 m, Ya 0.558"
      (and (HT:Near (cdr (assoc "VA" sk)) 5.89603 1e-3) (HT:Near (cdr (assoc "VF" sk)) 9.34983 1e-3)
           (HT:Near (cdr (assoc "LA" sk)) 15.2905 1e-2) (HT:Near (cdr (assoc "YA" sk)) 0.558349 1e-4)))
    (HT:Check "ESS:Metodo (ex 4.3): grupos REGIME skimming, ENERGIA_RESIDUAL e estado final (lamina, velocidade, Froude)"
      (and (equal (cdr (assoc "VALOR" (cdr (assoc "REGIME" g)))) "skimming")
           (HT:Near (cdr (assoc "VALOR" (cdr (assoc "ENERGIA_RESIDUAL" g)))) 4.838274 1e-3)
           (HT:Near (cdr (assoc "VALOR" (cdr (assoc "ALTURA_LAMINA" g)))) 0.427815 1e-4)
           (HT:Near (cdr (assoc "VALOR" (cdr (assoc "VELOCIDADE" g)))) 9.34983 1e-3)
           (assoc "FROUDE" g) (assoc "AVISOS" g)))
    (HT:Check "ESS:Regime: S/l fora de 0.05 a 1.43 -> ERRO; S/l = 0.08 usa o limite de Chanson (nappe/transicao)"
      (and (assoc "ERRO" (ESS:Regime 0.02 1.0 0.2)) (assoc "ERRO" (ESS:Regime 2.0 1.0 0.2))
           (equal (cdr (assoc "TIPO" (ESS:Regime 0.4 5.0 0.2))) "nappe")
           (equal (cdr (assoc "TIPO" (ESS:Regime 0.4 5.0 0.6))) "transicao")))
  )
)

(defun HT:Run (/ r hits n antigos hid hid2 res defs rg)
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
        (HT:Check "ETQ:_CampoR: campos por cenario (atalhos, GRUPO.CAMPO, INPUT, grupo sozinho)"
          (progn
            (setq rg '(("TIPO" . "bacia") ("NOME" . "B1") ("ATRIB" ("C" . 0.6)) ("CARACT" ("AREA" . 120000.0))
                       ("RESULT" ("TR10" ("CENARIO" ("TR" . 10.0))
                                         ("TC" ("VALOR" . 14.2))
                                         ("VAZAO" ("VALOR" . 3.123) ("METODO" . "racional") ("TC" . 18.5)
                                                  ("INPUT" ("CN" . 80.0)))
                                         ("ENTRADA" ("VALOR" . 1.5) ("TC" . 9.0))
                                         ("ALTURA_LAMINA" ("VALOR" . 0.09))))))
            (and (HT:Near (atof (ETQ:_CampoR nil rg "QP" "TR10")) 3.123 1e-6)
                 (HT:Near (atof (ETQ:_CampoR nil rg "TC" "TR10")) 18.5 1e-6)
                 (HT:Near (atof (ETQ:_CampoR nil rg "TCP" "TR10")) 14.2 1e-6)
                 (HT:Near (atof (ETQ:_CampoR nil rg "TR" "TR10")) 10.0 1e-6)
                 (HT:Near (atof (ETQ:_CampoR nil rg "E.QP" "TR10")) 1.5 1e-6)
                 (HT:Near (atof (ETQ:_CampoR nil rg "entrada.tc" "TR10")) 9.0 1e-6)
                 (HT:Near (atof (ETQ:_CampoR nil rg "ALTURA_LAMINA" "TR10")) 0.09 1e-6)
                 (HT:Near (atof (ETQ:_CampoR nil rg "VAZAO.VALOR" "TR10")) 3.123 1e-6)
                 (HT:Near (atof (ETQ:_CampoR nil rg "CN" "TR10")) 80.0 1e-6)
                 (HT:Near (atof (ETQ:_CampoR nil rg "C" "TR10")) 0.6 1e-6)
                 (equal (ETQ:_CampoR nil rg "METODO" "TR10") "racional")
                 (equal (ETQ:_CampoR nil rg "CENARIO" "TR10") "TR10")
                 (equal (ETQ:_CampoR nil rg "NOME" "TR10") "B1")
                 (HT:Near (atof (ETQ:_CampoR nil rg "AREA" "TR10")) 12.0 1e-6))))
        (HT:Check "ETQ:_CenarioR: preferido, senao o em uso, senao o ultimo; sem resultado -> nil"
          (and (equal (ETQ:_CenarioR '(("A" ("X")) ("B" ("X"))) "A") "A")
               (equal (ETQ:_CenarioR '(("A" ("X")) ("B" ("X"))) "ZZZ") (if (assoc (OBJ:CenarioAtual) '(("A") ("B"))) (OBJ:CenarioAtual) "B"))
               (null (ETQ:_CenarioR nil "A"))))
        (HT:Check "ETQ:_GC: grupo.campo, E = ENTRADA, grupo sozinho = VALOR, inexistente = nil"
          (and (equal (ETQ:_GC '(("VAZAO" ("VALOR" . 2.0) ("TC" . 5.0))) "vazao.tc") 5.0)
               (equal (ETQ:_GC '(("ENTRADA" ("VALOR" . 1.0))) "E") 1.0)
               (null (ETQ:_GC '(("VAZAO" ("VALOR" . 2.0))) "TC.VALOR"))))
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
  (setq r (append r (HT:RunObsoleto)))
  (if (and (HYDRO:Has "tubo-obj") (HYDRO:Has "secao-tubo")) (setq r (append r (HT:RunTubo))))
  (if (HYDRO:Has "escada-obj") (setq r (append r (HT:RunEscada))))
  (if (and (HYDRO:Has "tipo-estrutura") (HYDRO:Has "estrutura-dissipador") (HYDRO:Has "dissipacao"))
    (setq r (append r (HT:RunDissipador))))
  (if (and (HYDRO:Has "tipo-estrutura") (HYDRO:Has "estrutura-dissipador") (HYDRO:Has "dissipacao-usbr") (HYDRO:Has "dissipacao-enrocamento"))
    (setq r (append r (HT:RunBaciasDissipacao))))
  (if (HYDRO:Has "escada-siscooh") (setq r (append r (HT:RunEscadaSiscooh))))
  (if (and (HYDRO:Has "tipo-estrutura") (HYDRO:Has "estrutura-passagem") (HYDRO:Has "estrutura-boca-lobo") (HYDRO:Has "captacao"))
    (setq r (append r (HT:RunEstrutura))))
  (if (HYDRO:Has "ligacao-visual-view") (setq r (append r (HT:RunLigVisual))))
  (if (HYDRO:Has "secao-tubo-view") (setq r (append r (HT:RunTuboView))))

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
