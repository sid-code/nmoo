(let
  ((address (get args 0))
   (guests (children $guest))
   (available-guests ($listutils:filter (lambda (x) x.available) guests))
   (guest (get available-guests 0 nil)))
  
  (if (istype guest "nil")
      (if (>= (len guests) 10)
        "No more room!"
        (let ((new-guest (create $guest)))
          (do
            (echo "Making a new guest to accomodate a player: " new-guest ".")
            (setprop new-guest "name" "a guest")
            (setprop new-guest "available" 0)
            (setprop new-guest "address" address)
            new-guest)))
      (do
        (echo "Found an existing guest, " guest ".")
        (setprop guest "available" 0)
        (setprop guest "address" address)
        guest)))
