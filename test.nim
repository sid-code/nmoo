import 
  unittest,
  objects, querying, scripting

suite "object tests":
  setup:
    var world = createWorld()
    var root = blankObject()
    world.add(root)
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
    var (has, contents) = o2.getContents()

    check has
    check contents.len == 1
    check o2.query("thin").len == 1

suite "scripting":
  suite "lexer":
    setup:
      var testStr = "(builtin \"stri\\\"ng\")"

    test "lexer works":
      var lexed = lex(testStr)
      check lexed.len == 4
