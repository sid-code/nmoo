(if (not (= caller self))  ; this verb can only be called by $recycler
    (err E_PERM (cat "Cannot call " self ":setup-toad"))
    (let ((potential  (get args 0))
          (new-parent  (get args 1))
          (new-owner (get args 2)))
      (do
       (setprop potential "owner" new-owner)
       (move potential $nowhere)
       (self:add-orphan potential)
       ($buildutils:recreate potential new-parent)
       (self:remove-orphan potential)
       potential)))
