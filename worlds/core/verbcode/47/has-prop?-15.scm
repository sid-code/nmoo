;;; ($verbutils:has-prop? obj prop-name)

(let ((obj (get args 0))
      (objparent (parent obj))
      (prop-name (get args 1)))
  (or (< -1 (in (props obj) prop-name))
      (if (= obj objparent)
          nil
          (verbcall self verb (list objparent prop-name)))))
