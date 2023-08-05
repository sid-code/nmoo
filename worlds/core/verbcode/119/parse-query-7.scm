;;; This function takes any URL fragment and extracts the URL-encoded
;;; query data.

;;; For example:
;;;   "/foo/baz/?a=b&c=d" => (table ("a" "b") ("c" "d"))

(call-cc
 ;; Early return idiom: calling `return` with parameter X inside the
 ;; following lambda will cause the entire call-cc block to return
 ;; with X
 (lambda (return)
   (let ((url (get args 0))
         ;; Now, extract everything after the first ?.
         ;; Note: we still expect any stray ?s to be URL-encoded, so the
         ;; assumption that the first literal ? in the string is the
         ;; start of the query is valid.
         (q-index (index url "?"))

         (_ (player:tell q-index))

         ;; Check if the query string is empty, if so then execute an
         ;; early return. The name `GUARD-CLAUSE` is purely for clarity.
         (GUARD-CLAUSE (if (or (= q-index (- 1 (len url))) (= q-index -1))
                           (call return (list (table)))
                           nil))

         (q-str   (substr url (+ 1 q-index) -1))
         (q-parts (split q-str "&"))
         (q-parts-split (map (lambda (part)
                               (let ((part-split (split part "=")))
                                 (if (not (= 2 (len part-split)))
                                     (list nil nil)
                                     (map (lambda (str) ($webutils:url-decode str))
                                          part-split))))
                             q-parts)))
     (tdelete (call table q-parts-split) nil))))
