(let ((obj (get args 0)))
  (if (= obj (parent obj))
      (verbs obj)
      (cat (verbs obj) (self:all-verbs (parent obj)))))
