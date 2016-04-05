# When the world handles a command, it needs to resolve strings passed by
# the player such as "clock" in "get clock". This resolution is done here.

import sequtils
import strutils
import tables

import types
import objects

proc startsWith(s1, s2: string): bool =
  if s1.len < s2.len: return false

  for idx, ch in s2:
    if ch != s1[idx]: return false

  return true

proc matches(obj: MObject, str: string): bool =
  if str.len == 0:
    return false

  let name = obj.getStrProp("name")
  if name.startsWith(str): return true

  for alias in obj.getAliases():
    if alias.startsWith(str): return true

  return false

proc getVicinity*(obj: MObject): seq[MObject] =
  newSeq(result, 0)

  let loc = obj.getLocation()

  if not isNil(loc):
    result.add(loc)
    let (has, contents) = loc.getContents()
    if has:
      for o in contents: result.add(o)
  else:
    result.add(obj)

  let (has, contents) = obj.getContents()
  if has:
    for o in contents: result.add(o)

proc query*(obj: MObject, str: string, global = false): seq[MObject] =
  newSeq(result, 0)
  let world = obj.getWorld()
  assert(not isNil(world))

  if str == "me":
    return @[obj]
  if str == "here":
    let loc = obj.getLocation()
    if not isNil(loc):
      return @[loc]

  if str[0] == '$':
    let tail = str[1..^1]
    let prop = world.verbObj.getProp(tail)
    if not isNil(prop):
      let val = prop.val
      if val.isType(dObj):
        return @[world.dataToObj(val)]

  if str.len > 0:
    if str[0] == '#':
      try:
        let
          id = parseInt(str[1 .. ^1]).id
          fobj = world.byID(id)
        if not isNil(fobj):
          result.add(fobj)
      except:
        discard # let it be


  let searchSpace = if global: world.getObjects()[] else: obj.getVicinity()

  result.add(searchSpace.filterIt(not isNil(it) and it.matches(str)))
