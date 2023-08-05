(settaskperms caller)
(let ((contents (file-contents self.asset-path)))
  (setprop self "data" contents))
