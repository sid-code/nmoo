;; ::
;;    (:html-fragment-for-data data:Any
;;                             obj-hyperlink-schema:Callable = default-hyperlink-schema)
;;
;; Convert `data` into html fragment. Use argument
;; `obj-hyperlink-schema` to convert objects into hyperlinks to their
;; own pages.


(define default-hyperlink-schema
  (lambda (o) (cat "/obj/" (strsub ($ o) "#" ""))))

(define html-fragment-for-data
  (lambda (data ohs)
    (cond
     ((istype data "obj")
      (cat "<a href=\"" (ohs data) "\">" ($o data) "</a>"))
     ((istype data "table")
      (cat "(table "
           ($strutils:join
            (map (lambda (pair)
                   (cat "("
                        (html-fragment-for-data (get pair 0) ohs)
                        " "
                        (html-fragment-for-data (get pair 1) ohs)
                        ")"))
                 (tpairs data)) " ")
           ")"))
     ((istype data "list")
      (cat "("
           ($strutils:join
            (map (lambda (d) (html-fragment-for-data d ohs)) data) " ")
           ")"))
     
     ((istype data "str")
      (cat "\"" data "\""))
     (($ data)))))

(if (or (< (len args) 1) (> (len args) 2))
    (error E_ARGS (cat self ":" verb " takes 1 or 2 arguments"))
    (let ((data (get args 0))
          (object-hyperlink-schema (get args 1 default-hyperlink-schema)))
      ($webutils:escape-html (call html-fragment-for-data (list data object-hyperlink-schema)))))
