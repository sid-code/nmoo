(let ((func (get args 0))
      (high (maxobj)))
  ($listutils:countup (lambda (x)
                        (let ((o (object x)))
                          (and (valid o)
                               (func o))))
                      0
                      high))
