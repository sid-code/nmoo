# This file has methods for manipulating objects and their properties

import types
import sequtils
import strutils
import tables
import logging
import options
import std/sugar
# NOTE: verbs is imported later on!

proc blankObject*: MObject
proc getProp*(obj: MObject, name: string, all = true): MProperty
proc getStrProp*(obj: MObject, name: string, all = true): string
proc getAliases*(obj: MObject): seq[string]
proc getLocation*(obj: MObject): MObject
proc getContents*(obj: MObject): seq[MObject]
proc getPropVal*(obj: MObject, name: string, all = true): MData
proc getPropAndObj*(obj: MObject, name: string, all = true): Option[tuple[o: MObject, p: MProperty]]
proc setProp*(obj: MObject, name: string, newVal: MData): tuple[p: MProperty, e: MData]
proc delPropRec*(obj: MObject, prop: MProperty): seq[tuple[o: MObject, p: MProperty]]
proc propIsInherited*(obj: MObject, name: string): bool
proc propIsInherited*(obj: MObject, prop: MProperty): bool
proc getOwnProps*(obj: MObject): seq[string]
proc moveTo*(obj: MObject, newLoc: MObject): bool
proc createChild*(parent: MObject): MObject
proc createWorld*(name: string, persistent = true): World
proc add*(world: World, obj: MObject)
proc delete*(world: World, obj: MObject)
proc getGlobal*(world: World, key: string): MData
proc changeParent*(obj: MObject, newParent: MObject)
proc addToContents*(obj: MObject, newMember: MObject): bool
proc removeFromContents*(obj: MObject, member: MObject): bool

template setPropR*(obj: MObject, name: string, newVal: untyped) =
  discard obj.setProp(name, newVal.md)

# Builtin property data
var BuiltinPropertyData = initTable[string, MData]()
BuiltinPropertyData["name"] = "no name".md
BuiltinPropertyData["owner"] = 0.ObjID.md
BuiltinPropertyData["location"] = 0.ObjID.md
BuiltinPropertyData["contents"] = @[].md
BuiltinPropertyData["level"] = 3.md
BuiltinPropertyData["pubread"] = 1.md
BuiltinPropertyData["pubwrite"] = 0.md
BuiltinPropertyData["fertile"] = 1.md

# Object initialization
# NOTE: Only pass blank objects to this proc. If not, it will overwrite the
# values of the built in properties.
proc initializeBuiltinProps*(obj: MObject) =
  for propName, value in BuiltinPropertyData.pairs:
    discard obj.setProp(propName, value)

proc blankObject*: MObject =
  result = MObject(
    id: 0.id,
    world: nil,
    isPlayer: false,
    props: @[],
    verbs: @[],
    parent: nil,
    children: @[],

    output: proc (obj: MObject, m: string) =
      debug "sent to #$1: $2" % [$obj.getID(), m]
  )

  initializeBuiltinProps(result)


# The following are convenience procs to ease the transition from
# no builtin properties to builtin properties.
proc owner*(obj: MObject): MData =
  obj.getPropVal("owner")
proc `owner=`(obj: MObject, newOwnerd: MData) =
  discard obj.setProp("owner", newOwnerd)

proc `owner=`*(obj: MObject, newOwner: MObject) =
  obj.owner = newOwner.md

  # Need to set the owner of all properties with the 'c' flag.
  # There will be a hook in the setprop builtin that calls this
  # if the 'owner' property is set.
  for prop in obj.props:
    if prop.ownerIsParent:
      prop.owner = newOwner

proc level*(obj: MObject): int =
  obj.getPropVal("level").intVal
proc `level=`*(obj: MObject, newLevel: int) =
  discard obj.setProp("level", newLevel.md)

proc pubRead*(obj: MObject): bool =
  obj.getPropVal("pubread") == 1.md
proc `pubRead=`*(obj: MObject, newVal: bool) =
  discard obj.setProp("pubread", if newVal: 1.md else: 0.md)

proc pubWrite*(obj: MObject): bool =
  obj.getPropVal("pubwrite") == 1.md
proc `pubWrite=`*(obj: MObject, newVal: bool) =
  discard obj.setProp("pubwrite", if newVal: 1.md else: 0.md)

proc fertile*(obj: MObject): bool =
  obj.getPropVal("fertile") == 1.md
proc `fertile=`*(obj: MObject, newVal: bool) =
  discard obj.setProp("fertile", if newVal: 1.md else: 0.md)

proc `==`(d: MData, obj: MObject): bool =
  d == obj.md

## Permissions handling

proc isWizard*(obj: MObject): bool = obj.level == 0

proc owns*(who, obj: MObject): bool {.inline.} =
  who.isWizard() or obj.owner == who
proc owns*(who: MObject, prop: MProperty): bool {.inline.} =
  who.isWizard() or prop.owner == who
proc owns*(who: MObject, verb: MVerb): bool {.inline.} =
  who.isWizard() or verb.owner == who.id

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
    objO = world.dataToObj(objd)
  if objO.isSome():
    return objO.get().toObjStr()
  else:
    return "Invalid object ($1)" % $objd

#import verbs

proc hasPropCalled(obj: MObject, name: string): bool =
  obj.getPropAndObj(name).isSome

