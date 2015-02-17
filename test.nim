import objects, querying

var world = createWorld()
var root = blankObject()
world.add(root)
root.setPropR("name", "root")
root.setPropR("aliases", @[])
root.setPropR("location", root)
root.setPropR("rootprop", "yes")

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

  var o1 = root.createChild()
  world.add(o1)

  var o2 = root.createChild()
  world.add(o2)

  o1.moveTo(o2)

  o1.setPropR("aliases", @["thingy".md])
  assert(o2.getContents().len == 1)
  assert(o2.query("thingy").len == 1)
  

testInheritance()
testQuery()

echo "All tests passed"
