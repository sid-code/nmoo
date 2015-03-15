import types, objects, scripting, verbs, os, sequtils, strutils

# object format:
#
# id
# isPlayer
# level
# pubRead pubWrite fertile (3-bit number)
#
# parent-id
# childrens'-ids (one line, sep'd by spaces)
#
# number of props
# each prop (separated by line containing ".")
# number of verbs
# each verb (separated by line containing ".")

# property format:
#
# name
# value
# owner-id
# inherited
# copyVal
# pubRead pubWrite ownerIsParent (3-bit number)

# verb format:
# names
# code (terminated by line containing ".")
# owner-id
# inherited
# doSpec prepSpec ioSpec (sep'd by spaces)
# pubRead pubWrite pubExec (3-bit number)


template addLine(orig, newLine: string) =
  orig &= newLine
  orig &= "\n"

proc pack(bits: varargs[bool]): int =
  result = 0
  for bit in bits:
    result = result shl 1
    if bit:
      result = result or 1

proc unpack3(packed: int): tuple[a: bool, b: bool, c: bool] =
  var p = packed
  result.c = (p and 1) == 1
  p = p shr 1
  result.b = (p and 1) == 1
  p = p shr 1
  result.a = (p and 1) == 1

proc dumpData(data: MData): string =
  toCodeStr(@[data].md)

proc dumpObjID(obj: MObject): string =
  if obj == nil:
    "-1"
  else:
    $obj.getID()

proc dumpBool(b: bool): string =
  if b:
    $1
  else:
    $0

proc dumpProperty(prop: MProperty): string =
  result = ""
  result.addLine(prop.name)
  result.addLine(dumpData(prop.val))
  result.addLine(dumpObjID(prop.owner))
  result.addLine(dumpBool(prop.inherited))
  result.addLine(dumpBool(prop.copyVal))
  result.addLine($pack(prop.pubRead, prop.pubWrite, prop.ownerIsParent))

proc dumpVerb(verb: MVerb): string =
  result = ""
  result.addLine(verb.names)
  result.addLine(verb.code)
  result.addLine(".")
  result.addLine(dumpObjID(verb.owner))
  result.addLine(dumpBool(verb.inherited))
  result.addLine(([$verb.doSpec, $verb.prepSpec, $verb.ioSpec].join(" ")))
  result.addLine($pack(verb.pubRead, verb.pubWrite, verb.pubExec))

proc dumpObject*(obj: MObject): string =
  result = ""
  result.addLine($obj.getID())
  result.addLine(dumpBool(obj.isPlayer))
  result.addLine($obj.level)
  result.addLine($pack(obj.pubRead, obj.pubWrite, obj.fertile))
  result.addLine(dumpObjID(obj.parent))
  result.addLine(obj.children.map(dumpObjID).join(" "))
  result.addLine($obj.props.len)
  for prop in obj.props:
    result.add(dumpProperty(prop))
    result.addLine(".")
  result.addLine($obj.verbs.len)
  for verb in obj.verbs:
    result.add(dumpVerb(verb))
    result.addLine(".")

proc readNum(stream: File): int =
  let line = stream.readLine().strip()
  return parseInt(line)

proc readData(stream: File): MData =
  let line = stream.readLine().strip()
  var parser = newParser(line)
  
  let
    resultd = parser.parseList()
    result = resultd.listVal

  return result[0]
  

proc readProp(world: World, stream: File): MProperty =
  result = newProperty(
    name = "",
    val = nilD,
    owner = nil
  )
  result.name = stream.readLine().strip()
  result.val = readData(stream)
  result.owner = world.byID(readNum(stream).id)
  result.inherited = readNum(stream) == 1
  result.copyVal = readNum(stream) == 1
  let (pr, pw, oip) = unpack3(readNum(stream))
  result.pubRead = pr
  result.pubWrite = pw
  result.ownerIsParent = oip

  doAssert(stream.readLine().strip() == ".")

proc readVerb(world: World, stream: File): MVerb =
  result = newVerb(
    names = "",
    owner = nil
  )
  result.names = stream.readLine().strip()
  var
    code = ""
    curLine = ""

  while curLine != ".":
    code &= curLine
    curLine = stream.readLine()

  result.setCode(code)
  
  result.owner = world.byID(readNum(stream).id)
  result.inherited = readNum(stream) == 1
  let specs = stream.readLine().split(" ")
  doAssert(specs.len == 3)
  result.doSpec = parseEnum[ObjSpec](specs[0])
  result.prepSpec = parseEnum[PrepType](specs[1])
  result.ioSpec = parseEnum[ObjSpec](specs[2])

  let (pr, pw, pe) = unpack3(readNum(stream))
  result.pubRead = pr
  result.pubWrite = pw
  result.pubExec = pe

  doAssert(stream.readLine().strip() == ".")

proc readObject(world: World, stream: File) =
  let id = readNum(stream).id
  var obj = world.byID(id)
  
  obj.setID(id)
  obj.isPlayer = readNum(stream) == 1
  obj.level = readNum(stream)
  let (pr, pw, fert) = unpack3(readNum(stream))
  obj.pubRead = pr
  obj.pubWrite = pw
  obj.fertile = fert

  let parentID = readNum(stream)
  if parentID == -1:
    obj.parent = nil
  else:
    obj.parent = world.byID(parentID.id)

  obj.children = @[]
  let children = stream.readLine().split(" ")
  for child in children:
    let childID = parseInt(child)
    obj.children.add(world.byID(childID.id))
  
  obj.props = @[]
  let numProps = readNum(stream)
  for i in 0 .. numProps - 1:
    obj.props.add(readProp(world, stream))

  obj.verbs = @[]
  let numVerbs = readNum(stream)
  for i in 0 .. numVerbs - 1:
    obj.verbs.add(readVerb(world, stream))

  obj.world = world

proc getWorldDir(name: string): string =
  "worlds" / name

proc getObjectFile(worldName: string, id: int): string =
  getWorldDir(worldName) / $id

proc persist*(world: World, obj: MObject) =
  let fileName = getObjectFile(world.name, obj.getID().int)
  if not existsFile(fileName):
    return

  let file = open(fileName, fmWrite)

  file.write(dumpObject(obj))

  file.close()

proc persist*(world: World) =
  if existsDir(getWorldDir(world.name)):
    for obj in world.getObjects()[]:
      if obj != nil:
        world.persist(obj)

proc loadWorld*(name: string): World =
  result = createWorld(name)
  let dir = getWorldDir(name)
  var objs = result.getObjects()
  for file in walkFiles(dir / "*"):
    let
      obj = blankObject()
      (p, fname) = splitPath(file)
      id = parseInt(fname)

    obj.setID(id.id)
    
    discard p
    if id >= objs[].len:
      setLen(objs[], id * 2)

    objs[id] = obj

  for file in walkFiles(dir / "*"):
    let fh = open(file, fmRead)
    readObject(result, fh)
    fh.close()

  result.verbObj = objs[0]

when isMainModule:
  let obj = blankObject()
  obj.setPropR("name", "obj")
  stdout.write(dumpObject(obj))
