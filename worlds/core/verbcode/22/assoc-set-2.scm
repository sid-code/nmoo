;;; (:assoc-set assoclist key new-value)
;;; If a `(key, any-value)` pair exists in `assoclist`, it is removed.
;;; Then, a `(key, new-value)` pair is added to `assoclist`.


(let ((assoclist    (get args 0))
      (key          (get args 1))
      (new-value    (get args 2))
      (existing     (self:assoc-pair assoclist key (list key new-value)))
      (new-existing (set existing 1 new-value)))
  (setadd (setremove assoclist existing) new-existing))
