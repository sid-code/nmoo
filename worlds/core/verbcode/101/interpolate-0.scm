;;; interpolate string with gender pronouns
;;; arguments: string, object in question
;;; ==== THE FOLLOWING IS TAKEN FROM LAMBDAMOO HELP FILE "help pronoun" ===
;;; The complete set of substitutions is as follows:
;;; 
;;;         %% => `%'  (just in case you actually want to talk about percentages).
;;;     Names:
;;;         %n => the player
;;;         %t => this object (i.e., the object issuing the message,... usually)
;;;         %d => the direct object from the command line
;;;         %i => the indirect object from the command line
;;;         %l => the location of the player
;;;     Pronouns:
;;;         %s => subject pronoun:          either `he',  `she', or `it'
;;;         %o => object pronoun:           either `him', `her', or `it'
;;;         %p => posessive pronoun (adj):  either `his', `her', or `its'
;;;         %q => posessive pronoun (noun): either `his', `hers', or `its'
;;;         %r => reflexive pronoun:  either `himself', `herself', or `itself'
;;;     General properties:
;;;         %(foo) => player.foo
;;;         %[tfoo], %[dfoo], %[ifoo], %[lfoo]
;;;                => this.foo, dobj.foo, iobj.foo, and player.location.foo
;;;     Object numbers:
;;;         %#  => player's object number
;;;         %[#t], %[#d], %[#i], %[#l]
;;;             => object numbers for this, direct obj, indirect obj, and location.
;;; 
;;; In addition there is a set of capitalized substitutions for use at the
;;; beginning of sentences.  These are, respectively,
;;; 
;;;    %N, %T, %D, %I, %L for object names,
;;;    %S, %O, %P, %Q, %R for pronouns, and
;;;    %(Foo), %[dFoo] (== %[Dfoo] == %[DFoo]),... for general properties
(let ((str (get args 0))
      (obj (get args 1))
      (get-identifier (lambda (o)
                        (if o
                            (try (o:name) (getprop o "name" ($ o)))
                            "(nil)")))
      (pct-n (get-identifier obj))
      (pct-t (get-identifier self))
      (pct-d (get-identifier dobj))
      (pct-d (get-identifier iobj))
      (pct-l (get-identifier obj.location))
      (x (player:tell (getprop obj "gender")))
      (gender (getprop obj "gender" $gender))
      (pct-s gender.subject)
      (pct-o gender.object)
      (pct-p gender.posadj)
      (pct-q gender.posnoun))
  ($strutils:gsub str "%%(%%|[#ntdilsopqrNTDILSOPQR]|%[[^%]]%])"
                  (lambda (start end capture)
                    (get capture 0))))