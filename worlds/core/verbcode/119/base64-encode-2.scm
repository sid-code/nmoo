(define base64-encode-triplet
  (lambda (c1 c2 c3)
    (if (nil? c1) (err E_ARGS "base64-encode-triplet's first argument must be not nil")
        (let ((e1 (/ c1 4))
              (e2-partial (* (% c1 4) 16)))
          (if (nil? c2) (list e1 e2-partial -1 -1)
              (let ((e2 (+ e2-partial (/ c2 16)))
                    (e3-partial (* (% c2 16) 4)))
                (if (nil? c3) (list e1 e2 e3-partial -1)
                    (let ((e3 (+ e3-partial (/ c3 64)))
                          (e4 (% c3 64)))
                      (list e1 e2 e3 e4)))))))))

(define base64-lookup
  (lambda (value)
    (cond
     ((= value -1) "=") ; padding
     ((< value 26) (chr (+ value (ord "A"))))
     ((< value 52) (chr (+ (- value 26) (ord "a"))))
     ((< value 62) (chr (+ (- value 52) (ord "0"))))
     ((= value 62) "+")
     ((= value 63) "/")
     ((err E_ARGS (cat "base 64 value out of range: " value))))))

(define base64-encode
  (lambda (str)
    (let ((size        (len str))
          (num-blocks  (/ size 3))
          (no-padding? (= 0 (% size 3)))
          (blocks      (range 0 (if no-padding? (- num-blocks 1) num-blocks))))
      (if (= 0 size) ""
          (call cat
                (map (lambda (block)
                       (let ((idx (* block 3))
                                        ; guaranteed not to be out of bounds
                             (c1 (ord (substr str idx idx)))
                             (c2 (if (> idx (- size 2)) nil (ord (substr str (+ idx 1) (+ idx 1)))))
                             (c3 (if (> idx (- size 3)) nil (ord (substr str (+ idx 2) (+ idx 2))))))
                         (call cat (map base64-lookup (base64-encode-triplet c1 c2 c3)))))
                     blocks))))))

(if (not (= 1 (len args)))
    (err E_ARGS (cat verb " takes one string argument"))
    (let ((str (get args 0)))
      (base64-encode str)))
