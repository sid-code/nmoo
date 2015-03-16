import
  unittest, tables,
  types, objects,
  verbs,
  scripting,
  builtins

import querying

test "== operator works for MData":
  var
    x = 2.md
    y = 2.md

  check x == y

  x = @[1.md, "two".md, "three".mds].md
  y = @[1.md, "two".md, "three".mds].md

  check x == y

  x = @[2.md, "two".md, "three".mds].md

  check x != y

suite "object tests":
  setup:
    var world = createWorld("test")
    var root = blankObject()
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

    check nowhere.getContents().contents.len == 2

  test "inheritance works":
    var child = root.createChild()
    world.add(child)
    child.setPropR("name", "child")

    var evenMoreChild = child.createChild()
    world.add(evenMoreChild)
    evenMoreChild.setPropR("rootprop", "no")

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
    let (has, contents) = o2.getContents()

    check has
    check contents.len == 1
    check o2.query("thin").len == 1

  test "verbs fire correctly":
    var verb = newVerb(
      names = "action",
      owner = root,
      doSpec = oThis,
      prepSpec = pOn,
      ioSpec = oThis,
    )

    root.verbs.add(verb)

    verb.setCode("(do argstr)")
    check ($root.handleCommand("action root on root") == "@[\"root on root\"]")

  test "verbs call correctly":
    var verb = newVerb(
      names = "action",
      owner = root,
      prepSpec = pNone,
      doSpec = oNone,
      ioSpec = oNone,
    )

    root.verbs.add(verb)

    verb.setCode("(do args)")
    check ($root.verbCall("action", root, @["hey".md]) == "@[@[\"hey\"]]")


suite "lexer":
  setup:
    let testStr = "(builtin \"stri\\\"ng\")"

  test "lexer works":
    let lexed = lex(testStr)
    check lexed.len == 4

suite "parser":
  setup:
    let testStr = "(echo \"hello world\" (sub-list \"who knew?\" 3.14))"
    var parser = newParser(testStr)
  test "parser works":
    let
      result = parser.parseList()
      str = $result

    check str == "@['echo, \"hello world\", @['sub-list, \"who knew?\", 3.14]]"

suite "evaluator":
  setup:
    var world = createWorld("test")
    var root = blankObject()
    world.add(root)

    var worthy = blankObject()
    world.add(worthy)

    var unworthy = blankObject()
    world.add(unworthy)
    unworthy.level = 3

    var verb = newVerb(
      names = "verb name",
      owner = root,
      doSpec = oNone,
      prepSpec = pWith,
      ioSpec = oNone
    )
    root.verbs.add(verb)

    root.setPropR("name", "root")

    var symtable = initSymbolTable()
    proc evalS(code: string, who: MObject = root): MData =
      var parser = newParser(code)
      let
        parsed = parser.parseList()

      return eval(parsed, world, who, who, symtable)

  test "let statement binds symbols locally":
    let result = evalS("""
    (do (let ((a "b") (b a)) b) (echo a))
    """)

    check result.isType(dErr)
    check result.errVal == E_UNBOUND

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

  test "setprop checks permissions":
    let result = evalS("""
    (setprop #1 "newprop" "oops")
    """, unworthy)

    check result.isType(dErr)
    check result.errVal == E_PERM

  test "setprop sets owner of new properties correctly":
    # note: the level defaults to zero so we don't have to change it
    var result = evalS("""
    (setprop #1 "newprop" "newval")
    """, worthy)

    check result.isType(dStr)
    let prop = root.getProp("newprop")
    check prop != nil
    check prop.owner == worthy

  test "setpropinfo works":
    var result = evalS("""(setpropinfo #1 "name" (#1 "rw" "name1"))""")
    check result.isType(dObj)
    check result.objVal.int == 1
    let prop = root.getProp("name1")
    check prop != nil
    check prop.name == "name1"
    check prop.pubWrite
    check prop.pubRead
    check (not prop.ownerIsParent)

  test "setpropinfo checks permissions":
    var result = evalS("""(setpropinfo #1 "name" (#1 "rw" "name1"))""", unworthy)
    check result.isType(dErr)
    check result.errVal == E_PERM

  test "props statement works":
    var result = evalS("(props #1)", worthy)
    check ($result == "@[\"name\"]")

  test "props checks permissions":
    root.pubRead = false
    var result = evalS("(props #1)", unworthy)
    check result.isType(dErr)

  test "verbs statement works":
    var result = evalS("(verbs #1)", worthy)
    check ($result == "@[\"verb name\"]")

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
    check ($result == "@[#1, \"rwx\", \"new ve*rb name\"]")

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
    check ($result == "@[#1, \"rx\", \"cool varb\"]")
    result = evalS("(getverbargs #1 \"cool\")")
    check ($result == "@[\"none\", \"none\", \"none\"]")

  test "delverb statement works":
    var result = evalS("(addverb #1 \"cool varb\")")
    let beforelen = root.verbs.len
    result = evalS("(delverb #1 \"cool\")")
    let afterlen = root.verbs.len

    check beforelen == afterlen + 1

  test "try statement works":
    var result = evalS("(try (echo unbound) 4 (echo \"incorrect finally fire\"))")
    check result == 4.md # for good measure

    result = evalS("(try \"no error here!\" (echo \"incorrect except fire\") 4)")

    check result == 4.md

  test "move statement works":
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

    # move actually moves objects
    var result = evalS("(move gencont nowhere)")
    check genericContainer.getLocation() == nowhere
    let (has, contents) = nowhere.getContents()
    check has
    check genericContainer in contents

    # move removes objects from previous location
    result = evalS("(move genthing gencont)")
    let (has2, contents2) = nowhere.getContents()
    check has2
    check contents2.len == 1

    # for good measure
    check genericThing.getLocation() == genericContainer

    # recursive move
    result = evalS("(move gencont gencont)")
    check result.isType(dErr)
    check result.errVal == E_RECMOVE

  test "lambda statement works":
    var result = evalS("(lambda (x y) (do x y) 4 4)")
    check result.isType(dList)
    check result.listVal.len == 2

  test "call statement works on lambdas":
    var result = evalS("(call (lambda (x y) (do x y)) 4 4)")
    check result.isType(dList)
    check result.listVal.len == 2

  test "call statement works on builtins":
    var result = evalS("(call do 4 4)")
    check result.isType(dList)
    check result.listVal.len == 2

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

  test "reduce statement works":
    var result = evalS("(reduce + 0 (1 2 3 4))")
    check result == 10.md

    result = evalS("(reduce + (1 2 3 4))")
    check result == 10.md

    result = evalS("(reduce (lambda (x y) (+ x (* 2 y))) 0 (1 3 5 7))")
    check result == 32.md

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

  test "= statement works":
    var result = evalS("(= 3 3)")
    check result == 1.md

    result = evalS("(= (3 3 \"cat\") (3 3 \"cat\"))")
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

  test "cons statement works":
    var result = evalS("(cons 1 (1 2))")
    check result.isType(dList)
    check result.listVal.len == 3
