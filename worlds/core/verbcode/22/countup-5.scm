(let ((func (get args 0))
      (low  (get args 1))
      (high (get args 2))
      (state (call-cc (lambda (x) (list low x)))))
  (if (nil? state) ; stopping condition
      nil ; return
      (let ((idx (get state 0))
            (cont (get state 1)))
        (if (> idx high)
            (cont nil)
            (do
             (func idx)
             (cont ((+ idx 1) cont)))))))
