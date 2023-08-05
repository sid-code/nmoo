(let ((path (get args 1))
      (pathquery ($webutils:parse-query path))
      (redirect (tget pathquery "redirect" nil))
      (redirect-input-html
       (if (nil? redirect)
           ""
           (cat "<input type='hidden' name='redirect' value='" redirect "' />"))))
  (list 200
        (table ("Content-Type" "text/html"))
        (cat "<form action='/auth' method='post'>"
             redirect-input-html
             "<label for='user'>Username:</label>"
             "<input type='text' name='user' placeholder='Username' required><br>"
             "<label for='pass'>Password:</label>"
             "<input type='password' name='pass' placeholder='Password' required><br>"
             "<button type='submit'>Login</button>")))
