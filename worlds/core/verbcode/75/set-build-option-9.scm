;;; (:set-build-option option new-value)
;;; Sets the build option `option` to `new-value`

(if (not (or (= caller self) ($permutils:controls? caller self)))
    (err E_PERM (cat caller " cannot modify build options of " self))
    (let ((option (get args 0))
          (new-value (get args 1)))
      (setprop self "build-options"
        ($buildopts:set self.build-options option new-value))))
