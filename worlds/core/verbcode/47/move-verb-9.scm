(let ((obj1  (get args 0))
      (vname (get args 1))
      (obj2  (get args 2)))
  (do
   ($verbutils:copy-verb obj1 vname obj2)
   (delverb obj1 vname)))
