(let ((token (get args 0))
      (search ($listutils:filter (lambda (pair) (= token (get pair 1))) self.access-tokens)))
  (if (< 0 (len search))
      (get (get search 0) 0)
      nil))
