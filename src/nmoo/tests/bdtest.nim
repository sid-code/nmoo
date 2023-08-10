include ../bytedump

# Test each of the components to make sure they work

suite "bytedump tests":
  setup:
    var ss, oss: StringStream
    var data, dataCopy: MData

  test "MData dumps correctly":
    data = @[1.md].md
    data.listVal[0].pos = (10, 10)
    data.pos = (30, 30)
    ss = newStringStream()
    ss.writeMData(data)
    oss = newStringStream(ss.data)
    dataCopy = oss.readMData()
    check data == dataCopy

  test "MData error with stack trace dumps correctly":
    data = E_ARGS.md("Invalid arguments")
    data.trace.add( ("line 1", (1, 1)) )
    data.trace.add( ("line 2", (2, 2)) )

    ss = newStringStream()
    ss.writeMData(data)
    oss = newStringStream(ss.data)
    dataCopy = oss.readMData()
    check data == dataCopy

  test "VSymTable dumps correctly":
    var vst: VSymTable = newTable[int, MData]()
    vst[0] = data
    vst[1] = 10.md

    ss = newStringStream()
    ss.writeVSymTable(vst)
    oss = newStringStream(ss.data)
    let vstCopy = oss.readVSymTable()
    check vstCopy[0] == data
    check vstCopy[1] == 10.md

  test "Instruction dumps correctly":

    var instruction = Instruction(itype: inPUSH, operand: 10.md)
    ss = newStringStream()
    ss.writeInstruction(instruction)
    oss = newStringStream(ss.data)
    let instructionCopy = oss.readInstruction()
    check instruction == instructionCopy

# TODO: FINISH WRITING THESE
