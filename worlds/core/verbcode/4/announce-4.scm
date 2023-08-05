(let
  ((announcer (get args 0))
   (msg (get args 1))
   (who (setremove self.contents announcer)))
  
  (map (lambda (obj) (obj:tell msg)) who))
