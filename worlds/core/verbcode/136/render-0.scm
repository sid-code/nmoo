(define html-headers (table ("Content-Type" "text/html")))

(call (lambda (method path headers body args)
        (call-cc
         (lambda (return)
           (let ((authuser (settaskperms (tget headers "authuser" player)))
                 (obj-str  (get (get args 0 ()) 0))
                 (verb-str (get (get args 1 ()) 0)))
             (list 200 html-headers "<b>yay</b>")))))
      args)