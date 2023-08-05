;; Access tokens are stored in a table that maps token strings to
;; pairs of (player:Obj expiry:Int) where expiry is the time (ms since
;; 1970 UTC) of expiry of the session.

(call-cc
 ;; "early return" idiom
 (lambda (return)
   (let ((token (get args 0))
         ;; if the token doesn't exist, return early with nil
         (attempt (or (tget self.sessions token nil) (call return '(nil))))
         (who    (get attempt 0))
         (expiry (get attempt 1))
         (now    (time)))
     (if (> now expiry)
         (do (self:revoke-session-token token) nil)
         who))))
