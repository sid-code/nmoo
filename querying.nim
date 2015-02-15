import objects, sequtils

proc getLocation(obj: MObject): MObject =
  let world = obj.world
  if world == nil: return nil

  let loc = obj.getPropVal("location")

  if loc.isType(dObj):
    return world.byID(loc.objVal)
  else:
    return nil

proc getContents(obj: MObject): seq[MObject] =
  let world = obj.world
  if world == nil: return nil

  let contents = obj.getPropVal("contents")
  var result: seq[MObject] = @[]

  if contents.isType(dList):
    for o in contents.listVal:
      if o.isType(dObj):
        result.add(world.byID(o.objVal))

  return result

proc getAliases(obj: MObject): seq[string] =
  let aliases = obj.getPropVal("aliases")
  var result: seq[string] = @[]

  if aliases.isType(dList):
    for o in aliases.listVal:
      if o.isType(dStr):
        result.add(o.strVal)

  return result

proc getStrProp(obj: MObject, name: string): string =
  let datum = obj.getPropVal(name)

  if datum.isType(dStr):
    return datum.strVal
  else:
    return ""

proc startsWith(s1, s2: string): bool =
  if s1.len < s2.len: return false

  for idx, ch in s1:
    if ch != s2[idx]: return false

  return true

proc matches(obj: MObject, str: string): bool =
  let name = obj.getStrProp("name")
  if name.startsWith(str): return true

  for alias in obj.getAliases():
    if alias.startsWith(str): return true

  return false

proc query*(obj: MObject, str: string): seq[MObject] =
  var searchSpace: seq[MObject] = @[]

  let loc = obj.getLocation()

  if loc != nil:
    for o in loc.getContents(): searchSpace.add(o)

  for o in obj.getContents(): searchSpace.add(o)

  return searchSpace.filterIt(it.matches(str))
