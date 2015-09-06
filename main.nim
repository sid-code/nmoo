import types, objects, querying, verbs, builtins, persist, os, strutils, re, tables

let
  world = loadWorld("min")
  player = world.getObjects()[8]

world.check()

player.output = proc(obj: MObject, msg: string) =
  echo msg

proc myEscape(s: string): string =
  s.replace("\"", "\\\"")

while true:
  stdout.write("> ")
  var command = stdin.readLine().strip()

  if command.contains("<>"):
    discard os.execShellCmd("vim edit.tmp")
    command = command.replace("<>", readFile("edit.tmp").myEscape())

  if command =~ re"vedit (.+?):(.*)":
    try:
      let verbname = matches[1]

      let objs = player.query(matches[0].strip(), global = true)
      let obj = objs[0]

      let verb = obj.getVerb(verbname)
      if verb == nil:
        raise newException(Exception, "Verb doesn't exist")

      let code = verb.code

      writeFile("edit.tmp", code)
      discard os.execShellCmd("vim edit.tmp -c \"set syntax=scheme\"")
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
