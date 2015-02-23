import
  unittest,
  types, objects, scripting,
  verbs

import querying

suite "object tests":
  setup:
    var world = createWorld()
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
      prepSpec = pNone,
      doSpec = oNone,
      ioSpec = oNone,
    )

    root.verbs.add(verb)

    verb.setCode("(do argstr)")
    check ($root.handleCommand("action hey") == "@[\"hey\"]")

suite "scripting":
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
      var world = createWorld()
      var root = blankObject()
      world.add(root)
      root.setPropR("name", "root")

      proc evalS(code: string): MData =
        var parser = newParser(code)
        let
          parsed = parser.parseList()
        
        return eval(parsed, world)

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

      result = evalS("""
      (getprop #1 "nonexistant")
      """)

      check result.isType(dNil)
