(let ((exit-dir (get args 0)))
  (< 0 (len (self:get-exits-by-dir exit-dir))))
