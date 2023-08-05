(define hex-char
  (lambda (n)
    (substr "0123456789ABCDEF" n n)))

(define encode-char
  (lambda (c)
    (let ((o (ord c))
          (c1 (/ o 16))
          (c2 (% o 16))
          (hc1 (hex-char c1))
          (hc2 (hex-char c2)))

    (cat "%" hc1 hc2))))

(let ((str (get args 0)))
  ($strutils:gsub str "([^A-Za-z0-9])"
                  (lambda (start end groups)
                    (encode-char (get groups 0)))))
