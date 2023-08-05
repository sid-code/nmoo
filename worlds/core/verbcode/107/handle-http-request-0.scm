(let ((method   (get args 0))
      (path     (get args 1))
      (q-index (index path "?"))
      (headers  (get args 2))
      (body     (get args 3 nil))
      (pathargs (get args 4 (list)))
      (authenticator #124) ; this is hardcoded for now
      (cookie-str (tget headers "cookie" ""))
      (cookies ($webutils:parse-cookies cookie-str))
      (session-token (tget cookies "Session-Token" nil))
      ;; Attempt to authenticate the user with the session token
      ;; Failure to resolve the session token will mean the resolve
      ;; verb returns nil, so then we will default to the current
      ;; player (which is probably a guest).
      (session-user
       (or (authenticator:resolve-session-token session-token) player))
      (headers-with-auth (tset headers "authuser" session-user)))

  (settaskperms session-user)

  (if (or (< (len path) 2) (= q-index 0) (= q-index 1))
      ;; we have reached the end of the routing chain
      (verbcall self "render" (list method path headers-with-auth body pathargs))
      ;; we need to keep routing
      (let ((attempt (verbcall self.router "route" (list path)))
            (resrc   (get attempt 0))
            (newpath (get attempt 1))
            (newpathargs (push pathargs (get attempt 2))))
        (resrc:handle-http-request method newpath headers-with-auth body newpathargs))))
