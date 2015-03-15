import types, objects, querying, verbs, builtins, rdstdin, strutils, persist

let
  world = loadWorld("min")
  player = world.getObjects()[8]

while true:
  let command = readLineFromStdin("> ").strip()

  if command.len == 0: continue
  discard player.handleCommand(command).isType(dNil)
