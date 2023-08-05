(let ((html (get args 0))
      (escape-quotes (get args 1 0)))
  ;; TODO: implement quote escaping
  (gsub (gsub (gsub html "&" "&amp;") "<" "&lt;") ">" "&gt;"))
