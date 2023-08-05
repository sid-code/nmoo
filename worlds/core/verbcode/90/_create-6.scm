(let ((new-parent (get args 0))
      (new-owner  (get args 1 player)))
  (do
   (settaskperms caller)
   (let ((created (self:_recreate new-parent)))
     (if (nil? created)
         (err E_QUOTA "temporary error: could not create object")
         created))))
