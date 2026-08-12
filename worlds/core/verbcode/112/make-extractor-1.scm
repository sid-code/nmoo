(let (;; Given some kind of destructuring list, return the special pattern kind or nil if
      ;; it's not a special pattern.  Special patterns are lists with symbol for their first
      ;; element,
      ;; whose name starts with &.
      ;; For example:
      ;;   (&default x 10)   ; => 'default
      ;;   (&rest xs)        ; => 'rest
      ;;   (&foobar a b c)   ; => 'foobar
      ;;   (foo bar)         ; => nil
      (special-pattern
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

      ;; See comment above the `min-len` let-binding in `make-let-forms-list`.
      (min-len-contribution
       (lambda (pattern)
         (if (istype pattern "list")
             (let ((spec (special-pattern pattern)))
               (get (tget special-table spec '()) 1 1))
             1)))

      (make-let-forms-list
       (lambda (pattern-list argvar path)
         (let (;; If the argument variable we're destructuring from is not a simple scalar value;
               ;; i.e. it will probably evaluate to something and potentially have side-effects,
               ;; we need to bind it to a name. To test for this, we check if it's a list.
               (need-alias (istype argvar "list"))
               ;; To generate a good unique variable, we need to include the path of this
               ;; destructurer. For example, in the following destructurer:
               ;; (a (b (c d e) f))
               ;; The symbol c has path (1 1 0) since it's the element at index 0 of the element at
               ;; index of the element at index 1 of the extractor.
               (var (if need-alias (symbol (cat "__EXTRACTOR__" ($strutils:join path "_"))) argvar))
               (tmpdecl (if need-alias `((,var ,argvar)) '()))
               ;; If there aren't enough elements in the destructuring list, we need to throw E_BOUNDS.
               ;; To find this out, we calculate the minimum number of elements needed in the result
               ;; set by simply counting all the non-special destructuring forms in the provided
               ;; destructuring list.
               (min-len (fold-right (lambda (count next)
                                      (+ count (min-len-contribution next)))
                                    0
                                    pattern-list))
               (min-len-check `((__MIN_LEN_CHECK__
                                 (cond
                                  ((not (istype ,argvar "list"))
                                   ;; Quirky to return E_BOUNDS here but that's how we're signaling a
                                   ;; destructuring failure.
                                   (err E_BOUNDS
                                        (cat "expected an argument of type list, got " ,argvar)))
                                  ((> ,min-len (len ,argvar))
                                   (err E_BOUNDS
                                        (cat "expected at least " ,min-len
                                             " elements, instead only got " (len ,argvar))))
                                  ('everything-is-fine))))))
           (cat
            min-len-check
            tmpdecl
            (call cat (map (lambda (i)
                             (make-let-forms (get pattern-list i) `(get ,var ,i) (cat path (list i))))
                           (range 0 (- (len pattern-list) 1))))))))

      (make-let-forms-default
       (lambda (args argvar _path)
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
                   `((,var ,argvar))))))))

      (make-let-forms-rest
       (lambda (args argvar _path)
         (begin
           (unless (= 1 (len args))
             (err E_ARGS (cat "&rest needs exactly 1 argument")))
           (let ((var (get args 0))
                 (unif ($codeutils:unify '((&literal get) argvar idx) argvar (lambda (a1 a2 a3 a4) nil))))
             (if unif
                 (let ((innerargvar ($listutils:assoc unif 'argvar))
                       (idx ($listutils:assoc unif 'idx)))
                   `((,var ,(if (= 0 idx) innerargvar `(slice ,innerargvar ,(- idx 1))))))
                 `((,var ,argvar)))))))

      (make-let-forms-literal
       (lambda (args argvar _path)
         (begin
           (unless (= 1 (len args))
             (err E_ARGS (cat "&literal needs exactly 1 argument")))
           (let ((expected (get args 0)))
             `((__LITERAL_CHECK__
                (unless (= ,argvar ,expected)
                  (err E_BOUNDS
                       (cat "expected " ,expected
                            " but instead got " ,argvar)))))))))
      (special-table
       (table ('default (list make-let-forms-default 0))
              ('rest    (list make-let-forms-rest    0))
              ('literal (list make-let-forms-literal 1))))

      (make-let-forms-special
       (lambda (special-kind args argvar path)
         (let ((special-fn (get (tget special-table special-kind ()) 0 nil)))
           (when (nil? special-fn)
             (err E_ARGS (cat "Invalid extractor special kind: " ($ special-kind))))
           (special-fn args argvar path))))

      (make-let-forms
       (lambda (pattern argvar path)
         (cond
          ((istype pattern "sym") `((,pattern ,argvar)))
          ((istype pattern "list")
           (let ((sp (special-pattern pattern)))
             (if (nil? sp)
                 (make-let-forms-list pattern argvar path)
                 (make-let-forms-special sp (tail pattern) argvar path))))
          ((err E_ARGS (cat "Invalid type for pattern: " ($ pattern) ". Need symbol or list.")))))))

  (call make-let-forms (cat args '(()))))
