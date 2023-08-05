(let
  ((loc (getprop self "location" $nowhere))
   (player-loc (getprop player "location" $nowhere)))
   
  (if (= loc player-loc)
      (try
        (do
          (move self player)
          (player-loc:announce player (cat player.name " gets " self.name "."))
          (player:tell "Taken."))

        (player:tell "Could not get " self.name "!"))
      (player:tell self.name " is not here.")))
