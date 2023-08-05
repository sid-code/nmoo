(define login-button-frag #133)

(define styles
  (cat
   ".login-button { float: right; }"))

(define login-button-html (verbcall login-button-frag "render-partial" args))

(cat
 "<style>"
 styles
 "</style>"
 "<div class='header'>"
 "<span class='login-button'>" login-button-html "</span>"
 "</div>")
