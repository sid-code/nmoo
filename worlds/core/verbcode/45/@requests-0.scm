(let
  ((reqs #0.char-requests))
  
  (if (= 0 (len reqs))
    (echo "There are no character requests pending.")
    (do
      (echo "The following character requests are pending: ")
      (map (lambda (req)
             (let ((name  (get req 0 "No name"))
                   (email (get req 1 "No email"))
                   (ip    (get req 2 "No IP")))
               (player:tell (cat (fit name 16) (fit email 25) (fit ip 16)))))
           reqs))))
