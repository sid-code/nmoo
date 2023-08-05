;;; (:build-option option default=0)
;;; Returns the build option specified by `option`

(if (not (or (= caller self) ($permutils:controls? caller self)))
    (err E_PERM (cat caller " cannot access build options of " self))
    (let ((option (get args 0))
          (default (get args 1 0)))
      ($buildopts:get self.build-options option default)))
