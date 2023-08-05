(do
 (settaskperms caller)
 (let ((source (get args 0))
       (dest (get args 1))
       (exit (get args 2)))
   (do
    (source:rm-exit exit)
    (dest:rm-entrance exit))))
