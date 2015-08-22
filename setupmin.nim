import types, objects, querying, verbs, persist, builtins
import rdstdin, strutils, os, tables

var world = createWorld("min")
var root = blankObject()
root.level = 0
world.add(root)
root.owner = root
root.setPropR("name", "root")
root.setPropR("aliases", @[])
root.setPropR("rootprop", "yes")


var genericContainer = root.createChild()
world.add(genericContainer)
genericContainer.setPropR("name", "generic container")
genericContainer.setPropR("contents", @[])

var nowhere = genericContainer.createChild()
world.add(nowhere)

var genericThing = root.createChild()

world.add(genericThing)
genericThing.setPropR("name", "generic thing")

genericContainer.changeParent(genericThing)

var genericRoom = genericContainer.createChild()
world.add(genericRoom)
genericRoom.setPropR("name", "generic room")
genericRoom.setPropR("nexit", genericRoom)
genericRoom.setPropR("eexit", genericRoom)
genericRoom.setPropR("sexit", genericRoom)
genericRoom.setPropR("wexit", genericRoom)
genericRoom.setPropR("uexit", genericRoom)
genericRoom.setPropR("dexit", genericRoom)

var room = genericRoom.createChild()
world.add(room)
room.setPropR("name", "a room")

var genericPlayer = genericContainer.createChild()
world.add(genericPlayer)
genericPlayer.setPropR("name", "generic player")

genericPlayer.isPlayer = true

var player = genericPlayer.createChild()
world.add(player)
player.setPropR("name", "the player")

discard player.moveTo(room)

var eval = newVerb(
  names =  "eval",
  owner = root,

  pubRead = true,
  pubWrite = true,
  pubExec = true,

  doSpec = oStr,
  prepSpec = pNone,
  ioSpec = oNone
)
eval.setCode("""(eval (cat "(try (echo \"=> \" " dobjstr ") (echo \"eval error: \" error))"))""")
world.verbObj.verbs.add(eval)
player.level = 0

world.globalSymtable["$verbobj"] = world.verbObj.md
world.globalSymtable["$root"] = root.md
world.globalSymtable["$nowhere"] = nowhere.md
world.globalSymtable["$container"] = genericContainer.md
world.globalSymtable["$player"] = genericPlayer.md
world.globalSymtable["$room"] = genericRoom.md

createDir(getObjectDir(name))
world.persist()
