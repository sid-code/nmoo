(let ((obj   (get args 0))
      (name  (get args 1))
      (arg-spec (get args 2 nil))
      (verb-list (verbs obj))
      (num-verbs (len verb-list)))
  (get ($listutils:filter (lambda (idx)
                    (let ((verb-name (get verb-list idx)))
                      (and
                       ($verbutils:verbname-matches? verb-name name)
                       (if (nil? arg-spec)
                           1
                           (= arg-spec (getverbargs obj idx))))))
                    
                  (range 0 (- num-verbs 1)))
       0
       nil))
