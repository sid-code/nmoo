import types, scripting, tables, strutils, sequtils
from algorithm import reversed

proc newCSymTable: CSymTable = initTable[string, int]()
proc newSymGen(prefix: string): SymGen = SymGen(counter: 0, prefix: prefix)
proc newSymGen: SymGen = newSymGen("L")
proc newCompiler: MCompiler =
  MCompiler(
    real: @[],
    subrs: @[],
    symtable: newCSymTable(),
    symgen: newSymGen())

proc codeGen*(compiler: MCompiler, data: MData)

proc compileCode*(code: string): MCompiler =
  var compiler = newCompiler()
  var parser = newParser(code)
  compiler.codeGen(parser.parseList)
  return compiler

proc genSym(symgen: SymGen): string =
  result = "$1$2" % [symgen.prefix, $symgen.counter]
  symgen.counter += 1

template ins(typ: InstructionType, op: MData): Instruction =
  Instruction(itype: typ, operand: op)

template ins(typ: InstructionType): Instruction =
  ins(typ, nilD)

proc `$`(ins: Instruction): string =
  let itypeStr = ($ins.itype)[2 .. ^1]
  if ins.operand == nilD:
    return itypeStr & "\t"
  else:
    return "$1\t$2" % [itypeStr, ins.operand.toCodeStr()]

proc `$`*(compiler: MCompiler): string =
  var slines: seq[string] = @[]
  let all = compiler.subrs & compiler.real
  for ins in all:
    var prefix = "\t"
    if ins.itype == inLABEL:
      prefix = ins.operand.toCodeStr() & ":" & prefix
    slines.add(prefix & $ins)

  slines[compiler.subrs.len] &= "\t<ENTRY>"

  return slines.join("\n")

proc compileError(msg: string) =
  raise newException(MCompileError, "Compiler error: " & msg)

proc getSymbol(symtable: CSymTable, name: string): int =
  if symtable.hasKey(name):
    return symtable[name]
  else:
    compileError("unbound symbol '$1'" % [name])

proc getSymInst(symtable: CSymTable, name: string): Instruction =
  try:
    if builtinExists(name):
      return ins(inPUSH, name.mds)
    else:
      let index = symtable.getSymbol(name)
      return ins(inGET, index.md)
  except:
    return ins(inGGET, name.mds)

var specials = initTable[string, SpecialProc]()
proc specialExists(name: string): bool =
  specials.hasKey(name)

proc checkType(value: MData, expected: MDataType) =
  if not value.isType(expected):
    compileError("expected argument of type " & $expected & " instead got " & $value.dType)

template defSpecial(name: string, body: stmt) {.immediate, dirty.} =
  specials[name] = proc (compiler: MCompiler, args: seq[MData]) =
    body


# dNil means any type is allowed
proc verifyArgs(name: string, args: seq[MData], spec: seq[MDataType]) =
  if args.len != spec.len:
    compileError("$1: expected $2 arguments but got $3" %
      [name, $spec.len, $args.len])

  for o, e in args.zip(spec).items:
    if e != dNil and not o.isType(e):
      compileError("$1: expected argument of type $2 but got $3" %
        [name, $e, $o.dtype])

proc codeGen*(compiler: MCompiler, code: seq[MData]) =
  if code.len == 0:
    compiler.real.add(ins(inCLIST, 0.md))
    return

  let first = code[0]

  if first.isType(dSym):
    let name = first.symVal
    if specialExists(name):
      let
        args = code[1 .. ^1]
        prok = compile.specials[name]
      prok(compiler, args)
    else:
      for arg in code[1 .. ^1]:
        compiler.codeGen(arg)
      compiler.real.add(ins(inPUSH, first))
      compiler.real.add(ins(inCALL, (code.len - 1).md))
  else:
    for data in code:
      compiler.codeGen(data)
    compiler.real.add(ins(inCLIST, code.len.md))

proc codeGen*(compiler: MCompiler, data: MData) =
  if data.isType(dList):
    compiler.codeGen(data.listVal)
  elif data.isType(dSym):
    try:
      compiler.real.add(compiler.symtable.getSymInst(data.symVal))
    except:
      compiler.real.add(ins(inPUSH, data))
  else:
    compiler.real.add(ins(inPUSH, data))

template defSymbol(symtable: CSymTable, name: string): int =
  let index = symtable.len
  symtable[name] = index
  index

template addLabel(compiler: MCompiler, section: expr): MData =
  let name = compiler.symgen.genSym().mds

  compiler.`section`.add(ins(inLABEL, name))

  name

proc render*(compiler: MCompiler): CpOutput =
  ## Remove all label references and replace them
  ## with numbers that refer to there they jump to
  ##
  ## Instructions that still use labels:
  ##   J0, JN0, JMP, LPUSH, TRY

  var labels = newCSymTable()
  var code = compiler.subrs & compiler.real
  let entry = compiler.subrs.len

  for idx, inst in code:
    if inst.itype == inLABEL:
      labels[inst.operand.symVal] = idx

  for idx, inst in code:
    let op = inst.operand
    if inst.itype == inJ0 or inst.itype == inJN0 or inst.itype == inJMP:
      if op.isType(dSym):
        let label = op.symVal
        let jumpLoc = labels[label]
        code[idx] = ins(inst.itype, jumpLoc.md)
    elif inst.itype == inLPUSH:
      code[idx] = ins(inPUSH, labels[op.symVal].md)
    elif inst.itype == inTRY:
      let newLabels = op.listVal.map(proc(x: MData): MData = labels[x.symVal].md).md
      code[idx] = ins(inTRY, newLabels)

  code.add(ins(inHALT))
  return (entry, code)

