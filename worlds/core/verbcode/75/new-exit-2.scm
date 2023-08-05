(do
 (let ((exit-dir (get args 0))
       (exit-src (get args 1))
       (exit-dest (get args 2))
       (new-exit (self:_create $exit)))
   (do
    (setprop new-exit "name" (cat "exit to " exit-dest))
    (setprop new-exit "dir" exit-dir)
    (setprop new-exit "source" exit-src)
    (setprop new-exit "destination" exit-dest)
    new-exit)))
