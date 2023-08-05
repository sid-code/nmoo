(if (= 0 (len argstr))
    (player:tell "Syntax: @program obj:verb")
    ;; The second argument (0) means we only want verbs defined
    ;; on the object, not on its ancestors
    (let ((verb-loc ($verbutils:parse-verbstr argstr 0)))
      (cond
       ((istype verb-loc "str") (player:tell verb-loc))
       ((istype verb-loc "list")
        (let ((code (caller:read-till-dot)))
         (do (setverbcode (get verb-loc 0) (get verb-loc 1) code)
             (player:tell "Verb edited successfully!"))))
       ((player:tell "Something has gone terribly wrong.")))))
