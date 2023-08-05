(map (lambda (guest)
       (setprop guest "available" 1))
     (children $guest))
(echo "Marked all guests available")
