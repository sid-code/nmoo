;;; Syntax: @dig <new-room-name>
;;;     or: @dig <dir> to <new-room-name>
;;;     or: @dig <dir> to <existing-room-number>

(do
    (settaskperms caller)
    (cond
     ((= 0 (len argstr))
      (player:tell "Syntax: <INSERT HELP HERE>"))
     ((= -1 (index argstr " to ")) ; no exit specified
      (let ((new-room (self:new-room-named argstr)))
	(player:tell "New room created: " ($o new-room))))
     ((let ((spl (split argstr " to "))
	    (dir (get spl 0))
	    (full-dir ($strutils:expand-exit-name dir))
	    (new-name (get spl 1))
	    (loc (getprop caller "location")))
	(cond
	 ((= 0 (len dir))
	  (player:tell "You need to specify a direction."))
	 ((= 0 (len new-name))
	  (player:tell "You need to specify a new name."))
	 ((loc:has-exit-dir? full-dir)
	  (player:tell "An exit in direction " full-dir " already exists!"))
	 ((let ((other-room 
		 (if (nil? iobj)
		     (let ((new-room (self:new-room-named new-name)))
		       (do
			   (player:tell "New room created: " ($o new-room))
			   new-room))
		     iobj))
		(new-exit (self:new-exit full-dir loc other-room)))
	    (do
		(player:tell "New exit created: " ($o new-exit))
		(player:tell "Attempting to link " loc " to " other-room
			     " in direction " full-dir ".")
	      (try (do
		       (self:connect-rooms-with loc other-room new-exit)
		       (player:tell "Success!"))
		   (if (erristype error E_PERM)
		       (player:tell "I couldn't link the room.  Perhaps you could"
				    " ask this room's owner?")
		       error))))))))))
