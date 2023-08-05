(do
 (settaskperms caller)
 (let ((source (get args 0))
       (dest (get args 1)))
   (if (source:has-exit? self)
       (err E_ARGS (cat source " already has exit " self))
       (if (dest:has-entrance? self)
           (err E_ARGS (cat dest " already has entrance " self))
           (do
            (source:add-exit self)
            (dest:add-entrance self)
            (setprop self "source" source)
            (setprop self "destination" dest))))))
