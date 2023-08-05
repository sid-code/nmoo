;;; (:set optist option value=1) => new optlist
;;; sets the option in optlist to value which defaults to 0.

(let ((optlist (get args 0))
      (option  (get args 1))
      (value   (get args 2 0)))
  ($listutils:assoc-set optlist option value))
