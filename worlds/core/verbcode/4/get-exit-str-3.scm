(let ((exits self.exits)
      (exit-names 
        ($listutils:unique (map (lambda (exit) exit.dir)
                                ($listutils:filter (lambda (exit) (not exit.hidden))
                                           exits)))))
  (cat "You can go " ($strutils:joinlist exit-names "or" "nowhere") "."))
