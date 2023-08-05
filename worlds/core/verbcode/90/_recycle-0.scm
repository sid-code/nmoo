(let ((what (get args 0)))
  (if (not ($permutils:controls? caller what))
      (err E_ARGS (cat caller " can't recycle " what ": permission denied"))
  	  (if (playerflag what)
          (err E_ARGS "I will not recycle a player.")
          (do
           ()    ;TODO: Kill all tasks
           ($buildutils:recreate what $garbage)
           (setprop what "owner" $garbageman)
           (setprop what "name" (cat "Garbage Object " what))
           (try (move what self)
                (player:tell error))
           0))))
