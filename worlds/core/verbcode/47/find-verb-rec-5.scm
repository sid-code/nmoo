(let ((obj  (get args 0))
      (pt   (parent obj))
      (name (get args 1))
      (arg-spec (get args 2 nil))
      (original-object (get args 3 obj))
      (attempt ($verbutils:find-verb obj name arg-spec)))
  
  (if (nil? attempt)
   	  (if (= obj pt)
    	  nil
          ($verbutils:find-verb-rec pt name arg-spec original-object))
      (list obj attempt original-object)))
