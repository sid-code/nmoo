(let
  ((name (downcase (get args 0)))
   (players ($objutils:descendents $player))
   (matching-players
      ($listutils:filter (lambda (pl) (= (downcase pl.name) name)) players)))
  
  (get matching-players 0 nil))
