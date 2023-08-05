(let ((items self.items))
  (do
   (setprop self "items" (push items dobj))
   (player:tell "Added.")))
