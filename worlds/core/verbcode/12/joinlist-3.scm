(let
  ((lst (get args 0))
   (last-sep (get args 1))
   (if-empty (get args 2 "")))
   
  (cond 
    ((= 0 (len lst)) if-empty)
    ((= 1 (len lst)) (get lst 0))
    ((= 2 (len lst)) (cat ($ (get lst 0)) " " last-sep " " (get lst 1)))
    ((let
        ((last (get lst -1))
         (mod-lst (set lst -1 (cat last-sep " " last))))
         
        ($strutils:join mod-lst ", ")))))
