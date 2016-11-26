import streams
import times
import tables

import types

# Write a string by writing the length first then the string
proc writeStrl(s: Stream, str: string) =
  s.write(int32(str.len))
  s.write(str)

# Reads an int32 then reads that many characters into a string
proc readStrl(s: Stream): string =
  let slen = s.readInt32()
  return s.readStr(slen)

proc writeMData*(s: Stream, d: MData) =
  # The data type is encoded as an unsigned 8 bit integer. The 7 least
  # significant bits are used to encode the type, and the most significant
  # bit is flipped when the MData object has a position. If so, this position
  # immediately follows as two signed 32 bit integers.
  var dtype7bit: uint8 = uint8(d.dtype)

  let needToWritePos = d.pos != (0, 0)
  if needToWritePos:
    dtype7bit = dtype7bit or uint8(1 shl 7) # sets the sign bit to 1

  s.write(dtype7bit)

  if needToWritePos:
    s.write(int32(d.pos.line))
    s.write(int32(d.pos.col))

  case d.dtype:
    of dInt:
      s.write(int64(d.intVal))
    of dFloat:
      s.write(float64(d.floatVal))
    of dStr:
      let str = d.strVal
      s.writeStrl(str)
    of dSym:
      let sym = d.symVal
      s.writeStrl(sym)
    of dErr:
      let err = d.errVal
      let msg = d.errMsg
      s.write(int8(err))
      s.writeStrl(msg)
    of dList:
      let list = d.listVal
      s.write(int32(list.len))
      for el in list:
        s.writeMData(el)
    of dObj:
      s.write(int32(d.objVal))
    of dNil:
      discard

proc readMData*(s: Stream): MData =
  var dtype7bit = uint8(s.readInt8())
  let firstBit = uint8(1) == dtype7bit shr 7
  if firstBit:
    dtype7bit = dtype7bit and (1 shl 7 - 1)
    let line = int(s.readInt32())
    let col = int(s.readInt32())
    result.pos = (line, col)
  else:
    result.pos = (0, 0)

  result.dtype = MDataType(dtype7bit)

  case result.dtype:
    of dInt:
      result.intVal = int(s.readInt64())
    of dFloat:
      result.floatVal = float(s.readFloat64())
    of dStr:
      result.strVal = s.readStrl()
    of dSym:
      result.symVal = s.readStrl()
    of dErr:
      result.errVal = MError(s.readInt8())
      result.errMsg = s.readStrl()
    of dList:
      var size = s.readInt32()
      newSeq(result.listVal, 0)
      while size > 0:
        dec size
        result.listVal.add(s.readMData())
    of dObj:
      result.objVal = ObjID(int(s.readInt32()))
    of dNil:
      discard

proc writeVSymTable(s: Stream, vst: VSymTable) =
  s.write(int32(vst.len))
  for k, v in vst.pairs:
    s.write(int32(k))
    s.writeMData(v)

proc readVSymTable(s: Stream): VSymTable =
  result = initTable[int, MData]()
  var count = s.readInt32()
  while count > 0:
    dec count
    let key = int(s.readInt32())
    let val = s.readMData()
    result[key] = val

proc writeCSymTable(s: Stream, cst: CSymTable) =
  s.write(int32(cst.len))
  for k, v in cst.pairs:
    s.writeStrl(k)
    s.write(int32(v))
  
proc readCSymTable(s: Stream): CSymTable =
  result = initTable[string, int]()
  var count = s.readInt32()
  while count > 0:
    dec count
    let key = s.readStrl()
    let val = int(s.readInt32())
    result[key] = val

proc writeSymbolTable(s: Stream, st: SymbolTable) =
  s.write(int32(st.len))
  for k, v in st.pairs:
    s.writeStrl(k)
    s.writeMData(v)

proc readSymbolTable(s: Stream): SymbolTable =
  result = newSymbolTable()

  var count = s.readInt32()
  while count > 0:
    dec count
    let key = s.readStrl()
    let val = s.readMData()
    result[key] = val


proc `$`(fr: Frame): string =
  $fr.symtable & " " & $fr.tries

proc writeFrame(s: Stream, fr: Frame) =
  s.writeVSymTable(fr.symtable)
  s.write(int32(fr.calledFrom))

  s.write(int32(fr.tries.len))
  for t in fr.tries:
    s.write(int32(t))

proc readFrame(s: Stream): Frame =
  new result
  result.symtable = s.readVSymTable()
  result.calledFrom = s.readInt32()

  var count = s.readInt32()
  newSeq(result.tries, 0)
  while count > 0:
    dec count
    result.tries.add(int(s.readInt32()))

proc writeContinuation(s: Stream, cont: Continuation) =
  s.write(int32(cont.pc))

  s.write(int32(cont.stack.len))
  for el in cont.stack:
    s.writeMData(el)

  s.writeSymbolTable(cont.globals)

  s.write(int32(cont.frames.len))
  for fr in cont.frames:
    s.writeFrame(fr)

