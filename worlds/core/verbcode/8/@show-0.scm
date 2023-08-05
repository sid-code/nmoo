(let ((show-obj
       (lambda (obj)
         (do
          (player:tell "Object ID:  " dobj)
          (player:tell "Name:       " (getprop dobj "name" "No name"))
          (player:tell "Parent:     " ($o (parent dobj)))
          (player:tell "Owner:      " dobj.owner)
          
          (player:tell "Verb definitions: ")
          (map (lambda (verb) (player:tell "  " verb)) (verbs dobj))
          
          (player:tell "Properties: ")
          (map (lambda (prop) (player:tell "    " prop ": " (getprop dobj prop)))
               
            (#0:all-props dobj)))))
      (show-verb
       (lambda (obj verb-ref)
         (let ((info (getverbinfo obj verb-ref))
               (verb-owner (get info 0))
               (permissions (get info 1))
               (verb-names (get info 2))
               (args (getverbargs obj verb-ref))
               (direct-object (get args 0))
               (preposition (get args 1))
               (indirect-object (get args 2)))
           (do
            (player:tell obj ":" verb-names)
            (player:tell "Owner:            " ($o verb-owner))
            (player:tell "Permissions:      " permissions)
            (player:tell "Direct Object:    " direct-object)
            (player:tell "Preposition:      " preposition)
            (player:tell "Indirect object:  " indirect-object)))))
      (show-prop
       (lambda (obj prop-ref)
         (let ((info (getpropinfo obj prop-ref))
               (prop-owner (get info 0))
               (permissions (get info 1))
               (value (getprop obj prop-ref)))
           (do
            (player:tell obj "." prop-ref)
            (player:tell "Owner:           " ($o prop-owner))
            (player:tell "Permissions:     " permissions)
            (player:tell "Value:           " value))))))
            
           
  (cond
   ((< -1 (index dobjstr "."))
    (let ((parsed ($verbutils:parse-propstr dobjstr)))
      (if (istype parsed "str")
          (player:tell parsed) ; there was an error (this should probably never happen)
          (let ((obj (get parsed 0)) ; now we have to check if the property actually exists
                (prop-ref (get parsed 1)))
            (try
             (do
              (getprop obj prop-ref)
              (call show-prop (list obj prop-ref)))
             (player:tell error))))))
   ((< -1 (index dobjstr ":"))
    (let ((parsed ($verbutils:parse-verbstr dobjstr)))
      (if (istype parsed "str")
          (player:tell parsed) ; there was an error parsing the verb or the verb wasn't found
          (let ((obj-defined-on (get parsed 0))
                (verb-ref (get parsed 1))
                (obj (get parsed 2)))
            (do
             (if (not (= obj obj-defined-on))
                 (player:tell "Object " obj " does not define that verb, but its ancestor "
                              obj-defined-on " does.")
                 nil)
             (call show-verb (list obj-defined-on verb-ref)))))))
   ((if (nil? dobj)
        (player:tell "I don't see '" dobjstr "' here.")
        (show-obj dobj)))))
