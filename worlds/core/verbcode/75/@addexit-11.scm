;;; `dobj` is the exit
;;; `iobj` is the room
;;; `player` needs to control `room` 

(if (nil? dobj)
    (player:tell "There is no '" dobjstr "' here.")
    (if (nil? iobj)
        (player:tell "There is no '" iobjstr "' here.")
        
        ;; Check if `player` controls `iobj`
        (if (not ($permutils:controls? player iobj))
            (player:tell "Permission denied (for modifying " iobj ")")
            
            ;; Good to go, just add the exit now
            (do
             (iobj:add-exit dobj)
             (player:tell "Added exit " dobj " to " iobj ".")))))
