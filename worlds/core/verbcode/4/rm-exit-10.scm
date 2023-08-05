(do
 (settaskperms player)
 (let ((new-exit (get args 0))
       (exits self.exits))
   (setprop self "exits" (setremove exits new-exit))))
