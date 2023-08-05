;;; same as assoc-pair but returns only the second value
(let ((assoclist (get args 0))
      (key       (get args 1))
      (default   (get args 2 nil)))
  (get (self:assoc-pair assoclist key ()) 1 default))
