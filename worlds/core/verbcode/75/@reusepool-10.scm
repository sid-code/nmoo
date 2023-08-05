;;; Measure the pool size in 2 ways: (len (children $garbage)) and
;;; (len $recycler.contents) and report if they don't agree.
    
(let ((pool-size-1 (len (children $garbage)))
      (pool-size-2 (len $recycler.contents)))
  (if (= pool-size-1 pool-size-2)
      (player:tell "There are " pool-size-1 " garbage objects ready for "
                   "reuse.")

      (do (player:tell "Discrepancy exists between (children $garbage) and "
                       "$recycler.contents (former = " pool-size-1
                       ", latter = " pool-size-2 ").")

          (if (> (len args) 0)
              (do (player:tell "Attempting to remedy this...")
                  (map (lambda (child) ($recycler:_recycle child)) (children $garbage))
                  (player:tell "Success."))
              (player:tell "Use '" verb " fix' to fix this.")))))
