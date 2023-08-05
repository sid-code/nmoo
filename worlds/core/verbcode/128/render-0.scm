(define error-response
  (lambda (message)
    (list 400 (table ("Content-Type" "text/plain")) message)))

(define success-html
  (lambda (body)
    (list 200 (table ("Content-Type" "text/html")) body)))

(define success-plain
  (lambda (body)
    (list 200 (table ("Content-Type" "text/plain")) body)))

(define verb-code-editor #132)
(define bytecode-viewer #137)
(define standard-header-html (verbcall #134 "render-partial" args))

(define template
  (lambda (verb-ref body)
     (cat "<!DOCTYPE HTML>"
          "<html lang='en'>"
          "<head><meta charset='utf8'><title>Verb editor: " verb-ref "</title>"
          "</head>"
          standard-header-html
          "<body>" body "</body></html>")))

(call (lambda (method path headers body pargs)
        (call-cc
         (lambda (return)
           (let ((authuser (settaskperms (tget headers "authuser" player)))
                 (obj-str  (get (get pargs 0 ()) 0))
                 (verb-str (get (get pargs 1 ()) 0))

                 ;; try to extract the object number and verb number
                 (obj
                  (try (object obj-str)
                       (return (error-response (cat "Invalid object number: " obj-str)))))
                 (verb-num
                  (try (parseint verb-str)
                       (return (error-response (cat "Invalid verb number: " verb-str)))))

                 (verb-name (get (getverbinfo obj verb-num) 2))
                 (verb-ref  (cat ($ obj) ":" verb-name))

                 (verb-code
                  (try (getverbcode obj verb-num)
                       ;; make sure the verb exists
                       (return (error-response
                                (cat "Verb index " verb-num " out of range"))))))
             (cond
              ((= method 'get)
               (let ((qargs ($webutils:parse-query path))
                     (bytecode-view? (tget qargs "bytecode" 0))
                     (result-html
                      (if bytecode-view?
                          (bytecode-viewer:render-partial method path headers body (list obj verb-num))
                          (verb-code-editor:render-partial method path headers body (list obj verb-num)))))
                 (return (success-html (template verb-ref result-html)))))
              ((= method 'post)
               (if (nil? body)
                   (return (error-response "Nonexistant body"))
                   (try (do (setverbcode obj verb-num body)
                            (return (success-plain
                                     (cat "Successfully edited " verb-ref))))
                        (return (error-response
                                 (cat error))))))

              ((return (error-response (cat "Invalid method: " ($ method))))))))))
                 
         args)
