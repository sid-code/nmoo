# This file has methods for manipulating objects and their properties

import types, sequtils, strutils, tables, logging
# NOTE: verbs is imported later on!

proc getProp*(obj: MObject, name: string, all = true): MProperty
proc getStrProp*(obj: MObject, name: string, all = true): string
proc getAliases*(obj: MObject): seq[string]
proc getLocation*(obj: MObject): MObject
proc getContents*(obj: MObject): tuple[hasContents: bool, contents: seq[MObject]]
proc getPropVal*(obj: MObject, name: string, all = true): MData
proc setProp*(obj: MObject, name: string, newVal: MData): MProperty
proc addTask*(world: World, name: string, owner, caller: MObject,
              symtable: SymbolTable, code: CpOutput, taskType = ttFunction,
              callback = -1): Task
proc run*(task: Task, limit: int = 20000): TaskResult

## Permissions handling

proc isWizard*(obj: MObject): bool = obj.level == 0

proc owns*(who, obj: MObject): bool {.inline.} =
  who.isWizard() or obj.owner == who
proc owns*(who: MObject, prop: MProperty): bool {.inline.} =
  who.isWizard() or prop.owner == who
proc owns*(who: MObject, verb: MVerb): bool {.inline.} =
  who.isWizard() or verb.owner == who

proc canRead*(reader, obj: MObject): bool {.inline.} =
  reader.owns(obj) or obj.pubRead

proc canWrite*(writer, obj: MObject): bool {.inline.} =
  writer.owns(obj) or obj.pubWrite

proc canRead*(reader: MObject, prop: MProperty): bool {.inline.} =
  reader.owns(prop) or prop.pubRead

proc canWrite*(writer: MObject, prop: MProperty): bool {.inline.} =
  writer.owns(prop) or prop.pubWrite

proc canRead*(reader: MObject, verb: MVerb): bool {.inline.} =
  reader.owns(verb) or verb.pubRead

proc canWrite*(writer: MObject, verb: MVerb): bool {.inline.} =
  writer.owns(verb) or verb.pubWrite

proc canExecute*(executor: MObject, verb: MVerb): bool {.inline.} =
  executor.owns(verb) or verb.pubExec

proc toObjStr*(obj: MObject): string =
  let
    name = obj.getPropVal("name")
    objdstr = $obj.md
  if name.isType(dStr) and name.strVal.len > 0:
    return "$2 ($1)" % [objdstr, name.strVal]
  else:
    return "$1" % objdstr

proc `$`*(obj: MObject): string = obj.toObjStr

proc toObjStr*(objd: MData, world: World): string =
  ## Converts MData holding objects into strings
  let
    obj = world.dataToObj(objd)
  if isNil(obj):
    return "Invalid object ($1)" % $objd
  else:
    return obj.toObjStr()

import verbs

proc getPropAndObj*(obj: MObject, name: string, all = true): tuple[o: MObject, p: MProperty] =
  for p in obj.props:
    if p.name == name:
      return (obj, p)

  if all:
    let parent = obj.parent
    if not isNil(parent) and parent != obj:
      return parent.getPropAndObj(name, all)

  return (nil, nil)

proc getProp*(obj: MObject, name: string, all = true): MProperty =
  obj.getPropAndObj(name, all).p

proc setPropChildCopy*(obj: MObject, name: string, newVal: bool): bool =
  var prop = obj.getProp(name)
  if not isNil(prop):
    prop.copyVal = newVal
    return true
  else:
    return false

proc getPropVal*(obj: MObject, name: string, all = true): MData =
  var res = obj.getProp(name, all)
  if isNil(res):
    nilD
  else:
    res.val

proc setProp*(obj: MObject, name: string, newVal: MData): MProperty =
  var p = obj.getProp(name, all = false)
  if isNil(p):
    p = newProperty(
      name = name,
      val = newVal,
      owner = obj,
      inherited = false,
      copyVal = false,

      pubRead = true,
      pubWrite = false,
      ownerIsParent = true
    )

    obj.props.add(p)
  else:
    p.val = newVal

  return p

template setPropR*(obj: MObject, name: string, newVal: expr) =
  discard obj.setProp(name, newVal.md)

