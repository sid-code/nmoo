(reduce-right (lambda (l1 l2) (do (echo l1 l2) (reduce-right (lambda (x y) (+ x y)) l1))) '((1 
2 3) (4 5 6)))
