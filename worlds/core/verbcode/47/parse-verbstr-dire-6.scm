(let ((parse-result (verbcall self "parse-verbstr" args)))
  (cond
   ((istype parse-result "str") (err E_ARGS parse-result))
   ((istype parse-result "list") parse-result)
   ((err E_ARGS "something went terribly wrong. $verbutils:parse-verbstr was expected to return a str or list but returned instead " parse-result))))
