(do
 (settaskperms player)
 (let ((parts (split argstr " to ")))
   (if (not (= 2 (len parts)))
     (player:tell "Syntax: " verb " <object>.<property> to <new-value>")
     (let ((propdesc (get parts 0))
           (propdesc-parsed ($verbutils:parse-propstr propdesc))
           (newvalue-str (get parts 1))
           (newvalue (try (parse newvalue-str)
                          (do (player:tell "Could not parse value.") nil))))
       (cond
         ((istype newvalue "nil") nil)
         ((istype propdesc-parsed "str") (player:tell propdesc-parsed))
         ((istype propdesc-parsed "list")
          (let ((obj      (get propdesc-parsed 0))
                (prop-ref (get propdesc-parsed 1)))
            (if ($verbutils:has-prop? obj prop-ref)
                (try (do
                      (setprop obj prop-ref newvalue)
                      (player:tell "Set " obj "." prop-ref " to " newvalue))
                     (cond
                       ((erristype error E_PERM)
                        (player:tell "Permission denied."))
                       (error)))
                (player:tell ($o obj) " has no property '" prop-ref "'."))))
         ((player:tell "Something went terribly wrong. $verbutils:parse-propstr returned something it shouldn't have ("
                       propdesc-parsed ")")))))))
