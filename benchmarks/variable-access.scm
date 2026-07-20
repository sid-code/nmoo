;; Stress test for variable access performance.
;; Creates many variables and accesses them in a hot loop.
;; Run: nim c -r src/nmoo/util/eval benchmarks/variable-access.scm

(begin
  ;; Create a scope with many variables
  (let ((a 1) (b 2) (c 3) (d 4) (e 5) (f 6) (g 7) (h 8) (i 9) (j 10)
        (k 11) (l 12) (m 13) (n 14) (o 15) (p 16) (q 17) (r 18) (s 19) (t 20))
    (define inner-loop (lambda (count)
      (if (< count 500)
        (begin
          ;; Access all 20 variables, then write back
          (define a (+ a 1)) (define b (+ b 1)) (define c (+ c 1))
          (define d (+ d 1)) (define e (+ e 1)) (define f (+ f 1))
          (define g (+ g 1)) (define h (+ h 1)) (define i (+ i 1))
          (define j (+ j 1)) (define k (+ k 1)) (define l (+ l 1))
          (define m (+ m 1)) (define n (+ n 1)) (define o (+ o 1))
          (define p (+ p 1)) (define q (+ q 1)) (define r (+ r 1))
          (define s (+ s 1)) (define t (+ t 1))
          (inner-loop (+ count 1)))
        (begin))))
    (let ((start (time)))
      (inner-loop 0)
      (let ((elapsed (- (time) start)))
        (echo (cat "20-var access 500 iters: " ($ elapsed) "ms  ticks: " ($ (ticks-remaining)))))))

  ;; Lambda-heavy: define a function that captures many variables and call it repeatedly
  (let ((x1 1) (x2 2) (x3 3) (x4 4) (x5 5)
        (x6 6) (x7 7) (x8 8) (x9 9) (x10 10))
    (define captured-fn (lambda (n) (+ n x1 x2 x3 x4 x5 x6 x7 x8 x9 x10)))
    (define call-loop (lambda (n)
      (if (< n 200)
        (begin
          (captured-fn n) (captured-fn n) (captured-fn n)
          (captured-fn n) (captured-fn n)
          (call-loop (+ n 1)))
        (begin))))
    (let ((start (time)))
      (call-loop 0)
      (let ((elapsed (- (time) start)))
        (echo (cat "captured lambda 200x5:  " ($ elapsed) "ms  ticks: " ($ (ticks-remaining)))))))

  ;; Many recursive calls with variable access
  (define deep-loop (lambda (n a b c d e f g h)
    (if (< n 100)
      (deep-loop (+ n 1) (+ a 1) (+ b 1) (+ c 1) (+ d 1)
                           (+ e 1) (+ f 1) (+ g 1) (+ h 1))
      (begin))))
  (let ((start (time)))
    (deep-loop 0 0 0 0 0 0 0 0 0)
    (let ((elapsed (- (time) start)))
      (echo (cat "deep param access 100:  " ($ elapsed) "ms  ticks: " ($ (ticks-remaining))))))
)