(let ((who (get args 0))
      (dest self.destination)
      (door self.door)
      (door-attempt (if door (door:try-enter who) 1)))
  (if (valid dest)
      (if door-attempt
          (do
           (move who dest)
           (dest:look))
          nil)
      (who:tell "Exit didn't work because room was invalid.")))
