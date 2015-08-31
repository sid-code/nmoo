# This file has methods for manipulating objects and their properties

import types, sequtils, strutils, tables
# NOTE: verbs is imported later on!

proc getStrProp*(obj: MObject, name: string): string
proc getAliases*(obj: MObject): seq[string]
proc getLocation*(obj: MObject): MObject
proc getContents*(obj: MObject): tuple[hasContents: bool, contents: seq[MObject]]
proc getPropVal*(obj: MObject, name: string): MData
proc setProp*(obj: MObject, name: string, newVal: MData): MProperty
proc addTask*(world: World, name: string, owner, caller: MObject,
              symtable: SymbolTable, code: CpOutput, callback = -1)

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
    return "No name ($1)" % objdstr

proc toObjStr*(objd: MData, world: World): string =
  ## Converts MData holding objects into strings
  let
    obj = world.dataToObj(objd)
  if obj == nil:
    return "Invalid object ($1)" % $objd
  else:
    return obj.toObjStr()

import verbs


proc getProp*(obj: MObject, name: string): MProperty =
  for p in obj.props:
    if p.name == name:
      return p

  return nil

proc setPropChildCopy*(obj: MObject, name: string, newVal: bool): bool =
  var prop = obj.getProp(name)
  if prop != nil:
    prop.copyVal = newVal
    return true
  else:
    return false

proc getPropVal*(obj: MObject, name: string): MData =
  var res = obj.getProp(name)
  if res == nil:
    nilD
  else:
    res.val

proc setProp*(obj: MObject, name: string, newVal: MData): MProperty =
  var p = obj.getProp(name)
  if p == nil:
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
  result = @[]
  var prop = obj.setProp(name, newVal)

  if recursed: # If we're recursing, then it's being inherited
    prop.inherited = true

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
  result = @[]
  result.add((obj, obj.delProp(prop)))

  for child in obj.children:
    result.add(child.delPropRec(prop))


proc getLocation*(obj: MObject): MObject =
  let world = obj.getWorld()
  if world == nil: return nil

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
  if world == nil: return (false, @[])

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
  if loc == newLoc:
    return true
  if loc != nil:
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

proc getStrProp*(obj: MObject, name: string): string =
  let datum = obj.getPropVal(name)

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
  result.add(verbObj)
  result.verbObj = verbObj

proc size*(world: World): int =
  world.getObjects()[].len

proc delete*(world: World, obj: MObject) =
  var objs = world.getObjects()
  var idx = obj.getID().int

  objs[idx] = nil

proc setGlobal*(world: World, key: string, value: MData) =
  world.globalSymtable[key] = value

proc getGlobal*(world: World, key: string): MData =
  if world.globalSymtable.hasKey(key):
    world.globalSymtable[key]
  else:
    nilD

proc changeParent*(obj: MObject, newParent: MObject) =
  if not newParent.fertile:
    return

  if obj.parent != nil:
    # delete currently inherited properties
    obj.props.keepItIf(not it.inherited)

    # remove this from old parent's children
    obj.parent.children.keepItIf(it != obj)


  for p in newParent.props:
    var pc = p.copy
    pc.inherited = true

    # only copy the value of the property if specified by the property

    if not pc.copyVal:
      pc.val = blank(pc.val.dtype)


    obj.props.add(pc)

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

proc tick*(world: World) =
  for idx, task in world.tasks:
    try:
      task.step()
      if task.done:
        system.delete(world.tasks, idx)
    except:
      let exception = getCurrentException()
      task.done = true
      system.delete(world.tasks, idx)
      echo exception.repr
      task.caller.send("There was an internal error while executing a task you called.")
      task.caller.send("Here is what it says: " & exception.msg)
      task.caller.send("This error is due to a server bug.")
      # raise exception

proc addTask*(world: World, name: string, owner, caller: MObject,
              symtable: SymbolTable, code: CpOutput, callback = -1) =

  let newTask = task(
    id = world.taskIDCounter,
    name = name,
    compiled = code,
    world = world,
    owner = owner,
    caller = caller,
    globals = symtable,
    callback = callback)
  world.taskIDCounter += 1

  world.tasks.add(newTask)

proc numTasks*(world: World): int = world.tasks.len

# Check if there is a nowhere object
proc checkNowhere(world: World) =
  if world.globalSymtable.hasKey("$nowhere"):
    let nowhered = world.globalSymtable["$nowhere"]
    if nowhered.isType(dObj):
      let nowhere = world.dataToObj(nowhered)
      if nowhere.getProp("contents") == nil:
        raise newException(InvalidWorldError, "the $nowhere object needs to have contents")
      else:
        return
    else:
      raise newException(InvalidWorldError, "$nowhere needs to be an object")
  else:
    raise newException(InvalidWorldError, "there is no $nowhere object in the global symtable")

# This checks if the world is fit to be used
proc check*(world: World) =
  world.checkNowhere()
