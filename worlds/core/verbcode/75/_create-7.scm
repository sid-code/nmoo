(do 
 (settaskperms caller) 
 (if (self:build-option "bi-create")
     (verbcall $quotautils "bi-create" args)
     (verbcall $recycler verb args)))
