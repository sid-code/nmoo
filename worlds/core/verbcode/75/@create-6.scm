;;; Syntax: @create <parent> named <new-name>

(if (not (= (len args) 3))
    (do 
     (player:tell "Syntax: " verb " <parent> named <new-name>")
     (player:tell "If more than one word, new-name must be in quotes"))
    (let ((parent-str (get args 0))
          (parent-query (query player parent-str))
          (parent-query-len (len parent-query))
          (new-name (get args 2)))
      (cond
       ((= 0 parent-query-len)
        (player:tell "I can't see a " parent-query " here."))
       ((> 1 parent-query-len)
        (player:tell "Ambiguous query: " parent-query "."))
       ((let ((parent-obj (get parent-query 0))
              (child (player:_create parent-obj)))
          (do
           (setprop child "name" new-name)
           (setprop child "aliases" (setadd child.aliases new-name))
           (setprop child "description" new-name)
           (move child caller)
           (player:tell "Created child of " ($o parent-obj)
                        ", " ($o child))))))))
