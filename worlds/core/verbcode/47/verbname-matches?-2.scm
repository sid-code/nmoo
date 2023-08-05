(let ((name  (get args 0))
      (str   (get args 1))
      (names (split name))
      (matches
       ($listutils:filter (lambda (vname) ($verbutils:name-matches? vname str))
                  names)))
  (> (len matches) 0))