defSpecial "lambda":
  verifyArgs("lambda", args, @[dList, dNil])

  let bounds = args[0].listVal

  let labelName = compiler.addLabel(subrs)

  for bound in bounds.reversed():
    checkType(bound, dSym)
    let name = bound.symVal
    let index = compiler.symtable.defSymbol(name)
    compiler.subrs.add(ins(inSTO, index.md))

  let
    subrsBeforeSize = compiler.subrs.len
    realBeforeSize = compiler.real.len
  compiler.codeGen(args[1])
  let
    subrsAfterSize = compiler.subrs.len
    realAfterSize = compiler.real.len

  let
    addedSubrs = compiler.subrs[subrsBeforeSize .. subrsAfterSize - 1]
    addedReal = compiler.real[realBeforeSize .. realAfterSize - 1]
  compiler.subrs.delete(subrsBeforeSize, subrsAfterSize - 1)
  compiler.real.delete(realBeforeSize, realAfterSize - 1)
  compiler.subrs.add(addedReal)

  for bound in bounds:
    let name = bound.symVal
    compiler.symtable.del(name)
  compiler.subrs.add(ins(inRET))
  compiler.subrs.add(addedSubrs)

  compiler.real.add(ins(inLPUSH, labelName))
  compiler.real.add(ins(inMENV))
  compiler.real.add(ins(inPUSH, bounds.len.md))
  compiler.real.add(ins(inCLIST, 3.md))

defSpecial "map":
  verifyArgs("map", args, @[dNil, dNil])
  let fn = args[0]
  # fn can either be a sym or a lambda but it doesn't matter
  compiler.codeGen(fn)

  let index = compiler.symtable.defSymbol("__mapfn")
  compiler.real.add(ins(inSTO, index.md))
  compiler.codeGen(args[1])
  compiler.real.add(ins(inREV))
  compiler.real.add(ins(inCLIST, 0.md))
  let labelLocation = compiler.addLabel(real)
  let afterLocation = compiler.symgen.genSym().mds
  compiler.real.add(ins(inSWAP))
  compiler.real.add(ins(inLEN))
  compiler.real.add(ins(inJ0, afterLocation))
  compiler.real.add(ins(inPOPL))
  compiler.real.add(ins(inGET, index.md))
  compiler.real.add(ins(inCALL, 1.md))
  compiler.real.add(ins(inSWAP3))
  compiler.real.add(ins(inSWAP))
  compiler.real.add(ins(inPUSHL))
  compiler.real.add(ins(inJMP, labelLocation))
  compiler.real.add(ins(inLABEL, afterLocation))
  compiler.real.add(ins(inPOP))

defSpecial "call":
  verifyArgs("call", args, @[dNil, dNil])
  compiler.codeGen(args[1])
  compiler.codeGen(args[0])

  compiler.real.add(ins(inACALL))

defSpecial "let":
  verifyArgs("let", args, @[dList, dNil])
  let asmts = args[0].listVal
  for assignd in asmts:
    if not assignd.isType(dList):
      compileError("let: first argument must be a list of 2-size lists")
    let assign = assignd.listVal
    if not assign.len == 2:
      compileError("let: first argument must be a list of 2-size lists")

    let sym = assign[0]
    let val = assign[1]

    if not sym.isType(dSym):
      compileError("let: only symbols can be bound")

    compiler.codeGen(val)
    let symIndex = compiler.symtable.defSymbol(sym.symVal)
    compiler.real.add(ins(inSTO, symIndex.md))

  compiler.codeGen(args[1])

defSpecial "try":
  let alen = args.len
  if alen != 2 and alen != 3:
    compileError("try: 2 or 3 arguments required")

  let exceptLabel = compiler.symgen.genSym().mds
  let endLabel = compiler.symgen.genSym().mds
  compiler.real.add(ins(inTRY, @[exceptLabel].md))
  compiler.codeGen(args[0])
  compiler.real.add(ins(inJMP, endLabel))
  compiler.real.add(ins(inLABEL, exceptLabel))
  let errorIndex = compiler.symtable.defSymbol("error")
  compiler.real.add(ins(inSTO, errorIndex.md))
  compiler.codeGen(args[1])
  compiler.real.add(ins(inLABEL, endLabel))
  compiler.real.add(ins(inETRY))
  if alen == 3:
    compiler.codeGen(args[2])

defSpecial "cond":
  let endLabel = compiler.symgen.genSym().mds

  var branchLabels: seq[MData] = @[]
  var hadElseClause = false

  for arg in args:
    if not arg.isType(dList):
      compileError("cond: each argument to cond must be a list")
    let larg = arg.listVal
    if larg.len == 0 or larg.len > 2:
      compileError("cond: each argument to cond must be of length 1 or 2")

    if larg.len == 1:
      hadElseClause = true
      break

    let condLabel = compiler.symgen.genSym().mds
    branchLabels.add(condLabel)

    compiler.codeGen(larg[0])
    compiler.real.add(ins(inJN0, condLabel))

  compiler.real.add(ins(inJMP, endLabel))

  if not hadElseClause:
    compileError("cond: else clause required")

  for idx, arg in args:
    let larg = arg.listVal
    if larg.len == 1:
      compiler.real.add(ins(inLABEL, endLabel))
      compiler.codeGen(larg[0])
      break

    let condLabel = branchLabels[idx]
    compiler.real.add(ins(inLABEL, condLabel))
    compiler.codeGen(larg[1])
    compiler.real.add(ins(inJMP, endLabel))
