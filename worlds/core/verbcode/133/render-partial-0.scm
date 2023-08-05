(let ((headers (get args 2))
      (authuser (tget headers "authuser" nil))
      (path (tget headers "path")))
  
  (if (= $guest (parent authuser))
      (cat
       "<a href='/login?redirect=" ($webutils:url-encode path) "'>Login</a>")
      (cat
       "Hello, " (authuser:name) ". <a href='/logout'>Log out</a>")))
