;;; Usage:
;;; (self:issue-session-token who:Object expire:Int=7200000):Str

;;; where ``expires`` is the number of milliseconds for which the
;;; issued token will be valid.

;;; Things to note:
;;;   arguments are in the ``args`` variable

(let ((token  ($strutils:id-gen 48)) ;; Utility verb to generate random strings
      ;; Who is the token being generated for
      (who    (get args 0))
      
      ;; When does the token expire?
      (expiry (+ (time) (get args 1 7200000))))
  
      ;; Note: ``get``'s 3rd argument is used if the second is out of bounds
      ;; this is usued to implement the 7200000 ms default expiry
  
  ;; Everything is immutable: therefore, we have to retrieve the sessions table
  ;; ``self.sessions``, use ``tset`` builtin function to add the token (along 
  ;; with whose token it is and when it expires), and then use ``setprop`` to
  ;; update the "sessions" property. This is admittedly somewhat unwieldy.
  (setprop self "sessions" (tset self.sessions token (list who expiry)))
  
  ;; let bindings evaluate to the last expression evaluated in their body
  token)
