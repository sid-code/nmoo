# This code dumps objects and verbs into a somewhat human-readable plaintext
# format.

# Tasks are dumped to binary, however, using the bytedump module.

import os
import streams
import sequtils
import strutils
import marshal
import tables
import logging
import asyncdispatch

import types
import objects
import verbs
import scripting
import bytedump

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
  $(@[data].md)

proc dumpObjID(obj: MObject): string =
  if isNil(obj):
    ""
  else:
    $obj.getID()

proc dumpObjID(objd: MData): string =
  if not objd.isType(dObj):
    ""
  else:
    $objd.objVal

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
  result.addLine(verb.code.strip())
  result.addLine(".")
  result.addLine(dumpObjID(verb.owner))
  result.addLine(dumpBool(verb.inherited))
  result.addLine(([$verb.doSpec, $verb.prepSpec, $verb.ioSpec].join(" ")))
  result.addLine($pack(verb.pubRead, verb.pubWrite, verb.pubExec))

proc writeVerbCode*(world: World, obj: MObject, init = false)
proc dumpObject*(obj: MObject): string =
  result = ""
  result.addLine($obj.getID())
  result.addLine(dumpBool(obj.isPlayer))
  result.addLine(dumpObjID(obj.parent))
  result.addLine(obj.children.map(dumpObjID).join(" "))
  result.addLine($obj.props.len)
  for prop in obj.props:
    result.add(dumpProperty(prop))
    result.addLine(".")
  result.addLine($obj.verbs.len)
  for verb in obj.verbs:
    writeVerbCode(obj.world, obj)
    result.add(dumpVerb(verb))
    result.addLine(".")

proc dumpTask(task: Task): string =
  let resultSS = newStringStream()

  let self = task.self
  let player = task.player
  let caller = task.caller
  let owner = task.owner
  let world = task.world

  task.self = nil
  task.player = nil
  task.caller = nil
  task.owner = nil
  task.world = nil

  resultSS.writeLine($self.getID())
  resultSS.writeLine($player.getID())
  resultSS.writeLine($caller.getID())
  resultSS.writeLine($owner.getID())
  resultSS.writeTask(task)

  task.self = self
  task.player = player
  task.caller = caller
  task.owner = owner
  task.world = world

  return resultSS.data

proc readNum(stream: FileStream): int =
  let line = stream.readLine().strip()
  return parseInt(line)

proc readData(stream: FileStream): MData =
  let line = stream.readLine().strip()
  var parser = newParser(line)

  let
    resultd = parser.parseList()
    res = resultd.listVal

  return res[0]

proc readObjectID(world: World, stream: FileStream, default: MObject = nil):
                  MObject =
  var default = default
  if isNil(default):
    default = world.verbObj

  let id = readNum(stream)
  if id == -1:
    return world.verbObj

  result = world.byID(id.id)
  return if isNil(result): default else: result

proc readProp(world: World, stream: FileStream): MProperty =
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

proc readVerb(world: World, stream: FileStream): MVerb =
  result = newVerb(
    names = "",
    owner = nil
  )
  result.names = stream.readLine().strip()
  var
    code = ""
    curLine = ""

  while curLine != ".":
    code &= curLine & "\n"
    curLine = stream.readLine()

  result.owner = readObjectID(world, stream)

  let err = result.setCode(code, result.owner, compileIt = false)
  if err != E_NONE.md:
    warn "A verb called \"" & result.names & "\" failed to compile."
    warn $err

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

proc readObject(world: World, stream: FileStream) =
  let id = readNum(stream).id
  var obj = world.byID(id)
  newSeq(obj.props, 0)
  newSeq(obj.children, 0)
  newSeq(obj.verbs, 0)

  obj.setID(id)
  obj.isPlayer = readNum(stream) == 1

  obj.parent = readObjectID(world, stream, nil)

  let childrenStr = stream.readLine()
  if childrenStr.len != 0:
    let children = childrenStr.split(" ")
    for child in children:
      let childID = parseInt(child)
      if childID > 0:
        obj.children.add(world.byID(childID.id))

  let numProps = readNum(stream)
  for i in 0 .. numProps - 1:
    obj.props.add(readProp(world, stream))

  let numVerbs = readNum(stream)
  for i in 0 .. numVerbs - 1:
    obj.verbs.add(readVerb(world, stream))

  obj.world = world

