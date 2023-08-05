(list 200
      (table ("Content-Type" ($webutils:guess-mime self.asset-path)))
      self.data)
