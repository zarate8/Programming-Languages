#lang plai-typed
(require plai-typed/s-exp-match)

(define-type (Value 'a)
  [litV (n : 'a)]
  [closV (arg : symbol)
         (body : (ExprC 'b))
         (env : Env)])

(define-type (ExprC 'b)
  [litC (n : 'b)]
  [idC (s : symbol)]
  [plusC (l : (ExprC 'b)) 
         (r : (ExprC 'b))]
  [multC (l : (ExprC 'b))
         (r : (ExprC 'b))]
  [lamC (n : symbol)
        (body : (ExprC 'b))]
  [appC (fun : (ExprC 'b))
        (arg : (ExprC 'b))])

(define-type (Binding 'a)
  [bind (name : symbol)
        (val : (Value 'a))])

(define-type-alias Env (listof (Binding 'a)))

(define mt-env empty)
(define extend-env cons)

(module+ test
  (print-only-errors true))

;; parse ----------------------------------------
(define parse 
  : (s-expression s-expression (s-expression -> 'b) -> (ExprC 'b))               
  (lambda (s pat s-exp->)
    (cond      
      [(s-exp-match? pat s) (litC (s-exp-> s))]
      [(s-exp-match? `SYMBOL s) (idC (s-exp->symbol s))]
      [(s-exp-match? '{+ ANY ANY} s)
       (plusC (parse (second (s-exp->list s)) pat s-exp->)
              (parse (third (s-exp->list s)) pat s-exp->))]
      [(s-exp-match? '{* ANY ANY} s)
       (multC (parse (second (s-exp->list s)) pat s-exp->)
              (parse (third (s-exp->list s)) pat s-exp->))]
      [(s-exp-match? '{let {[SYMBOL ANY]} ANY} s)
       (let ([bs (s-exp->list (first
                               (s-exp->list (second
                                             (s-exp->list s)))))])
         (appC (lamC (s-exp->symbol (first bs))
                     (parse (third (s-exp->list s)) pat s-exp->))
               (parse (second bs) pat s-exp->)))]
      [(s-exp-match? '{lambda {SYMBOL} ANY} s)
       (lamC (s-exp->symbol (first (s-exp->list 
                                    (second (s-exp->list s)))))
             (parse (third (s-exp->list s)) pat s-exp->))]
      [(s-exp-match? '{ANY ANY} s)
       (appC (parse (first (s-exp->list s)) pat s-exp->)
             (parse (second (s-exp->list s)) pat s-exp->))]
      [else (error 'parse "invalid input")])))

(define (parse/num [s : s-expression]) : (ExprC 'a)
  (parse s `NUMBER s-exp->number))

(define (parse/str [s : s-expression]) : (ExprC 'a)
  (parse s `STRING s-exp->string))

(module+ test
  ;;String tests --------------------------------------------------
  (test (parse/str '"a")
        (litC "a"))
  (test (parse/str `x) ; note: backquote instead of normal quote
        (idC 'x))
  (test (parse/str '{+ "b" "a"})
        (plusC (litC "b") (litC "a")))
  (test (parse/str '{* "c" "d"})
        (multC (litC "c") (litC "d")))
  (test (parse/str '{+ {* "c" "d"} "e"})
        (plusC (multC (litC "c") (litC "d"))
               (litC "e")))
  (test (parse/str '{let {[x {+ "a" "b"}]}
                      y})
        (appC (lamC 'x (idC 'y))
              (plusC (litC "a") (litC "b"))))
  (test (parse/str '{lambda {x} "g"})
        (lamC 'x (litC "g")))
  (test (parse/str '{double "g"})
        (appC (idC 'double) (litC "g")))
  (test/exn (parse/str '{{+ "a" "b"}})
            "invalid input")
  (test/exn (parse/str '1)
            "invalid input")
  ;;Number tests --------------------------------------------------
  (test (parse/num '2)
        (litC 2))
  (test (parse/num `x) ; note: backquote instead of normal quote
        (idC 'x))
  (test (parse/num '{+ 2 1})
        (plusC (litC 2) (litC 1)))
  (test (parse/num '{* 3 4})
        (multC (litC 3) (litC 4)))
  (test (parse/num '{+ {* 3 4} 8})
        (plusC (multC (litC 3) (litC 4))
               (litC 8)))
  (test (parse/num '{let {[x {+ 1 2}]}
                      y})
        (appC (lamC 'x (idC 'y))
              (plusC (litC 1) (litC 2))))
  (test (parse/num '{lambda {x} 9})
        (lamC 'x (litC 9)))
  (test (parse/num '{double 9})
        (appC (idC 'double) (litC 9)))
  (test/exn (parse/num '{{+ 1 2}})
            "invalid input")
  (test/exn (parse/num '"a")
            "invalid input"))

;; interp ----------------------------------------
(define interp : ((ExprC 'b)
                  Env
                  'plus
                  'mult
                  -> (Value 'a))
  (lambda (a env p m)
    (type-case (ExprC 'b) a
      [litC (n) (litV n)]
      [idC (s) (lookup s env)]
      [plusC (l r) (p (interp l env p m) (interp r env p m))]                 
      [multC (l r) (m (interp l env p m) (interp r env p m))]
      [lamC (n body)
            (closV n body env)]
      [appC (fun arg) (type-case (Value 'a) (interp fun env p m)
                        [closV (n body c-env)
                               (interp body
                                       (extend-env
                                        (bind n
                                              (interp arg env p m))
                                        c-env) p m)]
                        [else (error 'interp "not a function")])])))

(define (interp/num [a : (ExprC 'a)] [env : Env]) : (Value 'a)
  (interp a env num+ num*))

(define (interp/str [a : (ExprC 'a)] [env : Env]) : (Value 'a)
  (interp a env str+ str*))


(module+ test
  
  ;; STRING TESTS ----------------------------------------  
  (test (interp/str (parse/str '"b") mt-env)
        (litV "b"))
  (test/exn (interp/str (parse/str `x) mt-env)
            "free variable")
  (test (interp/str (parse/str `x) 
                    (extend-env (bind 'x (litV "g")) mt-env))
        (litV "g"))
  (test (interp/str (parse/str '{+ "b" "a"}) mt-env)
        (litV "ba"))
  (test (interp/str (parse/str '{* "b" "a"}) mt-env)
        (litV "a"))
  (test (interp/str (parse/str '{+ {* "a" "b"} {+ "c" "d"}})
                    mt-env)
        (litV "bcd"))
  (test (interp/str (parse/str '{lambda {x} {+ x x}})
                    mt-env)
        (closV 'x (plusC (idC 'x) (idC 'x)) mt-env))
  (test (interp/str (parse/str '{let {[x "e"]}
                                  {+ x x}})
                    mt-env)
        (litV "ee"))
  (test (interp/str (parse/str '{let {[x "e"]}
                                  {let {[x {+ "a" x}]}
                                    {+ x x}}})
                    mt-env)
        (litV "aeae"))
  (test (interp/str (parse/str '{let {[x "e"]}
                                  {let {[y "f"]}
                                    x}})
                    mt-env)
        (litV "e"))
  (test (interp/str (parse/str '{{lambda {x} {+ x x}} "f"})
                    mt-env)
        (litV "ff"))

  (test/exn (interp/str (parse/str '{"a" "b"}) mt-env)
            "not a function")
  (test/exn (interp/str (parse/str '{+ "a" {lambda {x} x}}) mt-env)
            "not a literal")
  (test/exn (interp/str (parse/str '{let {[bad {lambda {x} {+ x y}}]}
                                      {let {[y "e"]}
                                        {bad "b"}}})
                        mt-env)
            "free variable")
  
  ;; NUMBER TESTS ----------------------------------------
  (test (interp/num (parse/num '2) mt-env)
        (litV 2))
  (test/exn (interp/num (parse/num `x) mt-env)
            "free variable")
  (test (interp/num (parse/num `x) 
                    (extend-env (bind 'x (litV 9)) mt-env))
        (litV 9))
  (test (interp/num (parse/num '{+ 2 1}) mt-env)
        (litV 3))
  (test (interp/num (parse/num '{* 2 1}) mt-env)
        (litV 2))
  (test (interp/num (parse/num '{+ {* 2 3} {+ 5 8}})
                    mt-env)
        (litV 19))
  (test (interp/num (parse/num '{lambda {x} {+ x x}})
                    mt-env)
        (closV 'x (plusC (idC 'x) (idC 'x)) mt-env))
  (test (interp/num (parse/num '{let {[x 5]}
                                  {+ x x}})
                    mt-env)
        (litV 10))
  (test (interp/num (parse/num '{let {[x 5]}
                                  {let {[x {+ 1 x}]}
                                    {+ x x}}})
                    mt-env)
        (litV 12))
  (test (interp/num (parse/num '{let {[x 5]}
                                  {let {[y 6]}
                                    x}})
                    mt-env)
        (litV 5))
  (test (interp/num (parse/num '{{lambda {x} {+ x x}} 8})
                    mt-env)
        (litV 16))

  (test/exn (interp/num (parse/num '{1 2}) mt-env)
            "not a function")
  (test/exn (interp/num (parse/num '{+ 1 {lambda {x} x}}) mt-env)
            "not a literal")
  (test/exn (interp/num (parse/num '{let {[bad {lambda {x} {+ x y}}]}
                                      {let {[y 5]}
                                        {bad 2}}})
                        mt-env)
            "free variable")
  )

;; num+ and num* ----------------------------------------
(define lit-op : (('a 'a -> 'a)
                  (Value 'a)
                  (Value 'a)
                  -> (Value 'a))
  (lambda (op l r)
    (cond
     [(and (litV? l) (litV? r))
      (litV (op (litV-n l) (litV-n r)))]
     [else
      (error 'interp "not a literal")])))

(define (string-mult [a : string] [b : string])
  (foldl (lambda (c r) (string-append b r))
         ""
         (string->list a)))

(define (str+ [l : (Value 'a)] [r : (Value 'a)]) : (Value 'a)
  (lit-op string-append l r))

(define (str* [l : (Value 'a)] [r : (Value 'a)]) : (Value 'a)
  (lit-op string-mult l r))

(define (num+ [l : (Value 'a)] [r : (Value 'a)]) : (Value 'a)
  (lit-op + l r))
(define (num* [l : (Value 'a)] [r : (Value 'a)]) : (Value 'a)
  (lit-op * l r))

;(define (lit+ [l : (Value 'a)] [r : (Value 'a)]) : (Value 'a)
 ; (cond
  ;  [ (lit-op string-append l r)])

(module+ test
  (test (str+ (litV "abc") (litV "de"))
        (litV "abcde"))
  (test (str* (litV "abc") (litV "de"))
        (litV "dedede"))
  (test (num+ (litV 1) (litV 2))
        (litV 3))
  (test (num* (litV 2) (litV 3))
        (litV 6))
  )

;; lookup ----------------------------------------
(define lookup : (symbol Env -> (Value 'a))
  (lambda (n env)
    (cond
     [(empty? env) (error 'lookup "free variable")]
     [else (cond
            [(symbol=? n (bind-name (first env)))
             (bind-val (first env))]
            [else (lookup n (rest env))])])))

(module+ test

 (test/exn (lookup 'x mt-env)
            "free variable")
  (test (lookup 'x (extend-env (bind 'x (litV "f")) mt-env))
        (litV "f"))
  (test (lookup 'x (extend-env
                    (bind 'x (litV "g"))
                    (extend-env (bind 'x (litV "f")) mt-env)))
        (litV "g"))
  (test (lookup 'y (extend-env
                    (bind 'x (litV "g"))
                    (extend-env (bind 'y (litV "f")) mt-env)))
        (litV "f"))
  ;; String tests ----------------------------------------
  (test/exn (lookup 'x mt-env)
            "free variable")
  (test (lookup 'x (extend-env (bind 'x (litV 8)) mt-env))
        (litV 8))
  (test (lookup 'x (extend-env
                    (bind 'x (litV 9))
                    (extend-env (bind 'x (litV 8)) mt-env)))
        (litV 9))
  (test (lookup 'y (extend-env
                    (bind 'x (litV 9))
                    (extend-env (bind 'y (litV 8)) mt-env)))
        (litV 8)))