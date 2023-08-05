(do
 (settaskperms player)
 (let ((new-exit (get args 0))
       (exits self.exits))
   (setprop self "exits" (setadd exits new-exit))))
