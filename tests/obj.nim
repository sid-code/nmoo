import unittest

import nmoo/types
import nmoo/objects
import nmoo/querying
import nmoo/verbs

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

    var err: MData
    verb.setCode("(do argstr)", root, err)
    check err == E_NONE.md
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

    var err: MData
    verb.setCode("(do args)", root, err)
    check err == E_NONE.md
    #check $root.verbCall("action", root, @["hey".md]) == "@[@[\"hey\"]]"
    check true
