(do
  (settaskperms caller)
  (if (= 0 (len argstr))
    (player:tell "Syntax: @undig <direction> [no-recycle]")

    (let ((loc        player.location)
          (asplit     (split argstr " "))
          (dir        (get asplit 0 nil))
          (no-recycle (= (get asplit 1 nil) "no-recycle")))

      (cond
        ((nil? loc)
         (player:tell "You need to move somewhere before un-digging!"))
        ((nil? dir)
         (player:tell "You need to specify a direction to un-dig."))
        ((let ((candidates (loc:get-exits-by-dir dir))
               (candlen    (len candidates)))
           (cond
             ((= 0 candlen)
              (player:tell "This room has no exit in direction '" dir "'."))
             ((> 1 candlen)
              (do
                (player:tell "Ambiguous exit string '" dir "'. Possibilities are: ")
                (map (lambda (exit)
                       (player:tell "  " exit.dir))
                     candidates)))
             ((let ((exit-to-delete (get candidates 0)))
                (let ((src exit-to-delete.source)
                      (dest exit-to-delete.destination))
                  (do
                    (player:disconnect-rooms-with src dest exit-to-delete)
                    (player:tell "Disconnected " ($o src) " from " ($o dest) ".")
                    (player:tell ($o exit-to-delete) " should be recycled now."))))))))))))
