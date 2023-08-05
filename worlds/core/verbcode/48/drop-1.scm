(let
  ((loc (getprop self "location" $nowhere))
   (player-loc (getprop player "location" $nowhere)))
   
  (if (= loc player)
      (try
        (do
          (move self player-loc)
          (player-loc:announce player (cat player.name " drops " self.name "."))
          (player:tell "Dropped."))
	  ;catch
        (player:tell "Could not drop " self.name "!"))
      (player:tell "You are not carrying " self.name ".")))
