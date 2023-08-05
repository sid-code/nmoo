(let ((path (get args 0))
      (dest (get args 1))
      (routes self.routes))

  (cond
   ;; routes must point to a valid object
   ((not (valid dest))
    (err E_ARGS (cat dest " is not a valid object")))

   ;; the route cannot already exist
   ((not (nil? ($listutils:assoc routes path)))
    (err E_ARGS (cat "route " path " already exists")))

   ;; all checks passed
   ((setprop self "routes"
               (push self.routes (list path dest))))))
