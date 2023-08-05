(let ((size (get args 0 5)))
  ($strutils:join (map (lambda (x) (chr (random 97 123))) (range 1 size))))
