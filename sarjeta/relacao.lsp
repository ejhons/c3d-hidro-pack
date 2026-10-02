(setq __app-name__ "DREN-SARJETA")
(setq __def-code__ 1005)

;Criar aplicativo
(defun sarj-cria-app()
  (regapp __app-name__)
)


;Capturar handle de um objeto
(defun get-handle (en / handle)
  (if en
    (cond
      ((= (type en) 'ENAME) (setq handle (vla-get-Handle (vlax-ename->vla-object en))))
      ((= (type en) 'VLA-OBJECT) (setq handle (vla-get-Handle (vlax-ename->vla-object en))))
      (t (setq handle nil))
      );cond
    (setq handle nil);else
    );if
  handle
  );defun


;Relacionar dois objetos
(defun set-xdata (en codigo valor app-name / )
  (if (not app-name) (setq app-name __app-name__))
  (entmod
    (append
      (entget en)
      (list
	(list -3
	      (list app-name
		    (cons codigo valor)
		    );list
	      );list
	);list
      );append
    );entmod
 );defun

;Retorna uma lista com a cole��o dos XData da aplica��o passada.
;Se app-name for nil, usa o valor default da aplica��o definido em __app-name__
(defun get-xdata-collection(en app-name / )
  (if (not app-name) (setq app-name __app-name__))
  (cdr (assoc app-name (cdr (assoc -3 (entget en (list app-name))))))
  )

;Retorna o valor do c�digo m=na cole��o dos XData da aplica��o passada.
;Se app-name for nil, usa o valor default da aplica��o definido em __app-name__
(defun get-xdata(en codigo app-name / )
  (if (not app-name) (setq app-name __app-name__))
  (cdr (assoc codigo (get-xdata-collection en __app-name__)))
  )
;;Remove a aplica��o de uma entidade.
;Se app-name for nil, usa o valor default da aplica��o definido em __app-name__
(defun remove-xdata-app(en app-name / dados )
  (if (not app-name) (setq app-name __app-name__))
  (setq dados (entget en  (list app-name)))
  (entmod
    (vl-remove-if
      (function
	(lambda (x)
	  (and (= (car x) -3)
	       (= (caar (cdr x)) app-name))
	  )
	)
      dados
      )
  )
  (entupd en)
  )

;Remove da aplica��o passada o primeiro dado com o c�digo passado
;Se app-name for nil, usa o valor default da aplica��o definido em __app-name__
(defun remove-xdata(en codigo app-name / dados xdata novo)
  (if (not app-name) (setq app-name __app-name__))
  
  (setq dados (entget en (list app-name)))
  (setq xdata (assoc -3 dados))
  (setq novo
    (list
      -3
      (cons app-name
        (vl-remove
          (assoc codigo (cdr (assoc __app-name__ (cdr xdata))));(assoc codigo (cdr xdata));(cons 1000 valor)
          (cdr (assoc app-name (cdr xdata)))
        )
      )
    )
  )

  (entmod
    (append
      (vl-remove xdata dados)
      (list novo)
    )
  )
  (entupd en)
)

;Remove da aplica��o passada, par exato '(codigo . valor) passado com par�metro.
;Se app-name for nil, usa o valor default da aplica��o definido em __app-name__
(defun remove-xdata-by-valor(en valor app-name / dados xdata novo)
  (if (not app-name) (setq app-name __app-name__))
  
  (setq dados (entget en (list app-name)))
  (setq xdata (assoc -3 dados))
  (setq novo
    (list
      -3
      (cons app-name
        (vl-remove
          valor;;(assoc codigo (cdr (assoc __app-name__ (cdr xdata))));(assoc codigo (cdr xdata));(cons 1000 valor)
          (cdr (assoc app-name (cdr xdata)))
        )
      )
    )
  )

  (entmod
    (append
      (vl-remove xdata dados)
      (list novo)
    )
  )
  (entupd en)
)
(defun get-relacionado(en1 / xdata2 handle2 en2)
  (setq xdata2 (assoc 1005 (get-xdata-collection en1 nil)))
  (setq handle2 (cdr xdata2))
  
  (handent handle2)
  )

;Estabele uma rela��o entre duas entidades
;Apenas <e1> � alterada sendo atribu�do � aplica��o padr�o um par '(1005 . <handle_en2>)
(defun relaciona-unidirecional (en1 en2 / handle1 handle2 )
  (setq handle2 (get-handle en2))
  (set-xdata en1 1005 handle2 nil)
  )

;Estabele uma rela��o entre duas entidades
;<e1> e <e2> s�o alterada sendo atribu�do � aplica��o padr�o um par '(1005 . <handle_outra_entidade>)
;� estabelecida uma rela��o 1-1
(defun relaciona-bidirecional (en1 en2 / )
  (setq handle1 (get-handle en1))
  (setq handle2 (get-handle en2))

  ;remove rela��es antigas antes de criar as novas.
  (remove-relacao-bidirecional en1)
  (remove-relacao-bidirecional en2)
  
  (set-xdata en1 1005 handle2 nil)
  (set-xdata en2 1005 handle1 nil)
  )

;Remove a rela��o apenas na entidade <e1>.
;N�o recomendado usar em entidades que funcionam com rela��es bidirecionais.
(defun remove-relacao-unidirecional (en / )
  (remove-xdata en 1005 nil)
  )


;Remove a rela��o na entidade <e1> e em sua relaciona, se existir.
(defun remove-relacao-bidirecional (en1  / xdata2 handle2 en2 )  
  (setq xdata2 (assoc 1005 (get-xdata-collection en1 nil)))
  (setq handle2 (cdr xdata2))
  (if handle2
    (progn
      (setq en2 (handent handle2))
      (if en2 (remove-xdata en2 1005 nil))
      )
    )
  
  (remove-xdata en1 1005 nil)		  
  )


;---------------------------------------------
;FUN��ES GERAIS

;Criar aplicativo
(defun xdata-cria-app(app-name)
  (if (not app-name) (setq app-name __app-name__));define o padr�o no arquivo
  (regapp __app-name__)
)

;Estabele uma rela��o entre duas entidades
;Apenas <e1> � alterada sendo atribu�do � aplica��o padr�o um par '(1005 . <handle_en2>)
(defun relaciona-unidirecional-by-code (en1 en2 code app-name / handle1 handle2 )
  (if (not app-name) (setq app-name __app-name__));define o padr�o no arquivo
  (if (not code) (setq code __def-code__));define 1005 por padr�o
  
  (setq handle2 (get-handle en2))
  (set-xdata en1 code handle2 app-name)
  )

;Estabele uma rela��o entre duas entidades
;<e1> e <e2> s�o alterada sendo atribu�do � aplica��o padr�o um par '(1005 . <handle_outra_entidade>)
;� estabelecida uma rela��o 1-1
(defun relaciona-bidirecional-by-code (en1 en2 code app-name / )
  (if (not app-name) (setq app-name __app-name__));define o padr�o no arquivo
  (if (not code) (setq code __def-code__));define 1005 por padr�o
  
  (setq handle1 (get-handle en1))
  (setq handle2 (get-handle en2))

  ;remove rela��es antigas antes de criar as novas.
  (remove-relacao-bidirecional-by-code en1 code app-name)
  (remove-relacao-bidirecional-by-code en2 code app-name)
  
  (set-xdata en1 code handle2 app-name)
  (set-xdata en2 code handle1 app-name)
  )

;Remove a rela��o apenas na entidade <e1>.
;N�o recomendado usar em entidades que funcionam com rela��es bidirecionais.
(defun remove-relacao-unidirecional-by-code (en  code app-name / )
  (if (not app-name) (setq app-name __app-name__));define o padr�o no arquivo
  (if (not code) (setq code __def-code__));define 1005 por padr�o
  
  (remove-xdata en code app-name)
  )

;Remove a rela��o na entidade <e1> e em sua relaciona, se existir.
(defun remove-relacao-bidirecional-by-code (en1 code app-name / xdata2 handle2 en2 )
  (if (not app-name) (setq app-name __app-name__));define o padr�o no arquivo
  (if (not code) (setq code __def-code__));define 1005 por padr�o
  
  (setq xdata2 (assoc code (get-xdata-collection en1 app-name)))
  (setq handle2 (cdr xdata2))
  (setq en2 (handent handle2))
  
  (remove-xdata en1 code app-name)
  (if en2 (remove-xdata en2 code app-name))		  
  )
;Remove a rela��o na entidade <e1> e em sua relaciona, se existir.
(defun remove-relacao-bidirecional-general-by-code (en1 code app-name / xdata2 handle2 en2 )
  (if (not app-name) (setq app-name __app-name__));define o padr�o no arquivo
  (if (not code) (setq code __def-code__));define 1005 por padr�o
  
  (setq xdata2 (assoc code (get-xdata-collection en1 app-name)))
  (setq handle2 (cdr xdata2))
  (if handle2
    (progn
      (setq en2 (handent handle2))
      (if en2 (remove-xdata en2 code app-name))
      )
    )
  
  (remove-xdata en1 code app-name)		  
  )

(defun get-relacionado-general(en1 code app-name / xdata2 handle2 en2)
  (if (not app-name) (setq app-name __app-name__));define o padr�o no arquivo
  (if (not code) (setq code __def-code__));define 1005 por padr�o
  
  (setq xdata2 (assoc code (get-xdata-collection en1 app-name)))
  (setq handle2 (cdr xdata2))
  
  (handent handle2)
  )
