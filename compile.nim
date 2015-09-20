import types, scripting, tables, strutils, sequtils
from algorithm import reversed

proc newCSymTable: CSymTable = initTable[string, int]()
proc toData(st: CSymTable): MData =
  var pairs: seq[MData] = @[]
  for key, val in st:
    pairs.add(@[key.md, val.md].md)
  return pairs.md

proc toCST*(data: MData): CSymTable =
  result = newCSymTable()
  if not data.isType(dList):
    return

  let list = data.listVal
  for pair in list:
    if not pair.isType(dList): continue

    let pairdata = pair.listVal
    let keyd = pairdata[0]
    let vald = pairdata[1]
    if not keyd.isType(dStr): continue
    if not vald.isType(dInt): continue
    let key = keyd.strVal
    let val = vald.intVal
    result[key] = val


proc newSymGen(prefix: string): SymGen = SymGen(counter: 0, prefix: prefix)
proc newSymGen: SymGen = newSymGen("L")
proc newCompiler: MCompiler =
  MCompiler(
    real: @[],
    subrs: @[],
    symtable: newCSymTable(),
    symgen: newSymGen())

proc codeGen*(compiler: MCompiler, data: MData)

proc genSym(symgen: SymGen): string =
  result = "$1$2" % [symgen.prefix, $symgen.counter]
  symgen.counter += 1

template ins(typ: InstructionType, op: MData): Instruction =
  Instruction(itype: typ, operand: op)

template ins(typ: InstructionType): Instruction =
  ins(typ, nilD)

proc `$`*(ins: Instruction): string =
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

proc makeSymbol(compiler: MCompiler): MData =
  compiler.symgen.genSym().mds

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
      return
    elif builtinExists(name):
      for arg in code[1 .. ^1]:
        compiler.codeGen(arg)
      compiler.real.add(ins(inPUSH, first))
      compiler.real.add(ins(inCALL, (code.len - 1).md))
      return

  for data in code:
    compiler.codeGen(data)
  compiler.real.add(ins(inCLIST, code.len.md))

proc codeGen*(compiler: MCompiler, data: MData) =
  if data.isType(dList):
    compiler.codeGen(data.listVal)
  elif data.isType(dSym):
    let name = data.symVal
    if name[0] == '$':
      let pos = data.pos
      var sym = "getprop".mds
      sym.pos = pos
      var expanded = @[sym, 0.ObjID.md, name[1..^1].md].md
      expanded.pos = pos

      compiler.codeGen(expanded)
    else:
      try:
        compiler.real.add(compiler.symtable.getSymInst(data.symVal))
      except:
        compiler.real.add(ins(inPUSH, data))
  else:
    compiler.real.add(ins(inPUSH, data))

# Quoted data needs no extra processing
proc codeGenQ*(compiler: MCompiler, code: MData) =
  if code.isType(dList):
    let list = code.listVal
    for item in list:
      compiler.codeGenQ(item)
    compiler.real.add(ins(inCLIST, list.len.md))
  else:
    compiler.real.add(ins(inPUSH, code))

template defSymbol(symtable: CSymTable, name: string): int =
  let index = symtable.len
  symtable[name] = index
  index

template addLabel(compiler: MCompiler, section: expr): MData =
  let name = compiler.makeSymbol()

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
    if inst.itype in {inJ0, inJN0, inJMP, inRETJ}:
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

proc compileCode*(code: MData): CpOutput =
  let compiler = newCompiler()
  compiler.codeGen(code)
  return compiler.render

proc compileCode*(code: string): CpOutput =
  var parser = newParser(code)
  return compileCode(parser.parseAtom())

defSpecial "quote":
  verifyArgs("quote", args, @[dNil])

  compiler.codeGenQ(args[0])

defSpecial "lambda":
  verifyArgs("lambda", args, @[dList, dNil])

  let bounds = args[0].listVal
  let expression = args[1]

  let labelName = compiler.addLabel(subrs)

  for bound in bounds.reversed():
    checkType(bound, dSym)
    let name = bound.symVal
    let index = compiler.symtable.defSymbol(name)
    compiler.subrs.add(ins(inSTO, index.md))

  let
    subrsBeforeSize = compiler.subrs.len
    realBeforeSize = compiler.real.len
  compiler.codeGen(expression)
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
  compiler.real.add(ins(inPUSH, compiler.symtable.toData()))
  compiler.real.add(ins(inMENV)) # This pushes the environment id AND a
                                 # MData representation if it

  compiler.real.add(ins(inGTID)) # Record the task ID in the lambda
  compiler.real.add(ins(inPUSH, bounds.md))
  compiler.real.add(ins(inPUSH, expression))
  compiler.real.add(ins(inCLIST, 6.md))

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
  let afterLocation = compiler.makeSymbol()
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

