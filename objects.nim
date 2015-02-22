import types, scripting, sequtils, strutils

proc getStrProp*(obj: MObject, name: string): string
proc getAliases*(obj: MObject): seq[string]
proc getLocation*(obj: MObject): MObject
proc getContents*(obj: MObject): tuple[hasContents: bool, contents: seq[MObject]]
import verbs

proc setCode(verb: MVerb, newCode: string) =
  var parser = newParser(newCode)
  verb.parsed = parser.parseList()


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
  var result = obj.getProp(name)
  if result == nil:
    nilD
  else:
    result.val

proc setProp*(obj: MObject, name: string, newVal: MData) =
  var p = obj.getProp(name)
  if p == nil:
    obj.props.add(newProperty(
      name,
      newVal,
      obj,
      false,
      false,

      true,
      false,
      true
    ))
  else:
    p.val = newVal

template setPropR*(obj: MObject, name: string, newVal: expr) =
  obj.setProp(name, newVal.md)

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

  var result: seq[MObject] = @[]

  var (has, contents) = obj.getRawContents();

  if has:
    for o in contents:
      if o.isType(dObj):
        result.add(world.byID(o.objVal))

    return (true, result)
  else:
    return (false, @[])



proc addToContents*(obj: MObject, newMember: var MObject): bool =
  var (has, contents) = obj.getRawContents();
  if has:
    contents.add(newMember.md)
    obj.setPropR("contents", contents)
    return true
  else:
    return false

proc removeFromContents(obj: MObject, member: var MObject): bool =
  var (has, contents) = obj.getRawContents();

  if has:
    for idx, o in contents:
      if o.objVal == obj.getID():
        system.delete(contents, idx)

    obj.setPropR("contents", contents)
    return true
  else:
    return false


proc getAliases*(obj: MObject): seq[string] =
  let aliases = obj.getPropVal("aliases")
  var result: seq[string] = @[]

  if aliases.isType(dList):
    for o in aliases.listVal:
      if o.isType(dStr):
        result.add(o.strVal)

  return result

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

proc createWorld*: World =
  result = newWorld()
  result.add(blankObject())

proc size*(world: World): int =
  world.getObjects()[].len

proc delete*(world: var World, obj: MObject) =
  var objs = world.getObjects()
  var idx = obj.getID().int

  objs[idx] = nil

proc changeParent*(obj: var MObject, newParent: var MObject) =
  if not newParent.fertile:
    return

  if obj.parent != nil:
    # delete currently inherited properties
    obj.props.keepItIf(not it.inherited)
    obj.verbs.keepItIf(not it.inherited)

    # remove this from old parent's children
    obj.parent.children.keepItIf(it != obj)


  for p in newParent.props:
    var pc = p.copy
    pc.inherited = true

    # only copy the value of the property if specified by the property

    if not pc.copyVal:
      pc.val = blank(pc.val.dtype)


    obj.props.add(pc)

  for v in obj.verbs:
    var vc = v.copy
    vc.inherited = true
    obj.verbs.add(vc)

  obj.parent = newParent
  newParent.children.add(obj)

proc createChild*(parent: var MObject): MObject =
  if not parent.fertile:
    return nil

  var newObj = blankObject()

  newObj.isPlayer = parent.isPlayer
  newObj.pubRead = parent.pubRead
  newObj.pubWrite = parent.pubWrite
  newObj.fertile = parent.fertile

  newObj.changeParent(parent)

  return newObj

proc moveTo*(obj: var MObject, newLoc: var MObject): bool =
  var loc = obj.getLocation()
  if loc == newLoc:
    return false
  if loc != nil:
    discard loc.removeFromContents(obj)

  if newLoc.addToContents(obj):
    obj.setPropR("location", newLoc)
    return true
  else:
    return false
