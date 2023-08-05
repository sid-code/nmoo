;;; Parses strings like "this,none,this" into ("this" "none" "this")
;;; The return value consists of the error code and the actual result.
;;;    (error-code result)

;;; Error code meanings and corresponding results:
;;;   0 - success, result is a list containing the three argspecs
;;;   1 - malformed list, result is garbage
;;;   2 - invalid objspec, result is the invalid objspec
;;;   3 - invalid prepspec, result is the invalid prepspec

(let ((str (get args 0))
      (spl (split str ",")))
  (if (not (= 3 (len spl)))
      (1 ())
      (let ((direct (get spl 0))
            (indirect (get spl 2))
            (preposition (get spl 1))
            (objspecs #0.possible-objspecs)
            (prepspecs #0.possible-prepspecs))
        (if (= -1 (in objspecs direct))
            (2 direct)
            (if (= -1 (in objspecs indirect))
                (2 indirect)
                (if (= -1 (in prepspecs preposition))
                    (3 preposition)
                    (0 spl)))))))