proc genFold(compiler: MCompiler, fn, default, list: MData,
             useDefault = true, right = true) =

  compiler.codeGen(fn)

  let index = compiler.symtable.defSymbol("__redfn")
  compiler.real.add(ins(inSTO, index.md))
  compiler.codeGen(list)                         # list

  let after = compiler.makeSymbol()
  let emptyList = compiler.makeSymbol()
  if not useDefault:
    compiler.real.add(ins(inLEN))                # list len
    compiler.real.add(ins(inJ0, emptyList))      # list

  if right:
    compiler.real.add(ins(inREV))                # list-rev

  if useDefault:
    compiler.codeGen(default)
  else:
    compiler.real.add(ins(inPOPL))               # list-rev last

  compiler.real.add(ins(inSWAP))                 # last list-rev

  let loop = compiler.addLabel(real)
  compiler.real.add(ins(inLEN))                  # last list-rev len
  compiler.real.add(ins(inJ0, after))            # last list-rev
  compiler.real.add(ins(inPOPL))                 # last1 list-rev last2
  compiler.real.add(ins(inSWAP3))                # list-rev last2 last1
  compiler.real.add(ins(inSWAP))                 # list-rev last1 last2
  compiler.real.add(ins(inGET, index.md))        # list-rev last1 last2 fn
  compiler.real.add(ins(inCALL, 2.md))           # list-rev result
  compiler.real.add(ins(inSWAP))                 # result list-rev
  compiler.real.add(ins(inJMP, loop))

  if not useDefault:
    compiler.real.add(ins(inLABEL, emptyList))
    compiler.codeGen(default)
    compiler.real.add(ins(inSWAP)) # So that the pop at the end pops off the empty list

  compiler.real.add(ins(inLABEL, after))
  compiler.real.add(ins(inPOP))                  # result

defSpecial "reduce-right":
  verifyArgs("reduce-right", args, @[dNil, dNil, dNil])

  compiler.genFold(args[0], args[1], args[2], useDefault = false, right = true)

defSpecial "reduce-left":
  verifyArgs("reduce-left", args, @[dNil, dNil, dNil])

  compiler.genFold(args[0], args[1], args[2], useDefault = false, right = false)

defSpecial "fold-right":
  verifyArgs("fold-right", args, @[dNil, dNil, dNil])

  compiler.genFold(args[0], args[1], args[2], useDefault = true, right = true)

defSpecial "fold-left":
  verifyArgs("fold-left", args, @[dNil, dNil, dNil])

  compiler.genFold(args[0], args[1], args[2], useDefault = true, right = false)

defSpecial "call":
  verifyArgs("call", args, @[dNil, dNil])
  compiler.codeGen(args[1])
  compiler.codeGen(args[0])

  compiler.real.add(ins(inACALL))

defSpecial "let":
  verifyArgs("let", args, @[dList, dNil])

  # Keep track of what's bound so we can unbind them later
  var binds: seq[string]
  newSeq(binds, 0)

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
    binds.add(sym.symVal)
    compiler.real.add(ins(inSTO, symIndex.md))

  compiler.codeGen(args[1])

  # We're outside scope so unbind the symbols
  for bound in binds:
    compiler.symtable.del(bound)

defSpecial "try":
  let alen = args.len
  if alen != 2 and alen != 3:
    compileError("try: 2 or 3 arguments required")

  let exceptLabel = compiler.makeSymbol()
  let endLabel = compiler.makeSymbol()
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
  let endLabel = compiler.makeSymbol()
  let elseLabel = compiler.makeSymbol()

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

    let condLabel = compiler.makeSymbol()
    branchLabels.add(condLabel)

    compiler.codeGen(larg[0])
    compiler.real.add(ins(inJN0, condLabel))

  compiler.real.add(ins(inJMP, elseLabel))

  if not hadElseClause:
    compileError("cond: else clause required")

  for idx, arg in args:
    let larg = arg.listVal
    if larg.len == 1:
      compiler.real.add(ins(inLABEL, elseLabel))
      compiler.codeGen(larg[0])
      compiler.real.add(ins(inLABEL, endLabel))
      break

    let condLabel = branchLabels[idx]
    compiler.real.add(ins(inLABEL, condLabel))
    compiler.codeGen(larg[1])
    compiler.real.add(ins(inJMP, endLabel))

defSpecial "if":
  if args.len != 3:
    compileError("if takes 3 arguments (condition, if-true, if-false)")
  compiler.codeGen(@["cond".mds, @[args[0], args[1]].md, @[args[2]].md].md)
