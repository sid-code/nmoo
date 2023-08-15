import unittest
import options
import tables
import strutils
import std/sets

import types
import server
import querying
import scripting
import verbs
import compile
import tasks
import objects

suite "core data tests":
  test "== operator compares MData values properly":
    var
      x = 2.md
      y = 2.md

    check x == y

    x = @[1.md, "two".md, "three".mds].md
    y = @[1.md, "two".md, "three".mds].md

    check x == y

    x = @[2.md, "two".md, "three".mds].md

    check x != y

  test "== ignores line number information for MData":
    var
      x = 2.md
      y = 2.md

    x.pos = (10, 5)
    y.pos = (10, 6)

    check x == y

  test "`$` works":
    let x = @[@[1.md, 2.md, 3.md].md, 3.md].md
    check ($x) == "((1 2 3) 3)"

suite "object tests":
  setup:
    var world = createWorld("test", persistent = false)
    var root = blankObject()
    objects.initializeBuiltinProps(root)
    world.add(root)
    root.owner = root
    root.setPropR("name", "root")
    root.setPropR("aliases", @[])
    root.setPropR("rootprop", "yes")
    check root.setPropChildCopy("rootprop", true)

    var genericContainer = root.createChild()
    world.add(genericContainer)
    genericContainer.setPropR("name", "generic container")
    genericContainer.setPropR("contents", @[])

    var nowhere = genericContainer.createChild()
    world.add(nowhere)

    var genericThing = root.createChild()

    world.add(genericThing)
    genericThing.setPropR("name", "generic thing")
    check genericThing.moveTo(nowhere)

    genericContainer.changeParent(genericThing)

    check genericContainer.moveTo(nowhere)

    check nowhere.getContents().len == 2

  test "property inheritance works":
    var child = root.createChild()
    world.add(child)
    child.setPropR("name", "child")

    var evenMoreChild = child.createChild()
    world.add(evenMoreChild)
    evenMoreChild.setPropR("rootprop", "no")

    check child.getPropVal("rootprop").strVal != "no"
    child.changeParent(evenMoreChild)

    check child.getPropVal("rootprop").strVal == "no"

  test "query works":
    var o1 = genericThing.createChild()
    world.add(o1)

    var o2 = genericContainer.createChild()
    world.add(o2)

    o2.setPropR("contents", @[])
    discard o1.moveTo(o2)

    o1.setPropR("aliases", @["thingy".md])
    let contents = o2.getContents()

    check contents.len == 1
    check o2.query("thin").len == 1

  # TODO: fix this and the next one
  test "verbs fire correctly":
    var verb = newVerb(
      names = "action",
      owner = root.id,
      doSpec = oThis,
      prepSpec = pOn,
      ioSpec = oThis,
    )

    root.verbs.add(verb)

    check verb.setCode("(do argstr)", root) == E_NONE.md
    #check $root.handleCommand("action root on root") == "@[\"root on root\"]"
    check true

  test "verbs call correctly":
    var verb = newVerb(
      names = "action",
      owner = root.id,
      prepSpec = pNone,
      doSpec = oNone,
      ioSpec = oNone,
    )

    root.verbs.add(verb)

    check verb.setCode("(do args)", root) == E_NONE.md
    #check $root.verbCall("action", root, @["hey".md]) == "@[@[\"hey\"]]"
    check true

