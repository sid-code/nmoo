(do
 (settaskperms caller)
 (let ((cur-aliases self.aliases)
       (new-aliases (setadd cur-aliases iobjstr)))
   (do 
    (setprop self "aliases" new-aliases)
    (player:tell "Added alias \"" iobjstr "\" to \"" ($o self) ". "
                 "This object is now also known as " new-aliases "."))))
