# This code dumps and reads tasks from a compact binary format.

import streams
import asyncdispatch
import boost/io/asyncstreams
import times
import tables
import std/options

import types
import util/msstreams

proc writePos(s: Stream | AsyncStream, pos: CodePosition) {.multisync.} =
  await s.write(int32(pos.line))
  await s.write(int32(pos.col))

proc readPos(s: Stream | AsyncStream): Future[CodePosition] {.multisync.} =
  result.line = await s.readInt32()
  result.col = await s.readInt32()

proc writeTime(s: Stream | AsyncStream, t: Time) {.multisync.} =
  await s.write(t.toUnix())

proc readTime(s: Stream | AsyncStream): Future[Time] {.multisync.} =
  return fromUnix(await s.readInt64())

proc writeMData*(s: Stream | AsyncStream, d: MData) {.multisync.} =
  # The data type is encoded as an unsigned 8 bit integer. The 7 least
  # significant bits are used to encode the type, and the most significant
  # bit is flipped when the MData object has a position. If so, this position
  # immediately follows as two signed 32 bit integers.
  var dtype7bit: uint8 = uint8(d.dtype)

  let needToWritePos = d.pos != (0, 0)
  if needToWritePos:
    dtype7bit = dtype7bit or uint8(1 shl 7) # sets the sign bit to 1

  await s.write(dtype7bit)

  if needToWritePos:
    await s.writePos(d.pos)

  case d.dtype:
    of dInt:
      await s.write(int64(d.intVal))
    of dFloat:
      await s.write(float64(d.floatVal))
    of dStr:
      let str = d.strVal
      await s.writeStrl(str)
    of dSym:
      let sym = d.symVal
      await s.writeStrl(sym)
    of dErr:
      let err = d.errVal
      let msg = d.errMsg
      await s.write(int8(err))
      await s.writeStrl(msg)

      await s.write(int32(d.trace.len))
      for fdesc in d.trace:
        await s.writeStrl(fdesc.name)
        await s.writePos(fdesc.pos)
    of dList:
      let list = d.listVal
      await s.write(int32(list.len))
      for el in list:
        await s.writeMData(el)
    of dTable:
      let hmap = d.tableVal
      await s.write(int32(hmap.len))
      for key, val in pairs(hmap):
        await s.writeMData(key)
        await s.writeMData(val)
    of dObj:
      await s.write(int32(d.objVal))
    of dNil:
      discard

proc readMData*(s: Stream | AsyncStream): Future[MData] {.multisync.} =
  var dtype7bit = uint8(await s.readInt8())
  let firstBit = uint8(1) == dtype7bit shr 7

  let pos = if firstBit:
    dtype7bit = dtype7bit and (1 shl 7 - 1)
    let line = int(await s.readInt32())
    let col = int(await s.readInt32())
    (line, col)
  else:
    (0, 0)

  case MDataType(dtype7bit):
    of dInt:
      result = int(await s.readInt64()).md
    of dFloat:
      result = float(await s.readFloat64()).md
    of dStr:
      result = (await s.readStrl()).md
    of dSym:
      result = (await s.readStrl()).mds
    of dErr:
      result = MError(await s.readInt8()).md
      result.errMsg = await s.readStrl()
      var size = await s.readInt32()
      newSeq(result.trace, size)
      setLen(result.trace, 0)
      while size > 0:
        dec size
        let name = await s.readStrl()
        let pos = await s.readPos()
        result.trace.add( (name, pos) )

    of dList:
      result = @[].md
      var size = await s.readInt32()
      while size > 0:
        dec size
        result.listVal.add(await s.readMData())
    of dTable:
      var size = await s.readInt32()
      var mappairs: seq[(MData, MData)]
      while size > 0:
        dec size
        let key = await s.readMData()
        let val = await s.readMData()
        mappairs.add( (key, val) )
      result = mappairs.md
    of dObj:
      result = ObjID(int(await s.readInt32())).md
    of dNil:
      discard

  result.pos = pos

proc writeVSymTable(s: Stream | AsyncStream, vst: VSymTable) {.multisync.} =
  await s.write(int32(vst.len))
  for k, v in vst.pairs:
    await s.write(int32(k))
    await s.writeMData(v)

proc readVSymTable(s: Stream | AsyncStream): Future[VSymTable] {.multisync.} =
  result = initTable[int, MData]()
  var count = await s.readInt32()
  while count > 0:
    dec count
    let key = int(await s.readInt32())
    let val = await s.readMData()
    result[key] = val

proc writeSymbolTable(s: Stream | AsyncStream, st: SymbolTable) {.multisync.} =
  await s.write(int32(st.len))
  for k, v in st.pairs:
    await s.writeStrl(k)
    await s.writeMData(v)

proc readSymbolTable(s: Stream | AsyncStream): Future[SymbolTable] {.multisync.} =
  result = newSymbolTable()

  var count = await s.readInt32()
  while count > 0:
    dec count
    let key = await s.readStrl()
    let val = await s.readMData()
    result[key] = val


proc `$`(fr: Frame): string {.used.} =
  $fr.symtable & " " & $fr.tries

proc writeFrame(s: Stream | AsyncStream, fr: Frame) {.multisync.} =
  await s.writeVSymTable(fr.symtable)
  await s.write(int32(fr.calledFrom))

  await s.write(int32(fr.tries.len))
  for t in fr.tries:
    await s.write(int32(t))

