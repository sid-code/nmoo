(let
  ((target (get args 0))
   (passw  (get args 1))
   (player-phash (getprop target "password-hash" ""))
   (player-salt  (getprop target "password-salt" "")))

  (= player-phash (phash passw player-salt)))
