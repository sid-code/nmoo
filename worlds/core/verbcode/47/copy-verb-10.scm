(let ((obj1  (get args 0))
      (vname (get args 1))
      (obj2  (get args 2))
      (dump  ($verbutils:dump-verb obj1 vname)))
  (do
   ($verbutils:add-dumped-verb obj2 dump)))
