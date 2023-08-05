(do
  (player:tell self.name)
  (player:tell 
    (try (self:description)
         "(No description set.)"))
  (player:tell (self:get-exit-str))
  (let ((cts (setremove self.contents player)))
    (if (= 0 (len cts))
        "Nothing"
        (player:tell "You see "
          ($strutils:joinlist
            (map (lambda (obj) obj.name) cts)
            "and" "nothing") "."))))
