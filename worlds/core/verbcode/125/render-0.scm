(define plain-headers
  (table ("Content-Type" "text/plain")))
(define html-headers
  (table ("Content-Type" "text/html")))

(define page-header-frag #134)
(define page-header-html (verbcall page-header-frag "render-partial" args))

;; Generate HTML page describing `obj`
(define html-for-obj
  (lambda (obj)
    (cat "<!DOCTYPE HTML><html lang=\"en\"><head><meta charset=\"utf-8\"></head><body>"
         page-header-html
         "<h1>" ($webutils:escape-html ($ obj)) ": "
                ($webutils:escape-html (try (obj:name) (getprop obj "name" "(No name)"))) "</h1>"
         "<p>Child of " ($webutils:html-fragment-for-data (parent obj))
         " | Owned by " ($webutils:html-fragment-for-data obj.owner)
         (let ((ps (#0:all-props obj)))
           (if (= 0 (len ps)) "This object has no properties."
               (cat
                "<p>Properties:"
                "<table>"
                "<tr><td>Property name</td><td>Value</td></tr>"
                (call cat
                      (map
                       (lambda (p)
                         (cat "<tr><td>" p "</td><td>"
                              ($webutils:html-fragment-for-data (getprop obj p))
                              "</td></tr>"))
                       ps))
                "</table>")))
         (let ((vs (verbs obj)))
           (if (= 0 (len vs)) "This object defines no verbs (but its parents may)"
               (cat
                "<p>Verbs:"
                "<table>"
                "<tr><td>Verb name</td><td>Owner</td><td>Permissions</td></tr>"
                (call cat
                      (map
                       (lambda (vindex)
                         (let ((v (get vs vindex))
                               (srchref  (cat "/obj/" (gsub ($ obj) "#" "") "/v/" vindex))
                               (verbinfo (getverbinfo obj v))
                               (owner    (get verbinfo 0))
                               (perms    (get verbinfo 1)))
                           (cat "<tr><td><a href=\"" srchref "\">" v "</a></td>"
                                "<td>" ($webutils:html-fragment-for-data owner) "</td>"
                                "<td>" perms "</td></tr>")))
                       (range 0 (- (len vs) 1))))
                "</table>")))
         "<p>Children:<ul>"
         ($strutils:join (map (lambda (o)
                                (cat "<li>" ($webutils:html-fragment-for-data o)))
                              (children obj))
                         "")
         "</ul>"
         "</body></html>")))

(call (lambda (method path headers body args)
        (let ((authuser (tget headers "authuser" player))
	      (obj (object (get (get args 0 ()) 0 -1))))
	  (settaskperms authuser) ; prevent any monkey business
          (if (not (valid obj))
              (list 404 plain-headers
                    (cat "The object " obj " is invalid."))
              (try
                (list 200 html-headers
                      (html-for-obj obj))
                (if (erristype error E_PERM)
                    (list 401 plain-headers "You are not permitted to view this.")
                    error))))) ; rethrow

      args)