# The following two procs assume that `obj` has a property called `name` and as
# such does not bother to check.
proc propIsInherited*(obj: MObject, name: string): bool =
  let parent = obj.parent
  return not isNil(parent) and obj.parent != obj and obj.parent.hasPropCalled(name)

proc propIsInherited*(obj: MObject, prop: MProperty): bool =
  propIsInherited(obj, prop.name)

proc getPropAndObj*(obj: MObject, name: string, all = true): Option[tuple[o: MObject, p: MProperty]] =
  for p in obj.props:
    if p.name == name:
      return some((obj, p))

  if all:
    let parent = obj.parent
    if not isNil(parent) and parent != obj:
      return parent.getPropAndObj(name, all)

  return none((MObject, MProperty))

proc getProp*(obj: MObject, name: string, all = true): MProperty =
  obj.getPropAndObj(name, all).map(r => r.p).get(nil)

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

proc setProp*(obj: MObject, name: string, newVal: MData):
              tuple[p: MProperty, e: MData] =
  var p = obj.getProp(name, all = false)
  var e = E_NONE.md("")
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
    if BuiltinPropertyData.hasKey(name):
      let defaultValue = BuiltinPropertyData[name]
      if not newVal.isType(defaultValue.dtype):
        let msg = "Cannot set $#.$# to $#, only to a value of type $#"
        e = E_TYPE.md(msg % [$obj.md, name, $newVal, $defaultValue.dtype])
        p.val = defaultValue
      else:
        p.val = newVal
    else:
      p.val = newVal

  return (p, e)

proc delProp*(obj: MObject, prop: MProperty): MProperty =
  for idx, propName in obj.getOwnProps():
    if propName == prop.name:
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
    if not propIsInherited(obj, name):
      result.add(name)

proc getLocation*(obj: MObject): MObject =
  let world = obj.getWorld()
  if isNil(world):
    raise newException(InvalidWorldError, "world is nil")

  let locd = obj.getPropVal("location")

  if not locd.isType(dObj):
    raise newException(InvalidWorldError, "$#.location wasn't an object".format(locd))
  let locO = world.byID(locd.objVal)

  if locO.isSome():
    let loc = locO.get()
    if not isNil(loc):
      return loc

  raise newException(InvalidWorldError, "$# doesn't exist".format(locd))

proc getRawContents(obj: MObject): seq[MData] =
  let contents = obj.getPropVal("contents")
  return contents.listVal

proc getContents*(obj: MObject): seq[MObject] =
  newSeq(result, 0)

  let world = obj.getWorld()
  if isNil(world): return

  var contents = obj.getRawContents();

  for o in contents:
    if o.isType(dObj):
      let containedO = world.byID(o.objVal)
      if containedO.isSome():
        result.add(containedO.get())

proc addToContents*(obj: MObject, newMember: MObject): bool =
  # Note: we do not mutate the contents, rather we copy it
  var contents = obj.getRawContents()
  contents.add(newMember.md)
  obj.setPropR("contents", contents)
  return true

proc removeFromContents*(obj: MObject, member: MObject): bool =
  var contents = obj.getRawContents();

  contents.keepItIf(it.objVal != member.getID())

  obj.setPropR("contents", contents)
  return true

proc moveTo*(obj: MObject, newLoc: MObject): bool =
  var loc = obj.getLocation()
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
  var newid = ObjID(world.objects.len)

  obj.setID(newid)
  obj.setWorld(world)
  world.objects.add(obj)

proc createWorld*(name: string, persistent = true): World =
  result = newWorld()
  result.name = name
  result.persistent = persistent
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


#import persist

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

  let nowhereO = world.dataToObj(nowhered)
  if not nowhereO.isSome():
    raise newException(InvalidWorldError, "the $nowhere object didn't exist")

  let nowhere = nowhereO.get()

  if isNil(nowhere.getProp("contents")):
    raise newException(InvalidWorldError, "the $nowhere object needs to have contents")

proc checkObjectHierarchyHelper(world: World, root: MObject) =
  root.children.keepItIf(not isNil(it))
  for child in root.children:
    if child != root:
      world.checkObjectHierarchyHelper(child)

proc checkObjectHierarchy(world: World) =
  let rootO = world.dataToObj(world.getGlobal("root"))
  if rootO.isSome():
    world.checkObjectHierarchyHelper(rootO.get())
  else:
    raise newException(InvalidWorldError, "$root object didn't exist")

proc checkBuiltinProperties(world: World) =
  for obj in world.getObjects()[]:
    if isNil(obj): continue
    for propName, defaultValue in BuiltinPropertyData.pairs:
      let prop = obj.getProp(propName)
      if isNil(prop):
        let msg = "$# needs to have property $#. It will be set to the default value $#."
        warn msg % [$obj.md, propName, $defaultValue]
        discard obj.setProp(propName, defaultValue)
      else:
        let val = prop.val
        if not val.isType(defaultValue.dtype):
          let msg = "$#.$# needs to be of type $# (it was $#). It will be set to the default value $#."
          warn msg % [$obj, propName, $val.dtype, $defaultValue.dtype, $defaultValue]
          discard obj.setProp(propName, defaultValue)

# This checks if the world is fit to be used
proc check*(world: World) =
  world.checkRoot()
  world.checkNowhere()
  world.checkObjectHierarchy()
  world.checkBuiltinProperties()
