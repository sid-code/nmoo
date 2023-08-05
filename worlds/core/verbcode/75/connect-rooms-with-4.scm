(do
 (settaskperms caller)
 (let ((source (get args 0))
       (dest (get args 1))
       (exit (get args 2)))
   (do
    (source:add-exit exit)
    (dest:add-entrance exit))))
