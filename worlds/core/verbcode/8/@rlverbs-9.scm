(if (nil? dobj) (player:tell "Syntax: " verb " #obj")
    (do
        (map (lambda (v)
               (do (loadverb dobj v) (player:tell "Loaded " dobj ":" v)))
             (verbs dobj))
        (player:tell "Done loading verbs for " dobj ".")))
