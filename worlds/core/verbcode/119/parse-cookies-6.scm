;;; (self:parse-cookies cookie-str:Str):Table
;;;
;;; If any of the cookies are malformed, E_PARSE is raised.
;;;
;;; The return value is a table that maps cookie names to values.
(let ((cookie-str (get args 0)))
  (if (= 0 (len cookie-str))
      (table)
      (let ((cookies (split cookie-str "; "))
            (cookie-parts (map (lambda (cook)
                                 (let ((cook-parts (split cook "=")))
                                   (if (not (= 2 (len cook-parts)))
                                       (err E_PARSE (cat "invalid cookie: " cook))
                                       cook-parts)))
                               cookies)))
        (call table cookie-parts))))
