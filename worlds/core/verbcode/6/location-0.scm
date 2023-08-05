(echo 
  (try 
    (cat "You are located at " ($ caller.location) ".") 
    "There is no location"))
