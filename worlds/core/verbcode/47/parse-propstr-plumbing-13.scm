;;; Parses a string like "obj-str.prop" into (#5 "prop"), 
;;; assuming "obj-str" is a name of #5.

;;; The actual return value has 3 elements. The first, as usual, is
;;; the result code.
;;;   0 - success, return value: (obj prop)
;;;   1 - malformed property string, return value: nil
;;;   2 - missing object, return value: (obj-str prop) <-- note no obj
;;; The second element will be the real return value, if applicable.

;;; This differs from parse-verbstr verbs because it does NOT check
;;; whether the property exists. That's the job of whatever verb calls
;;; this one.

(let ((str (get args 0))
      (parsed (match str "([^.]+)%.(.+)")))
  (if (nil? parsed)
      (1 nil)
      (let ((obj-ref (get parsed 0))
            (obj-query (get (query player obj-ref) 0 nil))
            (prop-ref (get parsed 1)))
        (if (nil? obj-query)
            (2 parsed)
            (0 (list obj-query prop-ref))))))