proc setPropRec*(obj: MObject, name: string, newVal: MData,
                 recursed: bool = false):
                 seq[tuple[o: MObject, p: MProperty]] =
  newSeq(result, 0)

  if recursed: # If we're recursing, then it may not be necessary
    if not isNil(obj.getProp(name)):
      return

  var prop = obj.setProp(name, newVal)

  result.add((obj, prop))

  for child in obj.children:
    result.add(child.setPropRec(name, newVal, true))

proc delProp*(obj: MObject, prop: MProperty): MProperty =
  for idx, pr in obj.props:
    if pr.name == prop.name:
      system.delete(obj.props, idx)
      return prop

proc delPropRec*(obj: MObject, prop: MProperty):
    seq[tuple[o: MObject, p: MProperty]] =
  newSeq(result, 0)
  result.add((obj, obj.delProp(prop)))

  for child in obj.children:
    if child != obj:
      result.add(child.delPropRec(prop))

proc getOwnProps*(obj: MObject): seq[string] =
  newSeq(result, 0)
  for prop in obj.props:
    let name = prop.name
    result.add(name)

proc getLocation*(obj: MObject): MObject =
  let world = obj.getWorld()
  if isNil(world): return nil

  let loc = obj.getPropVal("location")

  if loc.isType(dObj):
    return world.byID(loc.objVal)
  else:
    return nil

proc getRawContents(obj: MObject): tuple[hasContents: bool, contents: seq[MData]] =

  let contents = obj.getPropVal("contents")

  if contents.isType(dList):
    return (true, contents.listVal)
  else:
    return (false, @[])


proc getContents*(obj: MObject): tuple[hasContents: bool, contents: seq[MObject]] =
  let world = obj.getWorld()
  if isNil(world): return (false, @[])

  var res: seq[MObject] = @[]

  var (has, contents) = obj.getRawContents();

  if has:
    for o in contents:
      if o.isType(dObj):
        res.add(world.byID(o.objVal))

    return (true, res)
  else:
    return (false, @[])



proc addToContents*(obj: MObject, newMember: MObject): bool =
  var (has, contents) = obj.getRawContents();
  if has:
    contents.add(newMember.md)
    obj.setPropR("contents", contents)
    return true
  else:
    return false

proc removeFromContents*(obj: MObject, member: MObject): bool =
  var (has, contents) = obj.getRawContents();

  if has:
    for idx, o in contents:
      if o.objVal == member.getID():
        system.delete(contents, idx)

    obj.setPropR("contents", contents)
    return true
  else:
    return false

proc moveTo*(obj: MObject, newLoc: MObject): bool =
  var loc = obj.getLocation()
  if not isNil(loc):
    discard loc.removeFromContents(obj)

  if newLoc.addToContents(obj):
    obj.setPropR("location", newLoc)
    return true
  else:
    return false

proc getAliases*(obj: MObject): seq[string] =
  let aliases = obj.getPropVal("aliases")
  newSeq(result, 0)

  if aliases.isType(dList):
    for o in aliases.listVal:
      if o.isType(dStr):
        result.add(o.strVal)

proc getStrProp*(obj: MObject, name: string, all = true): string =
  let datum = obj.getPropVal(name, all)

  if datum.isType(dStr):
    return datum.strVal
  else:
    return ""


proc add*(world: World, obj: MObject) =
  var objs = world.getObjects()
  var newid = ObjID(objs[].len)

  obj.setID(newid)
  obj.setWorld(world)
  objs[].add(obj)

proc createWorld*(name: string): World =
  result = newWorld()
  result.name = name
  var verbObj = blankObject()
  verbObj.parent = verbObj
  result.add(verbObj)
  result.verbObj = verbObj

proc size*(world: World): int =
  world.getObjects()[].len

proc delete*(world: World, obj: MObject) =
  var objs = world.getObjects()
  var idx = obj.getID().int

  objs[idx] = nil

proc setGlobal*(world: World, key: string, value: MData) =
  discard world.verbObj.setProp(key, value)

proc getGlobal*(world: World, key: string): MData =
  let prop = world.verbObj.getProp(key)
  if isNil(prop):
    nilD
  else:
    prop.val

proc changeParent*(obj: MObject, newParent: MObject) =
  if not newParent.fertile:
    return

  if not isNil(obj.parent):
    # delete currently inherited properties
    obj.props.keepItIf(not it.inherited)

    # remove this from old parent's children
    obj.parent.children.keepItIf(it != obj)

  obj.level = newParent.level
  obj.parent = newParent
  newParent.children.add(obj)

