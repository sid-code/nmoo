(let ((hverb (get args 0)))
  (cond
   ((= hverb 'get) (pass))
   ((= hverb 'post)
    (let ((headers (get args 2))
          (body (get args 3)))
      (settaskperms (tget headers "authuser" player))
      (list 200 (table ("Content-Type" "text/plain"))
            (try ($ (eval (parse body))) ($ error)))))
   ((list 400 (table ("Content-Type" "text/plain")) "verb not supported"))))
