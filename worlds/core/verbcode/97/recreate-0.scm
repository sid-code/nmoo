(let ((what (get args 0))
      (new-parent (get args 1))
      (owner (callerperms)))
  (if (not (or (= 0 (level owner)) (and (= owner what.owner) 
                                   (= owner new-parent.owner) 
                                   new-parent.fertile)))
      (err E_PERM (cat owner " cannot recreate " what))
      (let ((grandpa (parent what)))
        (do
         (map (if (= grandpa what)
                  (lambda (child) (setparent child child))
                  (lambda (child) (setparent child grandpa)))
              (children what))
         (map (lambda (obj)
                (if (playerflag obj)
                    (move obj $player-start)
                    (move obj $nowhere)))
              what.contents)
         (if ($verbutils:find-verb what "recycle")
             (what:recycle)
        	 nil) 
         (setparent what what)
         (map (lambda (propref) (delprop what propref)) (props what))
         (map (lambda (verbref) (delverb what verbref)) (verbs what))
         (setparent what new-parent)
         (setprop what "name" "")
         (setprop what "pubread" 0)
         (setprop what "pubwrite" 0)
         (setprop what "fertile" 0)
         (if ($verbutils:find-verb what "initialize")
             (what:initialize)
             nil)
         1))))
