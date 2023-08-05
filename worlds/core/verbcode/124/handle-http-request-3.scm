(define plain-headers (table ("Content-Type" "text/plain")))
(define html-headers  (table ("Content-Type" "text/html")))
(define invalid-method-error
  (list 405 plain-headers "Only POST requests allowed here."))
(define make-invalid-format-error
  (lambda (desc)
    (list 400 plain-headers
          (cat "Please supply a form-encoded non-empty authentication string"
               " (user=<username>&pass=<password>[&redirect=<url>]). (" desc ")"))))
(define invalid-password-error
  (list 401 plain-headers "Invalid username/password combo."))

(call-cc
 (lambda (return)
   (let ((method  (get args 0))
         (path    (get args 1))
         (headers (get args 2))
         (body    (get args 3 nil))

         ;; The name `GUARD-CLAUSE` is for clarity, this binding is unused
         (GUARD-CLAUSE
          (cond
           ((not (= method 'post)) (return invalid-method-error))
           ((nil? body)            (return (make-invalid-format-error "There was no body.")))
           (nil)))

         (login-request ($webutils:parse-query (cat "?" body)))
         (username      (tget login-request "user" nil))
         (password      (tget login-request "pass" nil))
         (redirect      (tget login-request "redirect" nil))
         
         (GUARD-CLAUSE
          (cond
           ((= username nil) (return (make-invalid-format-error "There was no username.")))
           ((= password nil) (return (make-invalid-format-error "There was no password.")))
           (nil)))

         (player-object (or (#0:find-player username) (return invalid-password-error)))
         (check (or (#0:check-pass player-object password) (return invalid-password-error)))

         ;; Password confirmed!

         ;; First, issue the token
         (token (self:issue-session-token player-object))

         ;; Then, set the cookie
         (resp-headers-old (tset html-headers "Set-Cookie" (cat "Session-Token=" token)))
         (resp-headers (if (nil? redirect)
                           resp-headers-old
                           ;; I KNOW I KNOW, IT COULD BE HTTPS
                           (tset resp-headers-old "Location" (cat "http" "://" (tget headers "host" "/") redirect))))
         (status-code (if (nil? redirect) 200 301)))
     (list status-code resp-headers
           (cat "You are logged in as " ($webutils:html-fragment-for-data player-object))))))
