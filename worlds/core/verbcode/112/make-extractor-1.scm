(let ((special-pattern
       (lambda (pattern-list)
         (call-cc
          (lambda (return)
            (let ((fst (head pattern-list)))
              (when (nil? fst) (return nil))
              (unless (istype fst "sym") (return nil))
              (let ((special-sym (symbol-name fst)))
                ;; Symbol is guaranteed to have a non-empty name.
                (unless (= "&" (substr special-sym 0 0)) (return nil))
                (when (= 1 (len special-sym))
                  (err E_ARGS "& alone cannot be used as a variable."))
                (symbol (substr special-sym 1 -1))))))))

      (make-let-forms-list
       (lambda (pattern-list argvar)
         (let ((need-alias (istype argvar "list"))
               (var (if need-alias (gensym "__EXTRACTOR__") argvar))
               (tmpdecl (if need-alias `((,var ,argvar)) '())))
           (cat tmpdecl (map (lambda (i)
                               (make-let-forms (get pattern-list i) `(get ,var ,i)))
                             (range 0 (- (len pattern-list) 1)))))))

      (make-let-forms-special
       (lambda (special-kind args argvar)
         (cond
          ((= special-kind 'default)
           (begin
             (unless (= 2 (len args))
               (err E_ARGS (cat "&default needs exactly 2 arguments: variable-name and default-value.")))
             (let ((var (get args 0))
                   (default (get args 1)))
               (unless (istype var "sym")
                 (err E_ARGS (cat "Expected a symbol, got " ($var) ".")))
               ;; If our target is a (get var index) expression, we can inject a
               ;; default parameter in there.
               (let ((unif ($codeutils:unify '((&literal get) argvar idx) argvar (lambda (a1 a2 a3 a4) nil))))
                 (if unif
                     `((,var (get ,($listutils:assoc unif 'argvar) ,($listutils:assoc unif 'idx) ,default)))
                     `((,var ,argvar)))))
             ))

          ((err E_ARGS (cat "Invalid extractor special kind: " ($ special-kind)))))))

      (make-let-forms
       (lambda (pattern argvar)
         (cond
          ((istype pattern "sym") `(,pattern ,argvar))
          ((istype pattern "list")
           (let ((sp (special-pattern pattern)))
             (if (nil? sp)
                 (make-let-forms-list pattern argvar)
                 (make-let-forms-special sp (tail pattern) argvar))))
          ((err E_ARGS (cat "Invalid type for pattern: " ($ pattern) ". Need symbol or list.")))))))
  (make-let-forms '((&default x y) (a (&default b 4) c) lol) 'args))

($codeutils:unify '(a b c d) '(1 2 3) list)
