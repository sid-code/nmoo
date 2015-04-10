import types, objects, querying, verbs, builtins, persist, os, strutils

let
  world = loadWorld("min")
  player = world.getObjects()[8]

player.output = proc(obj: MObject, msg: string) =
  echo msg

let command = commandLineParams().join(" ")
discard player.handleCommand(command)
while world.numTasks() > 0:
  world.tick()

# while true:
#   let command = readLineFromStdin("> ").strip()
#
#   if command.len == 0: continue
#   discard player.handleCommand(command).isType(dNil)
