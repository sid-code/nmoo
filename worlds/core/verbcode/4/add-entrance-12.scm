(do
 (settaskperms player)
 (let ((new-entrance (get args 0))
       (entrances self.entrances))
   (setprop self "entrances" (setadd entrances new-entrance))))