suite "parser":
  setup:
    proc parse(str: string, options: set[MParserOption] = {}): MData {.used.} =
      var parser = newParser(str, options)
      result = parser.parseFull()
      if parser.error.errVal != E_NONE:
        return parser.error
    proc parseOne(str: string, options: set[MParserOption] = {}): MData {.used.} =
      var parser = newParser(str, options)
      result = parser.parseAtom()
      if parser.error.errVal != E_NONE:
        return parser.error

  test "parser works":
    let parsed = parse("(echo \"hello world\" (sub-list \"who knew?\" 3.14))")

    check parsed == @["do".mds, @["echo".mds, "hello world".md, @["sub-list".mds, "who knew?".md, 3.14.md].md].md].md

  test "quote works":
    let parsed = parse("'(1 2 3)")
    check parsed == @["do".mds, @["quote".mds, @[1.md, 2.md, 3.md].md].md].md

  test "quasiquote/unquote works":
    let parsed = parse("`(2 3 ,(x))")
    check parsed == @["do".mds, @["quasiquote".mds, @[2.md, 3.md, @["unquote".mds, @["x".mds].md].md].md].md].md

  test "parser expands (obj:verb) shorthand correctly":
    let parsed = parse("(#0:filter closed door-list)")
    check parsed == @["do".mds, @["verbcall".mds, 0.ObjID.md, "filter".md, @["list".mds, "closed".mds, "door-list".mds].md].md].md

  test "parser handles weird cases":
    var parsed = parse("((((()))))")
    check parsed.isType(dList)

    parsed = parse("((((((")
    check parsed.isType(dErr)

  test "parser propogates unexpected token errors properly":
    let parsed = parse("(let ((x 5) (y '(lambda (x) (+ x ))))) stuff)")
    check parsed.isType(dErr)

  test "parser treats 5.5.5 as a symbol":
    let parsed = parse("5.5.5")
    check parsed == @["do".mds, "5.5.5".mds].md

  test "parser treats 5.5 as a float":
    let parsed = parse("5.5")
    check parsed == @["do".mds, md(5.5)].md

  test "parser rejects trailing parens":
    let parsed = parse("(abc))")
    check parsed.isType(dErr)

  test "parser parses serialized tables properly":
    let parsed = parseOne("(table (1 2) (3 4))", { poTransformDataForms })
    check parsed.isType(dTable)
    check parsed.tableVal.len == 2

  test "parser handles \\n escapes properly":
    let parsed = parseOne("\"abc\\ndef\"")
    check parsed == "abc\ndef".md

  test "parser handles \\xHH escapes properly":
    var parsed = parseOne("\"abc\\x0adef\"")
    check parsed == "abc\ndef".md

    parsed = parseOne("\"abc\\x11\\x22\\xFF\"")
    check parsed == "abc\x11\x22\xFF".md


