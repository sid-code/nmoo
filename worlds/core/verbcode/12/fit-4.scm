(let ((str (get args 0))
      (strlen (len str))
      (size (get args 1))
      (fill (get args 2 " "))
      (toolong (get args 3 "...")))

 (cond
  ((= size strlen) str)
  ((> size strlen)
   (let ((difference (- size strlen))
         (numfills (+ 1 (/ difference (len fill)))))
    (substr (cat str (repeat fill numfills)) 0 (- size 1))))
  ((< size strlen)
   (let ((pos (- size (+ 1 (len toolong)))))

    (if (> 1 pos) (substr str 0 size)
     (cat (substr str 0 pos) toolong))))
  ("empty else clause")))
