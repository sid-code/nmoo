(if (not (= (len args) 2)) 
 (player:tell "Syntax: " verb " obj1:verb obj2")
 (let ((verb-str   (get args 0))
       (verb-loc   ($verbutils:parse-verbstr verb-str)))
   (cond
    ((istype verb-loc "str") (player:tell verb-loc))
    ((istype verb-loc "list")
      (let ((obj1       (get verb-loc 0))
            (vidx       (get verb-loc 1))
            (vname      (get (verbs obj1) vidx))
            (obj2-ref   (get args 1))
            (obj2       (get (query player obj2-ref) 0 nil)))
       (if (nil? obj2)
        (player:tell "I don't see " obj2-ref " here.")
        (do
         ($verbutils:move-verb obj1 vname obj2)
         (echo "Successfully moved "
               ($o obj1) ":" vname " to " ($o obj2) ".")))))
           
     ((echo "Something truly terrible has happened.")))))
