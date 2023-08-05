(let
  ((what (get args 0))
   (childs (children what)))

  (if (= 0 (len childs)) ()  
    (call cat (map (lambda (child)
                (if (= child what) ()
                    (push (self:descendents child) child))) childs))))
