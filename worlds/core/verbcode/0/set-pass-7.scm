(let
  ((target (get args 0))
   (newpass (get args 1)))
  
  (if (or (= player target) (= 0 (level player)))
      (let ((salt (gensalt)))
        (do
          (setprop target "password-salt" salt)
          (setprop target "password-hash" (phash newpass salt))))
      (err E_PERM "only wizards can change passwords of other characters")))
