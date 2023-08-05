(let
  ((obj (get args 0)))
  
  (if (= obj (parent obj))
      (props obj)
      (fold-right
       (lambda (cur new-el)
         (setadd cur new-el))
       (#0:all-props (parent obj))
       (props obj))))
