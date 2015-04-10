import types, objects, verbs, scripting, os, sequtils, strutils, marshal

# object format:
#
# id
# isPlayer
# owner
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
  result.addLine(dumpObjID(obj.owner))
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

proc dumpTask(task: Task): string =
  result = ""
  let owner = task.owner
  let caller = task.caller

  task.owner = nil
  task.caller = nil
  task.world = nil

  result.addLine($$task)
  result.addLine($owner.getID())
  result.addLine($caller.getID())

proc readNum(stream: File): int =
  let line = stream.readLine().strip()
  return parseInt(line)

proc readData(stream: File): MData =
  let line = stream.readLine().strip()
  var parser = newParser(line)

  let
    resultd = parser.parseList()
    res = resultd.listVal

  return res[0]

proc readObjectID(world: World, stream: File, default: MObject = world.verbObj):
                  MObject =
  let id = readNum(stream)
  if id == -1:
    return world.verbObj

  result = world.byID(id.id)
  if result == nil:
    return world.verbObj
  else:
    return result

proc readProp(world: World, stream: File): MProperty =
  result = newProperty(
    name = "",
    val = nilD,
    owner = nil
  )
  result.name = stream.readLine().strip()
  result.val = readData(stream)
  result.owner = readObjectID(world, stream)

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

  result.owner = readObjectID(world, stream)

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
  obj.owner = readObjectID(world, stream)

  let (pr, pw, fert) = unpack3(readNum(stream))
  obj.pubRead = pr
  obj.pubWrite = pw
  obj.fertile = fert

  obj.parent = readObjectID(world, stream, nil)

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

proc readTask(world: World, stream: File) =
  let task = to[Task](stream.readLine())
  task.owner = readObjectID(world, stream)
  task.caller = readObjectID(world, stream)
  world.tasks.add(task)

proc readExtras(world: World, stream: File) =
  let ctr = readNum(stream)
  world.taskIDCounter = ctr

proc getWorldDir*(name: string): string =
  "worlds" / name

proc getObjectDir*(name: string): string =
  getWorldDir(name) / "objects"

proc getObjectFile(worldName: string, id: int): string =
  getObjectDir(worldName) / $id

proc getTaskDir(name: string): string =
  getWorldDir(name) / "tasks"

proc getTaskFile(name: string, id: int): string =
  getTaskDir(name) / $id

proc getExtrasFile(name: string): string =
  getWorldDir(name) / "extras"

proc persist*(world: World, obj: MObject) =
  let fileName = getObjectFile(world.name, obj.getID().int)
  let file = open(fileName, fmWrite)
  file.write(dumpObject(obj))
  file.close()

proc persist*(world: World, task: Task) =
  let fileName = getTaskFile(world.name, task.id)
  let file = open(fileName, fmWrite)
  file.write(dumpTask(task))
  file.close()

proc persistExtras(world: World) =
  let fileName = getExtrasFile(world.name)
  let file = open(fileName, fmWrite)
  file.write($world.taskIDCounter)
  file.close()

proc persist*(world: World) =
  if existsDir(getWorldDir(world.name)):
    world.persistExtras()

    createDir(getObjectDir(world.name))
    for obj in world.getObjects()[]:
      if obj != nil:
        world.persist(obj)
    createDir(getTaskDir(world.name))
    for task in world.tasks:
      world.persist(task)

proc loadWorld*(name: string): World =
  result = createWorld(name)
  let dir = getObjectDir(name)
  var objs = result.getObjects()
  var maxid = 0

  let extrasFileName = getExtrasFile(name)
  let extrasFile = open(extrasFileName, fmRead)

  readExtras(result, extrasFile)

  extrasFile.close()

  for fileName in walkFiles(dir / "*"):
    let
      obj = blankObject()
      (p, fname) = splitPath(fileName)
      id = parseInt(fname)

    if id > maxid:
      maxid = id

    obj.setID(id.id)

    discard p
    if id >= objs[].len:
      setLen(objs[], id * 2)

    objs[id] = obj

  setLen(objs[], maxid + 1)

  for fileName in walkFiles(dir / "*"):
    let file = open(fileName, fmRead)
    readObject(result, file)
    file.close()

  let taskdir = getTaskDir(name)
  for fileName in walkFiles(taskdir / "*"):
    let file = open(fileName, fmRead)
    readTask(result, file)
    file.close()

    # tasks are ephemeral
    removeFile(fileName)

  result.verbObj = objs[0]

when isMainModule:
  let obj = blankObject()
  obj.setPropR("name", "obj")
  stdout.write(dumpObject(obj))
