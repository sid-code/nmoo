;;; (:get optlist option default-value=nil)
;;; Returns the value of `option` from `optlist`.
;;; If the option does not exist, returns `default-value` which
;;;  defaults to nil

(let ((optlist (get args 0))
      (option  (get args 1))
      (default (get args 2 nil)))
  ($listutils:assoc optlist option default))
