(let ((new-desc iobjstr))
  (do
   (settaskperms player)
   (setprop self "description" new-desc)
   (player:tell "Description of " self " changed to \"" new-desc "\"")))
