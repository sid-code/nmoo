(do
 (settaskperms player)
 (if (= 0 (len args))
     (player:tell "Syntax: @prop <object>.<property>")
     (let ((objprop-ref (get args 0))
           (parsed ($verbutils:parse-propstr objprop-ref)))
       (cond
        ((istype parsed "str") (player:tell parsed)) ; string means error
        ((istype parsed "list")
         (let ((obj (get parsed 0))
               (prop-ref (get parsed 1)))
           (if ($verbutils:has-prop? obj prop-ref)
               (player:tell obj "." prop-ref " = "
                            (getprop obj prop-ref))
               (try (do
                     (setprop obj prop-ref nil)
                     (player:tell "Created property " prop-ref " on " ($o obj) " (set to nil)."))
                    (cond
                      ((erristype error E_PERM)
                       (player:tell "Failed to create new property (Permission denied)."))
                      (error))))))
        ((player:tell "Something terrible has happened. "
                      "$verbutils:parse-propstr has returned a value of "
                      "invalid type: " parsed))))))
