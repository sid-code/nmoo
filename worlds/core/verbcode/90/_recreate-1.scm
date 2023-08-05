(let ((cperms     (callerperms))
      (new-parent (get args 0 #1))
      (new-owner  (get args 1 cperms)))
  (cond
   ((not (or (= cperms new-owner) (= 0 (level new-owner))))
    (err E_PERM (cat "cannot set new owner to " 
                     new-owner
                     " (insufficient privileges")))
   ((not (valid new-parent))
    (err E_ARGS (cat new-parent " is not a valid object.")))
   ((not (playerflag new-owner))
    (err E_ARGS (cat ($ new-owner) " is not a player.")))
   ((not new-parent.fertile)
    (err E_PERM (cat new-parent " is not fertile.")))
   ((and (not (= new-owner new-parent.owner))
         (not (= 0 (level new-owner)))
         (not (= 0 (level cperms))))
    (err E_PERM (cat new-owner " cannot create child of " new-parent)))
   ((call-cc (lambda (return)
               (do
                (map (lambda (potential)
                       (if (and (= potential.owner $garbageman)
                                (= (parent potential) $garbage)
                                (= 0 (len (children potential))))
                           (call return ((self:setup-toad potential
                                                         new-parent
                                                         new-owner)))
                           nil))
                     
                     self.contents)
                (err E_QUOTA (cat "cannot find any garbage to recreate")))))))) ; Couldn't find anything
