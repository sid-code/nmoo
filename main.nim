import types, objects, querying, verbs, builtins, persist, os, strutils, rdstdin, re

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

  if command =~ re"vedit (.+?):(.*)":
    try:
      echo matches.repr
      let objID = parseInt(matches[0][2..^1])
      let verbname = matches[1]

      let obj = world.getObjects()[objID]
      let verb = obj.getVerb(verbname)
      let code = verb.code

      writeFile("edit.tmp", code)
      discard os.execShellCmd("vim edit.tmp")
      let newCode = readFile("edit.tmp")

      verb.setCode(newCode)
      echo "Succesfully edited verb '$1'" % verbname
      world.persist()


    except:
      echo "There was a problem editing the verb."

    continue

  if command.len == 0: continue

  discard player.handleCommand(command).isType(dNil)
  while world.numTasks() > 0:
    world.tick()

removeFile("edit.tmp")
