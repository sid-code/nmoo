import types, objects, sequtils


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

  result = @[]

  let loc = obj.getLocation()

  if loc != nil:
    result.add(loc)
    let (has, contents) = loc.getContents()
    if has:
      for o in contents: result.add(o)

  let (has, contents) = obj.getContents()
  if has:
    for o in contents: result.add(o)

proc query*(obj: MObject, str: string): seq[MObject] =
  obj.getVicinity().filterIt(it.matches(str))
