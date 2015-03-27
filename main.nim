import types, objects, querying, verbs, builtins, rdstdin, strutils, persist

let
  world = loadWorld("min")
  player = world.getObjects()[8]

player.output = proc(obj: MObject, msg: string) =
  echo msg

while true:
  let command = readLineFromStdin("> ").strip()

  if command.len == 0: continue
  discard player.handleCommand(command).isType(dNil)
