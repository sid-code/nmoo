(let ((dir (get args 0 nil))
      (exits self.exits))
    (if (istype dir "str")
        ($listutils:filter (lambda (ex) ($strutils:starts-with ex.dir dir)) exits)
        (err E_ARGS "must specify a direction to " verb)))
