(let ((token (get args 0)))
  (setprop self "sessions" (tdelete self.sessions token)))
