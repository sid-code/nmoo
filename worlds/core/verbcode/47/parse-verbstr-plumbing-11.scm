;;; Like git divides its commands (or verbs!) into "plumbing and 
;;; porcelain", I'm doing the same here. This is the plumbing
;;; version of 'parse-verbstr' that doesn't return nice string
;;; messages.

;;; The return value of this verb is always a list containing 4 
;;; items. If the list doesn't need to contain 5 items (for example,
;;; if it's an error, it will still be padded with zeros to reach
;;; 6 elements.

;;; The first element is the return status of the call. If everything
;;; worked out right, it will be 0.  
;;; If the verb string was not formatted correctly it will be 1. 
;;; If the OBJECT could not be found, it will be 2.
;;; If the VERB could not be found on the object, it will be 3.
;;; If a malformed arg spec string was included, it will be 4
;;; If an invalid arg is in the arg spec string, it will be 5

;;; The second, third, and fourth elements are the following,
;;; respectively: object verb is defined on, verb INDEX, original
;;; object from the query.

;;; The fifth element will be the "verb" part of the verb string
;;; passed in.

;;; The sixth argument will be the argspec tha was passed in. For
;;; example, if the string passed in was "#1:give(this,to,any")
;;; it will contain ("this" "to" "any"). If none was provided,
;;; then it will be nil.

;;; For example, "#2:tell" will parse into (0 #1 2 #2) if #1
;;; is the parent of #2 and defines tell (which happens to be in
;;; position 2.

(let ((str (get args 0))
      (parsed (match str "([^:]+):([^(]+)(?:%(([^)]+)%))?")))
  (if (nil? parsed)
      (1 0 0 0 0 nil)
      (call-cc 
       (lambda (return)
         (let ((obj-ref (get parsed 0))
               (obj-query (get (query player obj-ref) 0 nil))
               (verb-ref (get parsed 1))
               (arg-str (get parsed 2))
               (arg-spec
                 (if (or (nil? arg-str) (= 0 (len arg-str)))
                     nil
                     (let ((argstr-parse 
                            ($verbutils:parse-argstr-plumbing arg-str))
                           (argstr-result-code (get argstr-parse 0))
                           (argstr-result-value (get argstr-parse 1)))
                       (cond
                        ((= argstr-result-code 0) argstr-result-value)
                        ((= argstr-result-code 1) (call return ((4 0 0 0 0 nil))))
                        ((< -1 (in (2 3) argstr-result-code)) (call return ((5 0 0 0 0 argstr-result-value))))
                        ((err E_ARGS "parse-argstr returned something absurd!")))))))
           (if (nil? obj-query)
               (2 0 0 0 verb-ref arg-spec)
               (let ((verb-loc ($verbutils:find-verb-rec obj-query verb-ref arg-spec)))
                 (if (nil? verb-loc)
                     (3 obj-query -1 obj-query verb-ref arg-spec)
                     (cat (unshift verb-loc 0) (list verb-ref arg-spec))))))))))
