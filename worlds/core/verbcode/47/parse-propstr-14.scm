(let ((str (get args 0))
      (result-from-plumbing 
       ($verbutils:parse-propstr-plumbing str))
      (result-code (get result-from-plumbing 0))
      (result-value (get result-from-plumbing 1)))
  (cond
   ((= result-code 1)
    (cat "Your property string is malformed. The correct "
         "syntax is simply <object>.<property>"))
   ((= result-code 2)
    (cat "The object " (get result-value 0) " could not be "
         "found."))
   ((= result-code 0) result-value)
   ((cat "$verbutils:parse-propstr-plumbing returned an invalid "
         "error code: " result-code))))
