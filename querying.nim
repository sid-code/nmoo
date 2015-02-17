import objects, sequtils


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
    let (has, contents) = loc.getContents()
    if has:
      for o in contents: searchSpace.add(o)

  let (has, contents) = obj.getContents()
  if has:
    for o in contents: searchSpace.add(o)

  return searchSpace.filterIt(it.matches(str))
