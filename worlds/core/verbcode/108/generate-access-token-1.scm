(let ((access-tokens self.access-tokens)
      (token ($strutils:id-gen 8))
      (who (get args 0))
      (existing-token ($listutils:assoc access-tokens who)))
  (if (nil? existing-token)
      (do
       (setprop self "access-tokens" (push access-tokens (list who token)))
       token)
      existing-token))