proc readTask(world: World, stream: FileStream) =
  let self = readObjectID(world, stream)
  let player = readObjectID(world, stream)
  let caller = readObjectID(world, stream)
  let owner = readObjectID(world, stream)
  var task = stream.readTask()

  task.self = self
  task.player = player
  task.caller = caller
  task.owner = owner
  task.world = world
  world.tasks.add(task)

proc readObjectCount(world: World, stream: FileStream) =
  let ctr = readNum(stream)
  world.taskIDCounter = ctr

proc setDefaultObjectCount(world: World) =
  world.taskIDCounter = 0

proc getWorldDir*(name: string): string =
  "worlds" / name

proc getWorldLockFile(name: string): string =
  getWorldDir(name) / "lock"

proc getObjectDir*(name: string): string =
  getWorldDir(name) / "objects"

proc getObjectFile(worldName: string, id: int): string =
  getObjectDir(worldName) / $id

proc getTrashDir(name: string): string =
  getWorldDir(name) / "trash"

proc getTaskDir(name: string): string =
  getWorldDir(name) / "tasks"

proc getTaskFile(name: string, id: int): string =
  getTaskDir(name) / $id

proc getExtraFile(name: string, fileName: string): string =
  getWorldDir(name) / fileName

proc getObjectCountFile(name: string): string =
  getExtraFile(name, "objcount")

proc getVerbCodeDir(name: string): string =
  getWorldDir(name) / "verbcode"

proc getObjVerbCodeDir(name: string, id: int): string =
  getVerbCodeDir(name) / $id

proc getVerbCodeFile(verb: MVerb, index: int): string =
  "$#-$#.scm".format(verb.names, index)

proc writeVerbCode*(world: World, obj: MObject, init = false) =
  var dir = getObjVerbCodeDir(world.name, obj.getID().int)
  if init:
    removeDir(dir)

  if not existsDir(dir):
    createDir(dir)

  for index, v in obj.verbs:
    var fileName = dir / getVerbCodeFile(v, index)
    writeFile(fileName, v.code)

proc readVerbCode*(world: World, obj: MObject, verb: MVerb, programmer: MObject): MData =
  var dir = getObjVerbCodeDir(world.name, obj.getID().int)

  let vstr = "$#:$#".format($obj.md, verb.names)

  if not existsDir(dir):
    return E_ARGS.md("cannot read code for verb $# because the verb code directory doesn't exist".format(vstr))

  for index, v in obj.verbs:
    if v == verb:
      var fileName = dir / getVerbCodeFile(v, index)
      return v.setCode(readFile(fileName), programmer)

  return E_ARGS.md("cannot read code for verb $#".format(vstr))

proc persist*(world: World, obj: MObject) =
  if not world.persistent: return

  let fileName = getObjectFile(world.name, obj.getID().int)
  let file = newFileStream(fileName, fmWrite)
  file.write(dumpObject(obj))
  file.close()

proc persist*(world: World, task: Task) =
  if not world.persistent: return

  let fileName = getTaskFile(world.name, task.id)
  let file = newFileStream(fileName, fmWrite)
  file.write(dumpTask(task))
  file.close()

proc persistObjectCount(world: World) =
  if not world.persistent: return

  let fileName = getObjectCountFile(world.name)
  let file = newFileStream(fileName, fmWrite)
  file.write($world.taskIDCounter & "\n")
  file.close()

