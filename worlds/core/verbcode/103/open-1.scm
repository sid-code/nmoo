(let ((capname ($strutils:capitalize (self:name))))
  (if self.open
      (player:tell capname " is already open.")
      (call-cc (lambda (return)
        (do
         (if self.locked
             (let ((unlock-attempt self.unlock ))
               (if unlock-attempt ; successful unlock
                   (player:tell unlock-attempt)
                   (call return
                         (player:tell capname " is locked and you can't unlock it."))))
             nil)
         (setprop self "open" 1)
         (player:tell capname " is open now."))))))
