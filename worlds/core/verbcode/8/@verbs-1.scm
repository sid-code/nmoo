(do
  (settaskperms caller)
  (if (= 0 (len argstr))
      (player:tell "Syntax: " verb " obj")
      (if (nil? dobj)
          (player:tell "I don't see " dobj " around here.")
          (let ((verb-list (verbs dobj))
                (num-verbs (len verb-list)))
            (do 
             (player:tell "Showing verbs for " ($o dobj) ":")
             (player:tell "ID   Names                      Arguments")
             (player:tell "---  -------------------------  ----------------")  
             (map (lambda (idx)
                    (echo (fit (cat ($ idx) ")  ") 5)
                          (fit (get verb-list idx) 25) "  "
                          ($verbutils:get-verb-argstr dobj idx)))
                   (range 0 (- num-verbs 1))))))))
