;; nmoo scripting benchmark
;; Run: nim c -r src/nmoo/util/eval benchmarks/scripting.nmf

(begin
  ;; ── 1. empty loop (recursion) ──
  (define loop-empty (lambda (n)
    (if (< n 50)
      (loop-empty (+ n 1))
      (begin))))
  (let ((start (time)))
    (loop-empty 0)
    (let ((elapsed (- (time) start)))
      (echo (cat "empty loop 50:        " ($ elapsed) "ms  ticks: " ($ (ticks-remaining))))))

  ;; ── 2. arithmetic ──
  (define loop-arithm (lambda (n)
    (if (< n 50)
      (begin
        (define n2 (* n n))
        (define n3 (/ n2 2))
        (define n4 (- n3 n))
        (loop-arithm (+ n 1)))
      (begin))))
  (let ((start (time)))
    (loop-arithm 0)
    (let ((elapsed (- (time) start)))
      (echo (cat "arithmetic 50:        " ($ elapsed) "ms  ticks: " ($ (ticks-remaining))))))

  ;; ── 3. map ──
  (let ((lst (range 1 50)))
    (let ((start (time)))
      (let ((mapped (map (lambda (x) (+ x 1)) lst)))
        (let ((elapsed (- (time) start)))
          (echo (cat "map 50 elems:         " ($ elapsed) "ms  len: " ($ (len mapped)) "  ticks: " ($ (ticks-remaining))))))))

  ;; ── 4. fold-right ──
  (let ((lst (range 1 50)))
    (let ((start (time)))
      (let ((folded (fold-right (lambda (a b) (+ a b)) 0 lst)))
        (let ((elapsed (- (time) start)))
          (echo (cat "fold-right 50:        " ($ elapsed) "ms  result: " ($ folded) "  ticks: " ($ (ticks-remaining))))))))

  ;; ── 5. reduce-left ──
  (let ((lst (range 1 50)))
    (let ((start (time)))
      (let ((reduced (reduce-left (lambda (a b) (+ a b)) lst)))
        (let ((elapsed (- (time) start)))
          (echo (cat "reduce-left 50:       " ($ elapsed) "ms  result: " ($ reduced) "  ticks: " ($ (ticks-remaining))))))))

  ;; ── 6. property access ──
  (define loop-prop (lambda (n)
    (if (< n 50)
      (begin
        #1.name
        #1.level
        (loop-prop (+ n 1)))
      (begin))))
  (let ((start (time)))
    (loop-prop 0)
    (let ((elapsed (- (time) start)))
      (echo (cat "prop get 50:          " ($ elapsed) "ms  ticks: " ($ (ticks-remaining))))))

  ;; ── 7. list construction ──
  (define build-list (lambda (n acc)
    (if (< n 50)
      (build-list (+ n 1) (push acc n))
      acc)))
  (let ((start (time)))
    (let ((biglist (build-list 0 (list))))
      (let ((elapsed (- (time) start)))
        (echo (cat "list push 50:         " ($ elapsed) "ms  len: " ($ (len biglist)) "  ticks: " ($ (ticks-remaining)))))))

  ;; ── 8. function call overhead ──
  (define identity (lambda (x) x))
  (define loop-calls (lambda (n)
    (if (< n 50)
      (begin
        (identity n)
        (identity n)
        (identity n)
        (loop-calls (+ n 1)))
      (begin))))
  (let ((start (time)))
    (loop-calls 0)
    (let ((elapsed (- (time) start)))
      (echo (cat "identity calls 50:    " ($ elapsed) "ms  ticks: " ($ (ticks-remaining))))))
)