proc readFrame(s: Stream | AsyncStream): Future[Frame] {.multisync.} =
  new result
  result.symtable = await s.readVSymTable()
  result.calledFrom = await s.readInt32()

  var count = await s.readInt32()
  newSeq(result.tries, 0)
  while count > 0:
    dec count
    result.tries.add(int(await s.readInt32()))

proc writeContinuation(s: Stream | AsyncStream, cont: Continuation) {.multisync.} =
  await s.write(int32(cont.pc))

  await s.write(int32(cont.stack.len))
  for el in cont.stack:
    await s.writeMData(el)

  await s.writeSymbolTable(cont.globals)

  await s.write(int32(cont.frames.len))
  for fr in cont.frames:
    await s.writeFrame(fr)

proc readContinuation(s: Stream | AsyncStream): Future[Continuation] {.multisync.} =
  result.pc = int(await s.readInt32())

  newSeq(result.stack, 0)
  var count = await s.readInt32()
  while count > 0:
    dec count
    result.stack.add(await s.readMData())

  result.globals = await s.readSymbolTable()

  newSeq(result.frames, 0)
  count = await s.readInt32()
  while count > 0:
    dec count
    result.frames.add(await s.readFrame())

proc writeInstruction(s: Stream | AsyncStream, inst: Instruction) {.multisync.} =
  await s.write(int8(inst.itype))
  await s.writeMData(inst.operand)
  await s.write(int32(inst.pos.line))
  await s.write(int32(inst.pos.col))

proc readInstruction(s: Stream | AsyncStream): Future[Instruction] {.multisync.} =
  result = Instruction(itype: InstructionType(await s.readInt8()))
  result.operand = await s.readMData()
  result.pos.line = await s.readInt32()
  result.pos.col = await s.readInt32()

proc writePackage(s: Stream | AsyncStream, p: Package) {.multisync.} =
  await s.write(int8(p.ptype))
  case p.ptype:
    of ptData:
      await s.writeMData(p.val)
    of ptCall, ptInput:
      await s.write(int8(p.phase))

proc readPackage(s: Stream | AsyncStream): Future[Package] {.multisync.} =
  result = Package(ptype: PackageType(await s.readInt8()))
  case result.ptype:
    of ptData:
      result.val = await s.readMData()
    of ptCall, ptInput:
      result.phase = await s.readInt8()

proc writeTask*(s: Stream | AsyncStream, t: Task) {.multisync.} =
  await s.write(int32(t.id))
  await s.writeStrl(t.name)
  await s.writeTime(t.startTime)

  await s.writeMData(t.stack.md)
  
  await s.writeSymbolTable(t.globals)

  await s.write(int32(t.code.len))
  for inst in t.code:
    await s.writeInstruction(inst)

  await s.write(int32(t.pc))

  await s.write(int32(t.frames.len))
  for fr in t.frames:
    await s.writeFrame(fr)

  await s.write(int32(t.continuations.len))
  for cont in t.continuations:
    await s.writeContinuation(cont)

  await s.write(int8(t.status))
  await s.writeTime(t.suspendedUntil)
  await s.write(int32(t.tickCount))
  await s.write(int32(t.tickQuota))

  await s.write(int8(t.hasCallPackage))
  await s.writePackage(t.callPackage)
  await s.writeMData(t.builtinToCall)
  await s.writeMData(t.builtinArgs.md)

  await s.write(int8(t.taskType))
  await s.write(t.callback.get(TaskID(-1)).int32)
  await s.write(t.waitingFor.get(TaskID(-1)).int32)
  

proc readTaskID(s: Stream | AsyncStream): Future[Option[TaskID]] {.multisync.} =
  let id = await s.readInt32()
  if id == -1:
    return none(TaskID)
  else:
    return some(id.TaskID)

proc readTask*(s: Stream | AsyncStream): Future[Task] {.multisync.} =
  var t: Task
  var count: int32

  new t

  t.id = TaskID(await s.readInt32())
  t.name = await s.readStrl()
  t.startTime = await s.readTime()

  let stackd = await s.readMData()
  t.stack = stackd.listVal

  t.globals = await s.readSymbolTable()
  
  newSeq(t.code, 0)
  count = await s.readInt32()
  while count > 0:
    dec count
    let inst = await s.readInstruction()
    t.code.add(inst)

  t.pc = await s.readInt32()

  count = await s.readInt32()
  newSeq(t.frames, 0)
  while count > 0:
    dec count
    let fr = await s.readFrame()

    t.frames.add(fr)

  count = await s.readInt32()
  newSeq(t.continuations, 0)
  while count > 0:
    dec count
    t.continuations.add(await s.readContinuation())


  t.status = TaskStatus(await s.readInt8())
  t.suspendedUntil = await s.readTime()
  t.tickCount = await s.readInt32()
  t.tickQuota = await s.readInt32()

  t.hasCallPackage = (await s.readInt8()) == 1
  t.callPackage = await s.readPackage()
  t.builtinToCall = await s.readMData()
  let builtinArgsd = await s.readMData()
  t.builtinArgs = builtinArgsd.listVal

  t.taskType = TaskType(await s.readInt8())

  t.callback = await s.readTaskID()
  t.waitingFor = await s.readTaskID()

  return t

#when not isMainModule:
#  import scripting
#  defBuiltin "twt":
#    var ss = newStringStream()
#    ss.writeTask(task)
#
#    var oss = newStringStream(ss.data)
#    let taskCopy = oss.readTask()

