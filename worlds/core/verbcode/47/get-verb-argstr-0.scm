(let ((obj (get args 0))
      (verbdesc (get args 1)))

 (call cat (map (lambda (str) (fit str 6)) (getverbargs obj verbdesc))))