proc createChild*(parent: MObject): MObject =
  if not parent.fertile:
    return nil

  var newObj = blankObject()

  newObj.isPlayer = parent.isPlayer
  newObj.pubRead = parent.pubRead
  newObj.pubWrite = parent.pubWrite
  newObj.fertile = parent.fertile
  newObj.owner = parent.owner

  newObj.output = parent.output

  newObj.changeParent(parent)
  return newObj

import tasks

# This proc is called by the server
proc tick*(world: World) =
  for idx, task in world.tasks:

    if task.status == tsDone:
      if defined(showTicks):
        echo "Task " & task.name & " finished, used " & $task.tickCount & " ticks."
      system.delete(world.tasks, idx)

    if not task.isRunning(): continue
    try:
      task.step()
    except:
      let exception = getCurrentException()
      warn exception.repr
      task.doError(E_INTERNAL.md(exception.msg))


proc addTask*(world: World, name: string, owner, caller: MObject,
              symtable: SymbolTable, code: CpOutput, taskType = ttFunction,
              callback = -1): Task =
  let tickQuotad = world.getGlobal("tick-quota")
  let tickQuota = if tickQuotad.isType(dInt): tickQuotad.intVal else: 20000

  let newTask = task(
    id = world.taskIDCounter,
    name = name,
    compiled = code,
    world = world,
    owner = owner,
    caller = caller,
    globals = symtable,
    tickQuota = tickQuota,
    taskType = taskType,
    callback = callback)
  world.taskIDCounter += 1

  world.tasks.add(newTask)
  return newTask

# I would really like to put this in tasks.nim but verbs needs it and
# I can't import tasks from verbs.
proc run*(task: Task, limit: int = 20000): TaskResult =
  var limit = limit
  while limit > 0:
    case task.status:
      of tsSuspended, tsAwaitingInput, tsReceivedInput:
        return TaskResult(typ: trSuspend)
      of tsAwaitingResult:
        # This is a sticky case. Now we need to search for a task whose callback
        # is this task, so that we can run that task to completion.
        var found = false
        for idx, otask in task.world.tasks:
          if otask.callback == task.id:
            let res = otask.run(limit)
            if res.typ in {trError, trTooLong, trSuspend}: return res

            system.delete(task.world.tasks, idx)

            found = true
            break

        if not found:
          return TaskResult(typ: trSuspend)
      of tsDone:
        let res = task.top()
        if res.isType(dErr):
          return TaskResult(typ: trError, err: res)
        else:
          return TaskResult(typ: trFinish, res: res)
      of tsRunning:
        task.step()
        limit -= 1

  return TaskResult(typ: trTooLong)

proc numTasks*(world: World): int = world.tasks.len

import persist

# Check if a symbol in the global symtable has a certain desired type
proc checkForGSymType(world: World, sym: string, dtype: MDataType) =
  let data = world.getGlobal(sym)

  if not data.isType(dtype):
    raise newException(InvalidWorldError, "$# needs to be of type $#, not $#" % [sym, $dtype, $data.dtype])

proc checkRoot(world: World) =
  world.checkForGSymType("root", dObj)

proc checkNowhere(world: World) =
  world.checkForGSymType("nowhere", dObj)
  let nowhered = world.getGlobal("nowhere")

  let nowhere = world.dataToObj(nowhered)

  if isNil(nowhere.getProp("contents")):
    raise newException(InvalidWorldError, "the $nowhere object needs to have contents")

proc checkPlayer(world: World) =
  world.checkForGSymType("player", dObj)
  let playerd = world.getGlobal("player")

  let player = world.dataToObj(playerd)

  if isNil(player.getProp("contents")):
    raise newException(InvalidWorldError, "the $player object needs to have contents")

proc checkObjectHierarchyHelper(world: World, root: MObject) =
  root.children.keepItIf(not isNil(it))
  for child in root.children:
    if child != root:
      world.checkObjectHierarchyHelper(child)

  world.persist(root)

proc checkObjectHierarchy(world: World) =
  let root = world.dataToObj(world.getGlobal("root"))
  world.checkObjectHierarchyHelper(root)

# This checks if the world is fit to be used
proc check*(world: World) =
  world.checkRoot()
  world.checkNowhere()
  world.checkPlayer()
  world.checkObjectHierarchy()
