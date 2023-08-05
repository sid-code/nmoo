(define instruction-to-html
  (lambda (instruction)
    (cat ($webutils:html-fragment-for-data instruction)
         "<br>")))

(define bytecode-to-html
  (lambda (bytecode)
    (call cat (map instruction-to-html bytecode))))
    
(call (lambda (method path headers body pargs)
        (let ((obj (get pargs 0))
              (verb-num (get pargs 1))
              (bytecode (getverbbytecode obj verb-num)))
          (bytecode-to-html bytecode)))
      args)
