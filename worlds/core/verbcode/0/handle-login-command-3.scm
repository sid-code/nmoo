(cond
  ((= command "connect")
    (if (< (len args) 2) (player:tell "Syntax: connect <name> <pass>")
        (let ((name  (get args 0))
              (passw (get args 1))
              (target-player (#0:find-player name)))
          
         (if (nil? target-player)
             (player:tell "Incorrect player/password combo.")
             (if (#0:check-pass target-player passw) 
                 (do
                  (notify self (cat "Login: " ($o target-player) " from " 
                                    player.address))
                  (setprop target-player "address" player.address)
                  target-player)
                 (do
                  (notify self (cat "Failed login attempt: " ($o target-player)
                                    " from " player.address))
                  (player:tell "Incorrect player/password combo.")))))))
  ((= command "request")
    (if (< (len args) 2) (player:tell "Syntax: request <name> <email>")
       (let ((name (get args 0))
            (email (get args 1)))
          
        (do
           (#0:process-char-request name email)
           (player:tell 
            "Your request is being processed. Expect an email.")))))
  ((do
    (player:tell "Available commands: ")
    (player:tell "  connect <name> <pass>    --- Connect to an existing character")
    (player:tell "  request <name> <email>   --- Request a new character"))))
