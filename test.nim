import objects, querying

var world = createWorld()
var root = blankObject()
world.add(root)
root.setPropR("name", "root")
root.setPropR("aliases", @[])
root.setPropR("rootprop", "yes")
assert(root.setPropChildCopy("rootprop", true))


var genericContainer = root.createChild()
world.add(genericContainer)
genericContainer.setPropR("name", "generic container")
genericContainer.setPropR("contents", @[])

var nowhere = genericContainer.createChild()
world.add(nowhere)

var genericThing = root.createChild()

world.add(genericThing)
genericThing.setPropR("name", "generic thing")
assert(genericThing.moveTo(nowhere))

genericContainer.changeParent(genericThing)

assert(genericContainer.moveTo(nowhere))

assert(nowhere.getContents().contents.len == 2)


proc testInheritance =

  var child = root.createChild()
  world.add(child)
  child.setPropR("name", "child")

  var evenMoreChild = child.createChild()
  world.add(evenMoreChild)
  evenMoreChild.setPropR("rootprop", "no")

  child.changeParent(evenMoreChild)

  assert(child.getPropVal("rootprop").strVal == "no")

proc testQuery =

  var o1 = genericThing.createChild()
  world.add(o1)

  var o2 = genericContainer.createChild()
  world.add(o2)

  o2.setPropR("contents", @[])
  discard o1.moveTo(o2)

  o1.setPropR("aliases", @["thingy".md])
  var (has, contents) = o2.getContents()
  assert(has)
  assert(contents.len == 1)
  assert(o2.query("thingy").len == 1)
  

testInheritance()
testQuery()

echo "All tests passed"
