(let ((str (get args 0)))
  (if (= 0 (len str))
      str
      (let ((first (substr str 0 0))
            (rest (substr str 1 -1)))
        (cat (upcase first) rest))))
