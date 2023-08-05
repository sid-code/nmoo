(let
  ((name (get args 0))
   (email (get args 1))
   (cur-reqs (getprop self "char-requests" ()))
   (new-req (list name email caller.address)))
  
  (do
    (setprop self "char-requests" (push cur-reqs new-req))))
