(let
  ((location (getprop self "location" nil)))
  
  (do
    (echo "You have logged in as " (getprop self "name" "(no name)"))))
    ;(if (nil? location) ()
    ;  (location:look))))
