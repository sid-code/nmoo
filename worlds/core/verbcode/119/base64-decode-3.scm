(define base64-decode-quadruplet
  (lambda (e1 e2 e3 e4)
    (let ((c3 (if (= -1 e4) nil
                  (+ e4 (* (% e3 4) 64))))
          (c2 (if (= -1 e3) nil
                  (+ (/ e3 4) (* (% e2 16) 16))))
          (c1 (if (= -1 e2) nil
                  (+ (/ e2 16) (* e1 4)))))
      (list c1 c2 c3))))

(define base64-delookup
  (lambda (char)
    (let ((o (ord char))
          (oA (ord "A"))
          (oZ (ord "Z"))
          (oa (ord "a"))
          (oz (ord "z"))
          (o0 (ord "0"))
          (o9 (ord "9")))
      (cond
       ((= char "=") -1)
       ((= char "+") 62)
       ((= char "/") 63)
       ((and (>= o oA) (<= o oZ)) (- o oA))
       ((and (>= o oa) (<= o oz)) (+ 26 (- o oa)))
       ((and (>= o o0) (<= o o9)) (+ 52 (- o o0)))
       ((err E_ARGS (cat "invalid base64 character '" char "' (ascii " o ")")))))))

(define my-chr
  (lambda (num-or-nil)
    (if (nil? num-or-nil) "" (chr num-or-nil))))

(define base64-decode
  (lambda (str)
    (let ((size (len str))
          (num-blocks (/ size 4))
          (blocks (range 0 (- num-blocks 1))))
      (if (= 0 size) ""
          (if (not (= 0 (% size 4)))
              (err E_ARGS "cannot decode base64 string whose length isn't a multiple of 4")
              (call cat (map (lambda (block)
                               (let ((idx (* block 4))
                                     (e1 (base64-delookup (substr str idx idx)))
                                     (e2 (base64-delookup (substr str (+ idx 1) (+ idx 1))))
                                     (e3 (base64-delookup (substr str (+ idx 2) (+ idx 2))))
                                     (e4 (base64-delookup (substr str (+ idx 3) (+ idx 3)))))
                                 (call cat (map my-chr (base64-decode-quadruplet e1 e2 e3 e4)))))
                             blocks)))))))

(if (not (= 1 (len args)))
    (err E_ARGS (cat verb " takes one string argument"))
    (let ((str (get args 0)))
      (base64-decode str)))
