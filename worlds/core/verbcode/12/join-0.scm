(let
  ((lst (get args 0))
   (sep (get args 1 "")))
   
  (if (= 0 (len lst))
      ""
      (reduce-right (lambda (cur nxt) (cat ($ cur) sep ($ nxt))) lst)))
