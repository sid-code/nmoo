(if (= 0 (len args)) (player:tell "Syntax: @list obj:verb [tags] [no-line-numbers]")
  (let ((verb-str (get args 0))
        (rest-args (slice args 1))
        (show-tags? (< -1 (in rest-args "tags")))
        (show-line-numbers? (= -1 (in rest-args "no-line-numbers")))
        (allow-ancestors? (= -1 (in rest-args "no-ancestors")))
        (verb-loc ($verbutils:parse-verbstr verb-str allow-ancestors?)))
    (cond
     ((istype verb-loc "str") (player:tell verb-loc))
     ((istype verb-loc "list")
      (let ((obj  (get verb-loc 0))
            (vidx (get verb-loc 1))
            (original-object (get verb-loc 2))
            (vname (get (verbs obj) vidx)))
       (do
        (if (not (= obj original-object))
            (player:tell "Verb \"" vname "\" not defined on "
                         ($o original-object) " but rather on "
                         ($o obj) ".")
            0)
        (if show-tags? (player:tell "{verbcode}") 0)
        (if show-line-numbers?
            (let ((lines (split (getverbcode obj vidx) "\n"))
                  (max-line-len (len ($ (len lines)))))
              (map (lambda (line-num)
                     (player:tell (fit ($ (+ 1 line-num))
                                       (* -1 max-line-len)
                                       " ")
                                  ": "
                                  (get lines line-num)))
                   (range 0 (- (len lines) 1))))
            (player:tell (getverbcode obj vidx)))
        (if show-tags? (player:tell "{/verbcode}") 0))))
     ((player:tell "Something went terribly wrong. ($verbutils:parse-verbstr returned " verb-loc " which was of unexpected type.")))))
