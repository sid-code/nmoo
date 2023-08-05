(let ((method     (get args 0))
      (path       (get args 1))
      (headers    (get args 2))
      (pathparams (get args 3 nil)))
  (settaskperms (tget headers "authuser" player))
  (if (= method 'get)
      (200 (table ("Content-Type" "text/html"))
           (cat
            "<p>For now, I'll show you what you requested:"
            "<p>Path: " path
            "<p>Headers: " headers
            "<p>Extra parameters: " pathparams
            "<p>You are: " ($webutils:html-fragment-for-data (callerperms))))
      (400 (table ("Content-Type" "text/plain")) (cat "unsupported method " ($ method)))))
