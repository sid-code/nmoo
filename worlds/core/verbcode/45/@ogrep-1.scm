(let ((search (get args 0)))
  ($objutils:for-each-obj
   (lambda (obj)
     (do
      (let ((name (getprop obj "name" nil)))
        (or (nil? name)
            (let ((find-result (find name search)))
              (and find-result
                   (player:tell ($o obj))))))
      (suspend 0.1)))))
