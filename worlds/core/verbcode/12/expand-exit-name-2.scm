(let ((name (get args 0))
      (standard ("north" "east" "south" "west" "up" "down"))
      (attempt ($listutils:filter (lambda (fullname)
                            ($strutils:starts-with fullname name))
                          standard)))

  (if (= 0 (len attempt))
      name
      (get attempt 0)))
