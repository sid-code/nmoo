(let ((cts caller.contents))
  (if (= 0 (len cts))
      (player:tell "You are empty-handed.")
      (do 
       (player:tell "You are carrying:")
       (map (lambda (item) (player:tell " - " ($o item))) cts))))
