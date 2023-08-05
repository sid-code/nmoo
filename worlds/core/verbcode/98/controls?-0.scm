(let ((user (get args 0))
      (what (get args 1)))
  (or (= 0 (level user))      ; user is a wizard
      (= what.owner user)     ; user owns the object
      what.pubwrite))         ; object is publicly writable
