(do
 (settaskperms player)
 (map (lambda (ex)
        (let ((dest ex.destination))
          (dest:rm-entrance ex)))
      self.exits))
