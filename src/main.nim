import os
import strutils
import nre
import options
import tables

import types
import server
import objects
import querying
import verbs
import builtins
import persist
import rdstdin

let
  world = loadWorld("min")
  player = world.getObjects()[7]

try:
  world.check()
except InvalidWorldError:
  let exception = getCurrentException()
  echo "Invalid world: " & exception.msg & "."

player.output = proc(obj: MObject, msg: string) =
  echo msg

proc myEscape(s: string): string =
  s.replace("\"", "\\\"")

proc stripNewLines(s: string): string =
  s.replace("\n", "")

while true:
  while world.numTasks() > 0:
    world.tick()
  world.persist()

  var command = ""

  try:
    command = readLineFromStdin("> ").strip()
  except IOError:
    break

  if command.contains("<>"):
    discard os.execShellCmd("$EDITOR edit.tmp")
    command = command.replace("<>", readFile("edit.tmp").myEscape().stripNewLines())

  let match = command.match(re"vedit (.+?):(.*)")

  if match.isSome:
    try:
      let matches = match.get.captures
      let verbname = matches[1]

      let objs = player.query(matches[0].strip())
      let obj = objs[0]

      let verb = obj.getVerb(verbname)
      if verb == nil:
        raise newException(Exception, "Verb doesn't exist")

      let code = verb.code

      writeFile("edit.tmp", code)
      discard os.execShellCmd("$EDITOR edit.tmp -c \"set syntax=scheme\"")
      let newCode = readFile("edit.tmp")

      verb.setCode(newCode)
      echo "Succesfully edited verb '$1'" % verbname


    except:
      echo "There was a problem editing the verb."

    continue

  if command.len == 0: continue

  discard player.handleCommand(command)

removeFile("edit.tmp")
