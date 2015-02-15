import objects, querying

var world = createWorld()
var root = blankObject()
world.add(root)
root.setPropR("name", "root")
root.setPropR("aliases", @[])
root.setPropR("location", root)
root.setPropR("rootprop", "yes")

var child = root.createChild()
child.setPropR("name", "child")

echo child.getPropVal("rootprop").repr

var evenMoreChild = child.createChild()
evenMoreChild.setPropR("rootprop", "no")

child.changeParent(evenMoreChild)

echo child.getPropVal("rootprop").repr
