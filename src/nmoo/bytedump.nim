# This code dumps and reads tasks from a compact binary format.

import streams
import asyncdispatch
import boost/io/asyncstreams
import times
import tables

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
    of dObj:
      await s.write(int32(d.objVal))
    of dNil:
      discard

proc readMData*(s: Stream | AsyncStream): Future[MData] {.multisync.} =
  var dtype7bit = uint8(await s.readInt8())
  let firstBit = uint8(1) == dtype7bit shr 7
  if firstBit:
    dtype7bit = dtype7bit and (1 shl 7 - 1)
    let line = int(await s.readInt32())
    let col = int(await s.readInt32())
    result.pos = (line, col)
  else:
    result.pos = (0, 0)

  result.dtype = MDataType(dtype7bit)

  case result.dtype:
    of dInt:
      result.intVal = int(await s.readInt64())
    of dFloat:
      result.floatVal = float(await s.readFloat64())
    of dStr:
      result.strVal = await s.readStrl()
    of dSym:
      result.symVal = await s.readStrl()
    of dErr:
      result.errVal = MError(await s.readInt8())
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
      var size = await s.readInt32()
      newSeq(result.listVal, 0)
      while size > 0:
        dec size
        result.listVal.add(await s.readMData())
    of dObj:
      result.objVal = ObjID(int(await s.readInt32()))
    of dNil:
      discard

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

proc writeCSymTable(s: Stream | AsyncStream, cst: CSymTable) {.multisync.} =
  await s.write(int32(cst.len))
  for k, v in cst.pairs:
    await s.writeStrl(k)
    await s.write(int32(v))
  
proc readCSymTable(s: Stream | AsyncStream): Future[CSymTable] {.multisync.} =
  result = initTable[string, int]()
  var count = await s.readInt32()
  while count > 0:
    dec count
    let key = await s.readStrl()
    let val = int(await s.readInt32())
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


proc `$`(fr: Frame): string =
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
  result.itype = InstructionType(await s.readInt8())
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
  result.ptype = PackageType(await s.readInt8())
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
  await s.write(int32(t.callback))
  await s.write(int32(t.waitingFor))
  

proc readTask*(s: Stream | AsyncStream): Future[Task] {.multisync.} =
  var t: Task
  var count: int32

  new t

  t.id = await s.readInt32()
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
  t.callback = await s.readInt32()
  t.waitingFor = await s.readInt32()

  return t
  
#when not isMainModule:
#  import scripting
#  defBuiltin "twt":
#    var ss = newStringStream()
#    ss.writeTask(task)
#
#    var oss = newStringStream(ss.data)
#    let taskCopy = oss.readTask()

