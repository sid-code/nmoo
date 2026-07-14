import os
import strutils
import nre
import options
import tables
import std/strformat

import types
import server
import objects
import querying
import verbs
import builtins
import persist
import rdstdin

let
  world = loadWorld("core")
  player = world.getObjects()[7]

try:
  world.check()
except InvalidWorldError:
  let exception = getCurrentException()
  echo "Invalid world: " & exception.msg & "."

player.output = proc(obj: MObject, msg: string) =
  echo msg

proc myEscape(s: string): string =
  s.replace("\"", "\\\"").replace("\n","\\\n")

proc handleCtrlC {.noConv.} =
  echo "Shutting down..."
  raise newException(Exception, "Received SIGINT")

proc mainLoop =
  while true:
    while world.tasks.len() > 0:
      world.tick()
    world.persist()

    var command = ""

    try:
      command = readLineFromStdin("> ").strip()
    except IOError:
      break

    if command.contains("<>"):
      discard os.execShellCmd("$EDITOR edit.tmp")
      command = command.replace("<>", readFile("edit.tmp").myEscape())

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
        discard os.execShellCmd("$EDITOR edit.tmp -c \"set filetype=lisp\"")
        let newCode = readFile("edit.tmp")

        let err = verb.setCode(newCode, player, compileIt = true)
        if err == E_NONE.md:
          echo fmt"Succesfully edited verb '${verbname}'"
        else:
          echo fmt"Failed to edit verb '${verbname}': ${err}"


      except:
        echo "There was a problem editing the verb."

      continue

    if command.len == 0: continue

    discard player.handleCommand(command)

when isMainModule:
  setControlCHook(handleCtrlC)
  try:
    mainLoop()
  finally:
    world.persist()
    removeFile("edit.tmp")
