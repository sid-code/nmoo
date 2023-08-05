(do
 (settaskperms caller)
 (let ((new-room (self:_create $room)))
   (do
    (setprop new-room "name" (get args 0))
    new-room)))
