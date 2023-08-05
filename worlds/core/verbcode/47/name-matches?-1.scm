(let ((vname (get args 0))
      (str   (get args 1))
      (rname (strsub vname "*" ""))
      (slen  (len str))
      (vlen  (len rname))
      (star-index (index vname "*"))
      (star-loc (if (= -1 star-index) 9000000000 star-index)))
  (cond ((= slen vlen) (= str rname))
        ((> slen vlen)
         (and (= star-loc vlen) (= rname (substr str 0 (- vlen 1)))))
        ((< slen vlen)
         (and (<= star-loc slen) (= str (substr rname 0 (- slen 1)))))
        (("empty else clause"))))
