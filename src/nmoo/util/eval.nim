import std/options
import strutils
import std/cmdline
import std/logging

import ../types
import ../server
import ../scripting
import ../verbs
import ../compile
import ../tasks
import ../objects
import ../logfmt

proc makeWorld(): World =

  var world = createWorld("test", persistent = false)
  var root = blankObject()
  initializeBuiltinProps(root)
  root.changeParent(root)
  root.level = 0
  world.add(root)

  root.output = proc (o: MObject, msg: string) =
    echo "Sent to $#: $#".format(o, msg)

  var worthy = root.createChild()
  worthy.level = 0
  world.add(worthy)

  var unworthy = root.createChild()
  world.add(unworthy)
  unworthy.level = 3

  var verb = newVerb(
    names = "verb name",
    owner = root.id,
    doSpec = oNone,
    prepSpec = pWith,
    ioSpec = oNone
  )
  root.verbs.add(verb)

  root.setPropR("name", "root")

  return world

proc evalS(world: World, code: string, who: MObject): MData =
  var symtable = newSymbolTable()
  let name = "test task"
  let compiled = compileCode(code, who)
  if compiled.error != E_NONE.md:
    return compiled.error

  let t = world.addTask(name, who, who, who, who, symtable, compiled, ttFunction, none(TaskID))

  let tr = world.run(t)
  case tr.typ:
    of trFinish:
      return tr.res
    of trError:
      return tr.err
    of trTooLong:
      return E_QUOTA.md("task took too long!")
    else:
      return nilD

var clog: ConsoleLogger

when isMainModule:
  clog = newConsoleLogger(fmtStr=MLogFmtStr)
  addHandler(clog)
  let world = makeWorld()
  let obj = world.byID(0.ObjID).get()
  let f = open(commandLineParams()[0])
  echo world.evalS(readAll(f), obj)
