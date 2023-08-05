(let ((dest self.destination))
  (if (= dest $nowhere)
      (player:tell "This portal leads to nowhere!")
      (do
        (player:tell self.entermsg)
        (move player dest)
        (dest:look))))
