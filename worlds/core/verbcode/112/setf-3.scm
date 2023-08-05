(if (not (= (len args) 2))
    (err E_ARGS "setf takes exactly 2 arguments")
    (let ((loc     (get args 0))
          (new-val (get args 1)))
      (cond
       ((istype loc "sym")
        (err E_ARGS "cannot setf an arbitrary symbol"))
       ((or (not (istype loc "list") (> (len loc) 1)))
        (err E_ARGS (cat "what could you possibly hope setf'ing " loc " would achieve?")))
       ((let ((fst
