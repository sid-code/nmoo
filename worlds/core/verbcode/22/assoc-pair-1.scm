;;; (:assoc-pair assoclist key default=nil)
;;; Searches in `assoclist` for `(key  any-value)` and returns this pair
;;; If not found, returns `default` (which defaults to nil)


;;; Note: if the "pair" contains more than two values, any extra values are
;;; ignored and the whole thing is still returned.


(let ((assoclist (get args 0))
      (key       (get args 1))
      (default   (get args 2 nil)))
  (call-cc (lambda (return)
             (do
              (map (lambda (pair)
                     (if (and (istype pair "list")
                              (<= 2 (len pair)))
                         (if (= key (get pair 0))
                             (return pair)
                             nil)
                         nil))
                   assoclist)
              default))))
