(do
  (player:tell "You say, \"" argstr "\"")
  (self:announce player (cat player.name " says, \"" argstr "\"")))
