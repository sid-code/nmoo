(let ((pl (get args 0))) ; the player
  (if self.open 1 (do (pl:tell self.closedmsg) 0)))
