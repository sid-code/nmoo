(define hex-char-to-int
  (lambda (hc)
    (let ((o (ord hc))
          (oA (ord "A"))
          (o0 (ord "0")))
      (cond
       ((>= o oA) (+ 10 (- o oA)))
       ((>= o o0) (- o o0))
       ((err E_ARGS (cat "invalid hex character " hc)))))))

(let ((url-fragment (get args 0)))
  ($strutils:gsub url-fragment "%%([0-9a-fA-F]{2})"
                  (lambda (start end groups)
                    (let ((hex-str (get groups 0))
                          (char0   (substr hex-str 0 0))
                          (char1   (substr hex-str 1 1))
                          (hc0     (hex-char-to-int char0))
                          (hc1     (hex-char-to-int char1)))
                      (chr (+ (* hc0 16) hc1))))))
