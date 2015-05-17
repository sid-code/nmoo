import types, objects, querying, verbs, builtins, persist, os, strutils, rdstdin

let
  world = loadWorld("min")
  player = world.getObjects()[8]

player.output = proc(obj: MObject, msg: string) =
  echo msg

proc myEscape(s: string): string =
  s.replace("\"", "\\\"")

while true:
  var command = readLineFromStdin("> ").strip()

  if command.contains("<>"):
    discard os.execShellCmd("vim edit.tmp")
    command = command.replace("<>", readFile("edit.tmp").myEscape())

  if command.len == 0: continue

  discard player.handleCommand(command).isType(dNil)
  while world.numTasks() > 0:
    world.tick()

removeFile("edit.tmp")
