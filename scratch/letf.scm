(do
(define safe-get
  (lambda (perhaps-not-a-list idx default)
    (if (and (istype perhaps-not-a-list "list") (> (len perhaps-not-a-list) idx))
        (get perhaps-not-a-list idx)
        default)))

(define unify
  (lambda (target form)
    (cond
     ((istype target "sym") (list (list target form)))
     ((istype target "list") (unify-list target form))
     ((= target form) (list))
     ((list -1 target)))))

(define unify-list
  (lambda (target-list form)
    (cond
     ((not (istype form "list")) -1)
     ((= 0 (len target-list)) (if (= 0 (len form)) nil -1))
     ((let ((target-head  (get target-list 0))
            (target-tail (slice target-list 1))
            (form-tail   (try (slice form 1) nil)))

        (if (istype target-head "list")
            ;; first check for special list unification forms
            ;;   (splat sym)
            (let ((sftype (safe-get target-head 0 nil)))
              (cond
               ((and (= 2 (len target-head)) (= sftype 'splat))
                (if (= 0 (len target-tail))
                    (list (list (get target-head 1) form))
                    (err E_ARGS "only the last target can be a splat")))
               ((err E_ARGS (cat "invalid special unification form" target-head)))))
            (if (= 0 (len form))
                -1
                (let ((form-head (get form 0))
                      (sub-unification-head (unify target-head form-head)))
                  (if (= -1 (safe-get sub-unification-head 0 sub-unification-head))
                      -1
                      (let ((sub-unification-tail (unify target-tail form-tail)))
                        (if (= nil sub-unification-tail)
                            sub-unification-head
                            (if (= -1 sub-unification-tail)
                                -1
                                (cat sub-unification-head sub-unification-tail)))))))))))))

(define make-extractor
  (lambda (target-list   ; the argument format specification
           args-variable ; the symbol that will hold the arg list
           name)         ; the name to be reported in case of error
    (map (lambda (target-index)
           (let ((target (get target-list target-index))
                 (value-form (list 'get args-variable target-index)))
             (cond
              ((istype target "sym")
               (list target value-form))
              ((istype target "list")
               (cond
                ((and (= 2 (len target))
                      (= 'splat (get target 0))
                      (istype (get target 1) "sym"))
                 (list (get target 1) ; the symbol being bound
                       (list 'slice args-variable target-index))) ; the value
                ((and (= 3 (len target))
                      (= 'default (get target 0))
                      (istype (get target 1) "sym"))
                 (list (get target 1) ; the symbol being bound
                       (list 'get args-variable target-index (get target 2)))) ; the value
                ((make-extractor target value-form name))))
              ((err E_ARGS (cat "invalid target form " target))))))
         (range 0 (- (len target-list) 1)))))

(define-syntax letf
  (lambda (code)
    (let ((argspec (get code 0))
	  (data    (get code 1))
	  (forms   (slice code 2))) 
      `(let ,(call make-extractor (list argspec data 'letf))
	 ,(unshift forms 'do)))))

(letf (a (b c) (splat d)) (1 2 3 4 5 6 7 8)

      a)
)
