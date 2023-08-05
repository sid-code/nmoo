(do
 (settaskperms player)
 (let ((entrance-to-remove (get args 0))
       (entrances self.entrances))
   (setprop self "entrances" (setremove entrances entrance-to-remove))))