proc persist*(world: World) =
  if not world.persistent: return

  let oldName = world.name
  let oldDir = getWorldDir(oldName)
  world.name = world.name & ".new"
  let dir = getWorldDir(world.name)

  # Make sure it doesn't even exist
  removeDir(dir)
  createDir(dir)

  world.persistObjectCount()

  createDir(getObjectDir(world.name))

  let trashDir = getTrashDir(world.name)
  createDir(trashDir)

  let verbCodeDir = getVerbCodeDir(world.name)
  createDir(verbCodeDir)

  var objectCount = 0
  for idx, obj in world.getObjects()[]:
    objectCount += 1
    if isNil(obj):
      let deadObject = getObjectFile(world.name, idx)
      if fileExists(deadObject):
        moveFile(deadObject, trashDir / $idx)
    else:
      world.persist(obj)
  info "Wrote " & $objectCount & " objects to disk."

  let taskDir = getTaskDir(world.name)
  createDir(taskDir)

  var taskCount = 0
  for task in world.tasks:
    taskCount += 1
    world.persist(task)

  info "Wrote " & $taskCount & " tasks to disk."

  copyDir(dir, oldDir)
  removeDir(dir)
  world.name = oldName

proc dbDelete*(world: World, obj: MObject) =
  world.delete(obj)
  let id = obj.getID().int
  let objFile = getObjectFile(world.name, id)
  let trashFile = getTrashDir(world.name) / $id
  moveFile(objFile, trashFile)

proc acquireLock*(name: string): bool =
  let lockFile = getWorldLockFile(name)
  if existsFile(lockFile):
    return false

  writeFile(lockFile, "")
  return true

proc releaseLock*(name: string): bool =
  let lockFile = getWorldLockFile(name)
  if existsFile(lockFile):
    removeFile(lockFile)
    return true

  return false

proc backupWorld(name: string) =
  var suffix = 0
  let backupBase = name & ".b"
  var backupDir = getWorldDir(backupBase & $suffix)

  while existsDir(backupDir):
    inc suffix
    backupDir = getWorldDir(backupBase & $suffix)

  copyDir(getWorldDir(name), backupDir)


proc loadWorld*(name: string): World =
  info "Backing up world ", name, " before read..."
  backupWorld(name)
  info "Completed backup."

  result = createWorld(name)
  let dir = getObjectDir(name)
  var objs = result.getObjects()
  var maxid = 0

  try:
    let objcountFile = openFileStream(getObjectCountFile(name), fmRead)
    readObjectCount(result, objcountFile)
    objcountFile.close()
  except IOError:
    warn "IO error when trying to read " & getObjectCountFile(name) & "; using default value"
    setDefaultObjectCount(result)

  var objectCount = 0
  for fileName in walkFiles(dir / "*"):
    objectCount += 1
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
  info "Read " & $objectCount & " objects from disk."

  setLen(objs[], maxid + 1)

  for fileName in walkFiles(dir / "*"):
    let file = newFileStream(fileName, fmRead)
    readObject(result, file)
    file.close()

  let taskdir = getTaskDir(name)
  var taskCount = 0
  for fileName in walkFiles(taskdir / "*"):
    taskCount += 1
    let file = newFileStream(fileName, fmRead)
    readTask(result, file)
    file.close()

    # tasks are ephemeral
    removeFile(fileName)
  info "Read " & $taskCount & " tasks from disk."

  result.verbObj = objs[0]

  for obj in result.getObjects()[]:
    if not obj.isNil:
      writeVerbCode(result, obj)
      for v in obj.verbs:
        when defined(debug):
          debug "Compiling verb " & obj.toObjStr() & ":" & v.names
        # this time really compile it
        let err = v.setCode(v.code, v.owner)
        if err != E_NONE.md:
          error "A verb " & obj.toObjStr() & ":" & v.names & " failed to compile."
          error $err

  var oresult = result

when isMainModule:
  let obj = blankObject()
  obj.setPropR("name", "obj")
  stdout.write(dumpObject(obj))
