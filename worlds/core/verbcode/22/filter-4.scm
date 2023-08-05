(let
  ((fn (get args 0))
   (lst (get args 1)))
   
  
  (fold-right (lambda (acc next)
                 (if (call fn (list next))
                     (push acc next)
                     acc))
              
              () lst))
