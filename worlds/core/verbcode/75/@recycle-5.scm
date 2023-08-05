(do
 (settaskperms caller)
 (if (= caller dobj)
     (player:tell "Don't recycle yourself.")
     (let ((name ($o dobj)))
       (do
        ($recycler:_recycle dobj)
        (player:tell name " recycled.")))))
