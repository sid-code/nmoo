(let
  ((container (get args 0))
   (obj (get args 1)))
  
  (and
    (= (getprop obj "location" nil) container)
    (< -1 (in (getprop container "contents" ()) obj))))
