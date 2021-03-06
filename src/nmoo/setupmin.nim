
import rdstdin
import strutils
import os
import tables

import types
import objects
import verbs
import persist

let args = commandLineParams()
let name = if args.len == 1: args[0] else: "min"

if existsDir("worlds" / name):
  stderr.write("error: world " & name & " already exists.\n")
  stderr.write("Delete " & "worlds" / name & " and re-run this program.\n")

quit(0)

var world = createWorld(name)
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
  names = "eval",
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

createDir(getObjectDir(name))
world.persist()