proc readContinuation(s: Stream): Continuation =
  result.pc = int(s.readInt32())

  newSeq(result.stack, 0)
  var count = s.readInt32()
  while count > 0:
    dec count
    result.stack.add(s.readMData())

  result.globals = s.readSymbolTable()

  newSeq(result.frames, 0)
  count = s.readInt32()
  while count > 0:
    dec count
    result.frames.add(s.readFrame())

proc writeInstruction(s: Stream, inst: Instruction) =
  s.write(int8(inst.itype))
  s.writeMData(inst.operand)
  s.write(int32(inst.pos.line))
  s.write(int32(inst.pos.col))

proc readInstruction(s: Stream): Instruction =
  result.itype = InstructionType(s.readInt8())
  result.operand = s.readMData()
  result.pos.line = s.readInt32()
  result.pos.col = s.readInt32()

proc writePackage(s: Stream, p: Package) =
  s.write(int8(p.ptype))
  case p.ptype:
    of ptData:
      s.writeMData(p.val)
    of ptCall, ptInput:
      s.write(int8(p.phase))

proc readPackage(s: Stream): Package =
  result.ptype = PackageType(s.readInt8())
  case result.ptype:
    of ptData:
      result.val = s.readMData()
    of ptCall, ptInput:
      result.phase = s.readInt8()

proc writeTask*(s: Stream, t: Task) =
  s.write(int32(t.id))
  s.writeStrl(t.name)
  s.write(int32(t.startTime))

  s.writeMData(t.stack.md)
  
  s.writeSymbolTable(t.globals)

  s.write(int32(t.code.len))
  for inst in t.code:
    s.writeInstruction(inst)

  s.write(int32(t.pc))

  s.write(int32(t.frames.len))
  echo t.frames
  for fr in t.frames:
    s.writeFrame(fr)

  s.write(int32(t.continuations.len))
  for cont in t.continuations:
    s.writeContinuation(cont)

  s.write(int8(t.status))
  s.write(int32(t.suspendedUntil))
  s.write(int32(t.tickCount))
  s.write(int32(t.tickQuota))

  s.write(int8(t.hasCallPackage))
  s.writePackage(t.callPackage)
  s.writeMData(t.builtinToCall)
  s.writeMData(t.builtinArgs.md)

  s.write(int8(t.taskType))
  s.write(int32(t.callback))
  s.write(int32(t.waitingFor))
  

proc readTask*(s: Stream): Task =
  var t: Task
  var count: int32

  new t

  t.id = s.readInt32()
  t.name = s.readStrl()
  t.startTime = Time(s.readInt32())
  echo "READING TASK " & t.name

  let stackd = s.readMData()
  t.stack = stackd.listVal

  t.globals = s.readSymbolTable()
  
  newSeq(t.code, 0)
  count = s.readInt32()
  while count > 0:
    dec count
    let inst = s.readInstruction()
    t.code.add(inst)

  t.pc = s.readInt32()

  count = s.readInt32()
  newSeq(t.frames, 0)
  while count > 0:
    dec count
    let fr = s.readFrame()

    t.frames.add(fr)
  echo t.frames

  count = s.readInt32()
  newSeq(t.continuations, 0)
  while count > 0:
    dec count
    t.continuations.add(s.readContinuation())


  t.status = TaskStatus(s.readInt8())
  t.suspendedUntil = Time(s.readInt32())
  t.tickCount = s.readInt32()
  t.tickQuota = s.readInt32()

  t.hasCallPackage = s.readInt8() == 1
  t.callPackage = s.readPackage()
  t.builtinToCall = s.readMData()
  let builtinArgsd = s.readMData()
  t.builtinArgs = builtinArgsd.listVal

  t.taskType = TaskType(s.readInt8())
  t.callback = s.readInt32()
  t.waitingFor = s.readInt32()

  return t
  
when not isMainModule:
  import scripting
  defBuiltin "twt":
    var ss = newStringStream()
    ss.writeTask(task)

    var oss = newStringStream(ss.data)
    let taskCopy = oss.readTask()


when isMainModule:
  # Test each of the components to make sure they work

  var ss, oss: StringStream

  var data = @[1.md].md
  data.listVal[0].pos = (10, 10)
  data.pos = (30, 30)

  ss = newStringStream()
  ss.writeMData(data)
  oss = newStringStream(ss.data)
  let dataCopy = oss.readMData()
  assert data == dataCopy

  var vst: VSymTable = initTable[int, MData]()
  vst[0] = data
  vst[1] = 10.md

  ss = newStringStream()
  ss.writeVSymTable(vst)
  oss = newStringStream(ss.data)
  let vstCopy = oss.readVSymTable()
  assert vstCopy[0] == data
  assert vstCopy[1] == 10.md

  var instruction = Instruction(itype: inPUSH, operand: 10.md)
  ss = newStringStream()
  ss.writeInstruction(instruction)
  oss = newStringStream(ss.data)
  let instructionCopy = oss.readInstruction()
  assert instruction == instructionCopy

  # TODO: FINISH WRITING THESE

  echo "tests passed."



