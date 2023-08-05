;;; This is the frontend for $verbutils;parse-verbstr-plumbing
;;; it will return either a string or
;;;   (object-that-defines-verb verb-index obj)
;;; when parsing "obj:verb"

;;; It also takes a second argument which tells it whether to
;;; accept verbs defined on the object's ancestors.
(let ((str (get args 0))
      (check-parents? (get args 1 1))
      (result-from-plumbing (self:parse-verbstr-plumbing str))
      (result-code (get result-from-plumbing 0))
      (obj-defined-on (get result-from-plumbing 1))
      (verb-index (get result-from-plumbing 2))
      (obj-original (get result-from-plumbing 3)))
  (cond
   ((= result-code 1)
    (cat "Invalid verb string: " str))
   ((= result-code 2)
    (cat "There is no \"" obj-defined-on "\" around here."))
   ((= result-code 3)
    (cat ($o obj-original) " does not define that verb."))
   ((and 
     (not check-parents?)
     (= result-code 0) 
     (not (= obj-defined-on obj-original)))
    (cat ($o obj-original) " does not define that verb, but "
         "it's ancestor " ($o obj-defined-on) " does. Perhaps "
         "you mean to refer to that verb instead?"))
   ((= result-code 4) "Malformed argspc string")
   ((= result-code 5)
    (cat "Invalid argspec \"" (get result-from-plumbing 5) "\"."))
   ((= result-code 0)               ;success!
    (slice result-from-plumbing 1))
   ((err E_ARGS (cat "Unknown result code" result-code)))))