suite "evaluator":
  setup:
    var world = createWorld("test", persistent = false)
    var root = blankObject()
    initializeBuiltinProps(root)
    root.changeParent(root)
    root.level = 0
    world.add(root)

    root.output = proc (o: MObject, msg: string) =
      echo "Sent to $#: $#".format(o, msg)

    var worthy = root.createChild()
    worthy.level = 0
    world.add(worthy)

    var unworthy = root.createChild()
    world.add(unworthy)
    unworthy.level = 3

    var verb = newVerb(
      names = "verb name",
      owner = root.id,
      doSpec = oNone,
      prepSpec = pWith,
      ioSpec = oNone
    )
    root.verbs.add(verb)

    root.setPropR("name", "root")

    var symtable = newSymbolTable()
    proc evalS(code: string, who: MObject = root): MData =
      let name = "test task"
      let compiled = compileCode(code, who)
      if compiled.error != E_NONE.md:
        return compiled.error

      let t = world.addTask(name, who, who, who, who, symtable, compiled, ttFunction, none(TaskID))

      let tr = world.run(t)
      case tr.typ:
        of trFinish:
          return tr.res
        of trError:
          return tr.err
        of trTooLong:
          return E_QUOTA.md("task took too long!")
        else:
          return nilD

    # macro to test later
    let loopcode {.used.} = """
(define-syntax loop
  (lambda (form)
    (if (not (= (len form) 5))
        (err E_ARGS "loop takes 4 arguments")
        (let ((loopvars (get form 1))
              (initvals (get form 2))
              (cont-symbol (get form 3))
              (body (get form 4)))
          (if (not (istype loopvars "sym"))
              (err E_ARGS "first argument to loop must be a symbol")
              nil)
          (if (not (istype initvals "list"))
              (err E_ARGS "second argument to loop must be a list")
              nil)
          (if (not (istype cont-symbol "sym"))
              (err E_ARGS "third argument to loop must be a symbol")
              nil)
          `(let ((_CONT (call-cc (lambda (cont)
                                   (cont (list cont ,initvals)))))
                 (,loopvars (get _CONT 1))
                 (,cont-symbol (lambda (vals)
                              ;; avoid nasty surprises
                              (let ((realvals (if (istype vals "list") vals (list vals)))
                                    (continuation (get _CONT 0)))
                                (call continuation (list (list continuation realvals)))))))
             ,body)))))
"""
  test "recursive define statement works":
    let result = evalS("""
    (do
      (define x (lambda (y) (if (< y 1) 0 (+ y (call x (list (- y 1)))))))
      (call x (list 5)))""")
    check result == 15.md

  test "define statement works":
    let result = evalS("(do (define x 100) x)")
    check result == 100.md

  test "define statement binds symbols locally":
    let result = evalS("""
    (let ((x "unshadowed outer value")
          (lam (lambda (arg) (do (define x arg) x))))
      (list x (lam 100)))
    """)
    check result == @["unshadowed outer value".md, 100.md].md

  test "define bindings disappear once out of scope":
    let result = evalS("""
    (let ((lam (lambda (arg) (do (define x arg) x))))
      (list (lam 100))
      x)
    """)

    check result.isType(dErr)
    check result.errVal == E_UNBOUND
    # Make sure it's happening in the right place.  Line 1's usage is
    # legitimate, line 3's usage should be where the error is.
    check result.trace[0].pos.line == 3

  test "define bindings are accessible from define-syntax":
    let result = evalS("""
    (define x 123)
    (define-syntax makro (lambda (code) x))
    (makro)
    """)

    check result == 123.md

  test "define lambda works from define-syntax":
    let result = evalS("""
    (define fn (lambda (x) (+ x 1)))
    (define-syntax plusone (lambda (code) (map fn (tail code))))
    (plusone 1 2 3)
    """)

    check result == @[2.md, 3.md, 4.md].md

  test "recursive define lambda works from define-syntax":
    let result = evalS("""
    (define fn (lambda (x) (if (< x 1) 0 (+ x (fn (- x 1))))))
    (define-syntax plusone (lambda (code) (map fn (tail code))))
    (plusone 1 2 3)
    """)

    check result == @[2.md, 3.md, 4.md].md

  test "let statement binds symbols locally":
    let result = evalS("""
    (do (let ((a "b") (b a)) b) (echo a))
    """)

    check result.isType(dErr)
    check result.errVal == E_UNBOUND

  test "let statement accepts multiple body forms":
    let result = evalS("""
    (let ((a 5) (b 10)) a b)
    """)

    check result == 10.md

  test "let statement shadows properly":
    let result = evalS("""
    (let ((a 5))
      (list
       a
       (let ((a 10))
         a)
       a))
    """)

    check result == @[5.md, 10.md, 5.md].md

  test "cond statement works":
    var result = evalS("""
    (cond (1 "it works") (0 "it doesn't work") ("it doesn't work!!!"))
    """)

    check result.isType(dStr)
    check result.strVal == "it works"

    result = evalS("""
    (cond (0 "whoops") ("it works"))
    """)

    check result.isType(dStr)
    check result.strVal == "it works"

  test "parse statement works":
    let result = evalS("""
    (parse "(a b (c d e) 4.5)")
    """)

    check result == @["a".mds, "b".mds, @["c".mds, "d".mds, "e".mds].md, 4.5.md].md

  test "eval statement works":
    let result = evalS("""
      (eval '(call (lambda (x) (+ x x)) (5)))
    """)

    check result == 10.md

  test "getprop statement works":
    var result = evalS("""
    (getprop #1 "name")
    """)

    check result.isType(dStr)
    check result.strVal == "root"

  test "getprop raises error if property not found":
    var result = evalS("""(getprop #1 "doodoo")""")
    check result.isType(dErr)
    check result.errVal == E_PROPNF

  test "getpropinfo works":
    var result = evalS("""(getpropinfo #1 "name")""")
    check result.isType(dList)
    var rl = result.listVal
    check rl.len == 2
    check rl[0].isType(dObj)
    check rl[0] == root.md
    check rl[1].isType(dStr)

  test "setprop statement works":
    var result = evalS("""
    (setprop #1 "newprop" "val")
    """)

    check result.isType(dStr)
    check result.strVal == "val"

    result = evalS("""
    (getprop #1 "newprop")
    """)

    check result.isType(dStr)
    check result.strVal == "val"

  test "setprop correctly changes property value":
    discard evalS("""
    (setprop #1 "newprop" 400)
    """)
    discard evalS("""
    (setprop #1 "newprop" 450)
    """)

    var result = evalS("""
    (getprop #1 "newprop")
    """)

    check result == 450.md

  test "setprop checks permissions":
    let result = evalS("""
    (setprop #1 "newprop" "oops")
    """, unworthy)

    check result.isType(dErr)
    check result.errVal == E_PERM

  test "setprop sets owner of new properties correctly":
    var result = evalS("""
    (setprop #1 "newprop" "newval")
    """, worthy)

    check result.isType(dStr)
    let prop = root.getProp("newprop")
    check(not isNil(prop))
    check prop.owner == worthy

  test "setpropinfo works":
    var result = evalS("""(setpropinfo #1 "name" (#1 "rw" "name1"))""")
    check result.isType(dObj)
    check result.objVal.int == 1
    let prop = root.getProp("name1")
    check(not isNil(prop))
    check prop.name == "name1"
    check prop.pubWrite
    check prop.pubRead
    check(not prop.ownerIsParent)

  test "setpropinfo checks permissions":
    var result = evalS("""(setpropinfo #1 "name" (#1 "rw" "name1"))""", unworthy)
    check result.isType(dErr)
    check result.errVal == E_PERM

  test "props statement works":
    var result = evalS("(props #1)", worthy)
    check "name".md in result.listVal
    check "owner".md in result.listVal
    check "location".md in result.listVal
    check "contents".md in result.listVal
    check "pubread".md in result.listVal
    check "pubwrite".md in result.listVal
    check "fertile".md in result.listVal

  test "props checks permissions":
    root.pubRead = false
    var result = evalS("(props #1)", unworthy)
    check result.isType(dErr)

  test "verbs statement works":
    var result = evalS("(verbs #1)", worthy)
    check result == @["verb name".md].md

  test "verbs checks permissions":
    root.pubRead = false
    var result = evalS("(verbs #1)", unworthy)
    check result.isType(dErr)

  test "getverbinfo statement works":
    var result = evalS("(getverbinfo #1 \"verb\")")
    check result.isType(dList)
    check result.listVal.len == 3
    check result.listVal[0].isType(dObj)
    check result.listVal[1].isType(dStr)
    check result.listVal[2].isType(dStr)

  test "setverbinfo statement works":
    var result = evalS("(setverbinfo #1 \"verb\" (#1 \"rwx\" \"new ve*rb name\"))")
    result = evalS("(getverbinfo #1 \"verb\")")
    check result == @[1.ObjID.md, "rwx".md, "new ve*rb name".md].md

  test "getverbargs statement works":
    var result = evalS("(getverbargs #1 \"verb\")")
    check result.isType(dList)
    check result.listVal.len == 3

  test "setverbargs statement works":
    var result = evalS("(setverbargs #1 \"verb\" (\"any\" \"in front of\" \"any\"))")
    check result.isType(dObj)
    check verb.doSpec == oAny
    check verb.prepSpec == pInFront
    check verb.ioSpec == oAny

  test "addverb statement works":
    var result = evalS("(addverb #1 \"cool varb\")")
    result = evalS("(getverbinfo #1 \"cool\")")
    check result == @[1.ObjID.md, "rx".md, "cool varb".md].md
    result = evalS("(getverbargs #1 \"cool\")")
    check result == @["none".md, "none".md, "none".md].md

  test "delverb statement works":
    var result = evalS("(addverb #1 \"cool varb\")")
    let beforelen = root.verbs.len
    result = evalS("(delverb #1 \"cool\")")
    let afterlen = root.verbs.len

    check beforelen == afterlen + 1

  test "try statement works":
    var result = evalS("(try (echo unbound) 4)")
    check result == 4.md

    result = evalS("(try \"no error here!\" (echo \"incorrect except fire\") 4)")

    check result == 4.md

  test "erristype statement works":
    var result = evalS("(try (+ a b) ((erristype error E_UNBOUND) (erristype error E_ARGS)))")
    check result == @[1.md, 0.md].md

  test "move statement works":
    suite "move statement":
      setup:
        var genericContainer = root.createChild()
        world.add(genericContainer)
        genericContainer.setPropR("name", "generic container")
        genericContainer.setPropR("contents", @[])

        var nowhere = genericContainer.createChild()
        world.add(nowhere)
        nowhere.setPropR("name", "nowhere")

        var genericThing = root.createChild()
        world.add(genericThing)
        genericThing.setPropR("name", "generic thing")
        check genericThing.moveTo(nowhere)

        genericContainer.changeParent(genericThing)

        symtable["gencont"] = genericContainer.md
        symtable["nowhere"] = nowhere.md
        symtable["genthing"] = genericThing.md

        # Set up accept verb for containers
        discard evalS("""
        (do
          (addverb gencont "accept")
          (setverbcode gencont "accept" "1"))
        """)

      test "moved object is in destination":
        let result = evalS("(move gencont nowhere)")
        check genericContainer.getLocation() == nowhere
        let contents = nowhere.getContents()
        check genericContainer in contents

      test "move removes objects from previous location":
        let result = evalS("(move genthing gencont)")
        let contents = nowhere.getContents()
        check contents.len == 0

        # for good measure
        check genericThing.getLocation() == genericContainer

      test "recursive move is forbidden":
        let result = evalS("(move gencont gencont)")
        check result.isType(dErr)
        check result.errVal == E_RECMOVE

  test "lambda statement works":
    var result = evalS("(lambda (x y) (do x y))")
    check result.isType(dList)

  test "lambda variable can be called directly":
    var result = evalS("(let ((fn (lambda (x y) (do x y)))) (fn 1 2))")
    check result == 2.md

  test "call-cc works":
    var result = evalS("(call-cc (lambda (x) (call x (5))))")
    check result == 5.md

  test "call statement works on lambdas":
    var result = evalS("(call (lambda (x y) (do x y)) (4 5))")
    check result == 5.md

  test "call statement works on builtins":
    var result = evalS("(call do (4 5))")
    check result == 5.md

  test "verbcall statement works":
    var obj = root.createChild()
    world.add(obj)

    var fverb = newVerb(
      names = "funcverb",
      owner = obj.id,
    )

    check fverb.setCode("(get args 0)", root) == E_NONE.md
    discard obj.addVerb(fverb)

    symtable["obj"] = obj.md

    var result = evalS("(verbcall obj \"funcverb\" (3 4 5))")
    check result == 3.md

  test "istype statement works":
    var result = evalS("(istype \"abc\" \"str\")")
    check result == 1.md

    result = evalS("(istype 3 \"int\")")
    check result == 1.md

    result = evalS("(istype 3 \"str\")")
    check result == 0.md

    result = evalS("(istype 3 \"doodoo\")")
    check result.isType(dErr)

  test "map statement works":
    var result = evalS("(map do (1 2 3 4))")
    check result.isType(dList)
    check result.listVal.len == 4

    result = evalS("(map (lambda (x) (do x)) (1 2 3 4))")
    check result.isType(dList)
    check result.listVal.len == 4

  test "nested map statement works":
    let result = evalS("""
(map (lambda (x) (map (lambda (y) (+ y 1)) x))
  (list (list 1 2 3) (list 2 3 4) (list 3 4 5)))
    """)

    check result == @[
      @[2.md, 3.md, 4.md].md,
      @[3.md, 4.md, 5.md].md,
      @[4.md, 5.md, 6.md].md].md

  test "pathological map case works":
      let result = evals("""(define l
  (lambda (x)
    (map (lambda (y) (l (- y 1)))
         (range 1 x))))
(l 4)""")

      check result == @[@[].md, @[@[].md].md, @[@[].md, @[@[].md].md].md,
        @[@[].md, @[@[].md].md, @[@[].md, @[@[].md].md].md].md].md

  test "fold-right and friends work":
    var result = evalS("(fold-right + 0 (1 2 3 4))")
    check result == 10.md

    result = evalS("(reduce-right + (1 2 3 4))")
    check result == 10.md

    result = evalS("(fold-right (lambda (x y) (+ x (* 2 y))) 0 (1 3 5 7))")
    check result == 32.md

  test "nested fold-right works":
    var result = evalS("""
(let ((add-l (lambda (x y) (+ x y))))
  (reduce-right (lambda (l1 l2) (call add-l (list (reduce-right add-l l1) (reduce-right add-l l2))))
    (list (list 1 2 3) (list 4 5 6))))
    """)

    check result == 21.md

  test "arithmetic works":
    var result = evalS("(+ 3 4)")
    check result == 7.md

    result = evalS("(+ 3.0 4)")
    check result == 7.0.md

    result = evalS("(- 4 2)")
    check result == 2.md

    result = evalS("(* 4 2)")
    check result == 8.md

    result = evalS("(/ 4 2)")
    check result == 2.md
    result = evalS("(/ 4 3)")
    check result == 1.md
    result = evalS("(/ 3 4.0)")
    check result == 0.75.md

    result = evalS("(+ 3 (- 2 1))")
    check result == 4.md

  test "table constructor works":
    var result = evalS("(table)")
    check result.dtype == dTable
    check len(result.tableVal) == 0

    result = evalS("(table (5 10) (10 20) '(a 40))")
    check result.dtype == dTable
    let tab = result.tableVal
    check len(tab) == 3
    check tab[5.md] == 10.md
    check tab[10.md] == 20.md
    check tab["a".mds] == 40.md

  test "table constructor errors on invalid arguments":
    var result = evalS("(table 5)")
    check result == E_ARGS.md

    result = evalS("(table (5) (10))")
    check result == E_ARGS.md

  test "= statement works":
    var result = evalS("(= 3 3)")
    check result == 1.md

    result = evalS("(= (list 3 3 \"cat\" (table (4 4) (3 3))) (list 3 3 \"cat\" (table (4 4) (3 3))))")
    check result == 1.md

    result = evalS("(= (3 3 \"cat\" 4) (3 3 \"cat\"))")
    check result == 0.md

  test "cat statement works":
    var result = evalS("(cat (1 2 3) (2 3 4))")
    check result.isType(dList)
    check result.listVal.len == 6

    result = evalS("(cat \"abc\" \"def\")")
    check result.isType(dStr)
    check result.strVal == "abcdef"

  test "unshift statement works":
    var result = evalS("(unshift (1 2) 1)")
    check result.isType(dList)
    check result.listVal.len == 3

  test "len statement works":
    var result = evalS("(len (1 \"a\" (1 2 3)))")

    check result == 3.md

  test "len statement works on tables":
    var result = evalS("(len (table (1 \"a\") (2 3)))")

    check result == 2.md

  test "head statement works":
    var result = evalS("(head (1 2 3 4))")
    check result == 1.md

    result = evalS("(head ())")
    check result == nilD

  test "tail statement works":
    var result = evalS("(tail (1 2 3 4))")
    check result.isType(dList)
    check result.listVal.len == 3

    result = evalS("(tail ())")
    check result.isType(dList)
    check result.listVal.len == 0

  test "delete statement works":
    var result = evalS("(delete (1 2 1 1) 3)")
    check result == @[1.md, 2.md, 1.md].md

  test "insert statement works":
    var result = evalS("(insert (1 1) 1 2)")
    check result == @[1.md, 2.md, 1.md].md

  test "push statement works":
    var result = evalS("(push (1 2) 1)")
    check result == @[1.md, 2.md, 1.md].md

  test "set statement works":
    var result = evalS("(set (1 2 3) 9 4)")
    check result.isType(dErr)
    check result.errVal == E_BOUNDS

    result = evalS("(set (1 2 3) 2 1)")
    check result == @[1.md, 2.md, 1.md].md

  test "get statement works":
    var result = evalS("(get (1 2 3) 1)")
    check result == 2.md

  test "setadd statement works":
    var result = evalS("(setadd (1 2 3) 2)")
    check result.listVal.len == 3

    result = evalS("(setadd (1 2) 3)")
    check result.listVal.len == 3

  test "setremove statement works":
    var result = evalS("(setremove (1 2 3) 2)")
    check result.listVal.len == 2

    result = evalS("(setremove (1 2) 3)")
    check result.listVal.len == 2

  test "setdiff statement works":
    var result = evalS("(setdiff (1 2 3 4 5) (1 2 9))")
    check result.listVal.toHashSet == @[3.md, 4.md, 5.md].toHashSet

    result = evalS("(setdiff () (1 2 9))")
    check result == @[].md

  test "setdiffsym statement works":
    var result = evalS("(setdiffsym (1 2 3 4 5) (1 2 9))")
    check result.listVal.toHashSet == @[3.md, 4.md, 5.md, 9.md].toHashSet

    result = evalS("(setdiffsym () (1 2 9))")
    check result.listVal.toHashSet == @[1.md, 2.md, 9.md].toHashSet

  test "tget statement works":
    var result = evalS("(tget (table (1 10) (2 20)) 2)")
    check result == 20.md

    result = evalS("(tget (table (1 10) (2 20)) 4)")
    check result == E_BOUNDS.md

    result = evalS("(tget (table (1 10) (2 20)) 4 nil)")
    check result == nilD

  test "tset statement works":
    var result = evalS("(tset (table (1 10) (2 20)) 1 20)")
    check result.dtype == dTable
    check result.tableVal.len == 2
    check result.tableVal[1.md] == 20.md

    result = evalS("(tset (table (1 10) (2 20)) 3 20)")
    check result.dtype == dTable
    check result.tableVal.len == 3
    check result.tableVal[3.md] == 20.md

    result = evalS("(tset (table (1 10) (2 20)) 3)")
    check result == E_ARGS.md

  test "in statement works":
    var result = evalS("(in (1 2 3) 3)")
    check result.intVal == 2

    result = evalS("(in (1 2 3) 4)")
    check result.intVal == -1

    result = evalS("(in () 4)")
    check result.intVal == -1

  test "substr statement works":
    var result = evalS("""(substr "01234567" 2 5)""")
    check result == "2345".md

    result = evalS("""(substr "01234567" 30 50)""")
    check result.errVal == E_ARGS

  test "substr handles negative indices":
    var result = evalS("""(substr "01234567" 0 -1)""")
    check result == "01234567".md

    result = evalS("""(substr "01234567" 2 -2)""")
    check result == "23456".md

    result = evalS("""(substr "01234567" -1 2)""")
    check result.isType(dErr)

    result = evalS("""(substr "01234567" -100 2)""")
    check result.isType(dErr)

  test "splice statement works":
    var result = evalS("""(splice "abcdef" 1 4 "1234")""")
    check result == "a1234f".md

    result = evalS("""(splice "abcdef" 1 -1 "123")""")
    check result == "a123".md

    result = evalS("""(splice "abcdefghijklmnop" 1 -2 "123")""")
    check result == "a123p".md

    result = evalS("""(splice "abcdefghijklmnop" 1 -10 "123")""")
    check result == "a123hijklmnop".md

    result = evalS("""(splice "abcdefghijklmnop" 40 -10 "123")""")
    check result.isType(dErr)

    result = evalS("""(splice "abcdefghijklmnop" -1 10 "123")""")
    check result.isType(dErr)

  test "index statement works":
    var result = evalS("(index \"abcdefghij\" \"def\")")
    check result.intVal == 3

    result = evalS("(index \"abcdefghij\" \"adef\")")
    check result.intVal == -1

  test "range statement works":
    var result = evalS("(range 10 15)")
    check result == @[10.md, 11.md, 12.md, 13.md, 14.md, 15.md].md

  test "match statement works":
    var result = evalS("(match \"abcdef\" \"a(%w+)f\")")
    check result.isType(dList)
    let captures = result.listVal
    check captures.len == 1
    check captures[0] == "bcde".md

  test "find statement works":
    var result = evalS("""(find "hello %[n]" "%%%[([^%]]+)%]")""")
    check result == @[6.md, 9.md, @["n".md].md].md

    result = evalS("""(find "ayy lmao" "y" 3)""")
    check result == nilD

    result = evalS("""(find "ayy lmao" "y" 2)""")
    check result == @[2.md, 2.md, @[].md].md

  test "gsub statement works":
    var result = evalS("""(gsub "a <bc> <defghi>" "<([^>]+)>" "$1")""")
    check result == "a bc defghi".md

    result = evalS("""(gsub "a <bc> <defghi>" "<(?<named>[^>]+)>" "$named")""")
    check result == "a bc defghi".md

  test "fit statement works":
    var result = evalS("""(fit "hello world" 10)""")
    check result == "hello worl".md

    result = evalS("""(fit "hello world" 15)""")
    check result == "hello world    ".md

    result = evalS("""(fit "hello world" 15 "x")""")
    check result == "hello worldxxxx".md

    result = evalS("""(fit "hello world" 6 " " "...")""")
    check result == "hel...".md

    result = evalS("""(fit "hello world" 6 " " "abcdefg")""")
    check result == "abcdef".md

    result = evalS("""(fit "hello world" -15)""")
    check result == "    hello world".md

    result = evalS("""(fit "hello world" -15 "x")""")
    check result == "xxxxhello world".md

    result = evalS("""(fit "hello world" -6 " " "abcdefg")""")
    check result == "bcdefg".md

  test "static evaluation works":
    var result = evalS("""(static-eval 5)""")
    check result == 5.md

    # TODO: actually test static evaluation

  test "macros expand at compile-time, not run-time":
    world.verbObj.setPropR("root", root)
    root.setPropR("macro-test-property", 100)
    var result = evalS("""
(do
 (define-syntax makro (lambda (code)
   (+ 1 (getprop $root "macro-test-property"))))

 (define func (lambda ()
   (makro)))

 (define result-1 (func))

 ;; this shouldn't affect the next line; $root.macro-test-property
 ;; should be inlined into func.

 (setprop $root "macro-test-property" 200)

 (define result-2 (func))

 (list result-1 result-2))
""")

    check result == @[101.md, 101.md].md


  test "macro infinite recursion returns error":
    var result = evalS(""" (define-syntax lol (lambda (code) `(do (echo "running code!") ,code))) (lol 4) """)
    check result.isType(dErr)
    check result.errVal == E_MAXREC

  test "looping macro works":
    var result = evalS(loopcode & """
(loop loopstate '(15 0) continue
  (let ((cur (get loopstate 0))
        (sum (get loopstate 1)))
    (if (<= cur 0)
        sum
        (call continue (list (list (- cur 1) (+ sum cur)))))))
""")

    check result == 120.md

  test "looping macro can loop infinitely":
    var result = evalS(loopcode & """
(loop loopstate '(0) continue (call continue loopstate))
""")

    check result == E_QUOTA.md


include tests/bdtest
