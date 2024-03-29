(call-cc
 (lambda (return)
   (let ((str   (get args 0))
         (pat   (get args 1))
         (fn    (get args 2))
         (state (call-cc (lambda (x) (list str 0 x))))
         (cur         (get state 0))
         (start-index (get state 1))
         (ct          (get state 2))
         (find-result (or (find cur pat start-index) (return cur)))
         ;; note:          ^
         ;; find returns (start:Int end:Int capturing-groups:List)
         (new-start   (get find-result 0))
         (new-end     (get find-result 1))
         (fn-result   (call fn find-result))
         ;(new-end     (+ (len fn-result) (get find-result 1)))
         (spliced     (splice cur new-start new-end fn-result)))
     (ct (list spliced (+ (len fn-result) new-start) ct)))))
