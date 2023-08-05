(let ((src  self.source)
      (dest self.destination))
  (do
    (src:rm-exit self)
    (dest:rm-entrance self)
    self))
