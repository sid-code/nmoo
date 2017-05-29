import tables
import strutils
import sequtils

import types
import scripting
import objects

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
proc newCompiler(programmer: MObject): MCompiler =
  MCompiler(
    programmer: programmer,
    real: @[],
    subrs: @[],
    symtable: newCSymTable(),
    symgen: newSymGen())

proc codeGen*(compiler: MCompiler, data: MData)

proc genSym(symgen: SymGen): string =
  result = "$1$2" % [symgen.prefix, $symgen.counter]
  symgen.counter += 1

template ins(typ: InstructionType, op: MData, position: CodePosition): Instruction =
  Instruction(itype: typ, operand: op, pos: position)

template ins(typ: InstructionType, op: MData): Instruction =
  ins(typ, op, (0, 0))

template ins(typ: InstructionType): Instruction =
  ins(typ, nilD)

# shortcut for compiler.real.add
template radd(compiler: MCompiler, inst: Instruction) =
  compiler.real.add(inst)

# shortcut for compiler.subrs.add
template sadd(compiler: MCompiler, inst: Instruction) =
  compiler.subrs.add(inst)

proc `$`*(ins: Instruction): string =
  let itypeStr = ($ins.itype)[2 .. ^1]
  if ins.operand == nilD:
    return itypeStr & "\t"
  else:
    return "$1\t$2\t$3" % [itypeStr, ins.operand.toCodeStr(), $ins.pos]

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

proc getSymInst(symtable: CSymTable, sym: MData): Instruction =
  let pos = sym.pos
  let name = sym.symVal

  try:
    if builtinExists(name):
      return ins(inPUSH, name.mds, pos)
    else:
      let index = symtable.getSymbol(name)
      return ins(inGET, index.md, pos)
  except:
    return ins(inGGET, name.mds, pos)

var specials = initTable[string, SpecialProc]()
proc specialExists(name: string): bool =
  specials.hasKey(name)

proc checkType(value: MData, expected: MDataType) =
  if not value.isType(expected):
    compileError("expected argument of type " & $expected & " instead got " & $value.dType)

template defSpecial(name: string, body: untyped) {.dirty.} =
  specials[name] = proc (compiler: MCompiler, args: seq[MData], pos: CodePosition) =
    proc emit(inst: Instruction, where = 0) =
      var inst = inst
      inst.pos = pos
      if where == 0:
        compiler.radd(inst)
      else:
        compiler.sadd(inst)
    proc emit(insts: seq[Instruction], where = 0) =
      for inst in insts: emit(inst, where)

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

proc codeGen*(compiler: MCompiler, code: seq[MData], pos: CodePosition) =
  if code.len == 0:
    compiler.radd(ins(inCLIST, 0.md, pos))
    return

  let first = code[0]

  if first.isType(dSym):
    let name = first.symVal
    if specialExists(name):
      let
        args = code[1 .. ^1]
        prok = compile.specials[name]
      prok(compiler, args, pos)
      return
    elif builtinExists(name):
      for arg in code[1 .. ^1]:
        compiler.codeGen(arg)
      compiler.radd(ins(inPUSH, first, first.pos))
      compiler.radd(ins(inCALL, (code.len - 1).md, first.pos))
      return

  for data in code:
    compiler.codeGen(data)
  compiler.radd(ins(inCLIST, code.len.md, pos))

proc codeGen*(compiler: MCompiler, data: MData) =
  if data.isType(dList):
    compiler.codeGen(data.listVal, data.pos)
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
        compiler.radd(compiler.symtable.getSymInst(data))
      except:
        compiler.radd(ins(inPUSH, data, data.pos))
  else:
    compiler.radd(ins(inPUSH, data, data.pos))

# Quoted data needs no extra processing UNLESS quasiquoted in which case we need to watch for unqotes.
proc codeGenQ(compiler: MCompiler, code: MData, quasi: bool) =
  if code.isType(dList):
    let list = code.listVal

    if quasi and list.len > 0 and list[0] == "unquote".mds:
      if list.len == 2:
        compiler.codeGen(list[1])
      else:
        compileError("unquote: too many arguments")
    else:
      for item in list:
        compiler.codeGenQ(item, quasi)
      let pos = code.pos
      compiler.radd(ins(inCLIST, list.len.md, pos))
  else:
    compiler.radd(ins(inPUSH, code))

template defSymbol(symtable: CSymTable, name: string): int =
  let index = symtable.len
  symtable[name] = index
  index

template addLabel(compiler: MCompiler, section: untyped): MData =
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
    if inst.itype in {inJ0, inJT, inJNT, inJMP, inRETJ, inMCONT}:
      if op.isType(dSym):
        let label = op.symVal
        let jumpLoc = labels[label]
        code[idx] = ins(inst.itype, jumpLoc.md, inst.pos)
    elif inst.itype == inLPUSH:
      code[idx] = ins(inPUSH, labels[op.symVal].md, inst.pos)
    elif inst.itype == inTRY:
      let newLabel = labels[op.symVal].md
      code[idx] = ins(inTRY, newLabel, inst.pos)

  code.add(ins(inHALT))
  return (entry, code)

proc compileCode*(forms: seq[MData], programmer: MObject): CpOutput =
  let compiler = newCompiler(programmer)

  for form in forms:
    compiler.codeGen(form)

  return compiler.render

proc compileCode*(code: MData, programmer: MObject): CpOutput =
  let compiler = newCompiler(programmer)
  compiler.codeGen(code)
  return compiler.render

proc compileCode*(code: string, programmer: MObject): CpOutput =
  var parser = newParser(code)
  return compileCode(parser.parseFull(), programmer)

defSpecial "quote":
  verifyArgs("quote", args, @[dNil])

  compiler.codeGenQ(args[0], false)

defSpecial "quasiquote":
  verifyArgs("quasiquote", args, @[dNil])

  compiler.codeGenQ(args[0], true)

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
  emit(ins(inRET), 1)
  emit(addedSubrs, 1)

  emit(ins(inLPUSH, labelName))
  emit(ins(inPUSH, compiler.symtable.toData()))
  emit(ins(inMENV)) # This pushes the environment id AND a
                                 # MData representation if it

  emit(ins(inGTID)) # Record the task ID in the lambda
  emit(ins(inPUSH, bounds.md))
  emit(ins(inPUSH, expression))
  emit(ins(inCLIST, 6.md))

defSpecial "map":
  verifyArgs("map", args, @[dNil, dNil])
  let fn = args[0]
  # fn can either be a sym or a lambda but it doesn't matter
  compiler.codeGen(fn)

  let index = compiler.symtable.defSymbol("__mapfn")
  emit(ins(inSTO, index.md))
  compiler.codeGen(args[1])
  emit(ins(inREV))
  emit(ins(inCLIST, 0.md))
  let labelLocation = compiler.addLabel(real)
  let afterLocation = compiler.makeSymbol()
  emit(ins(inSWAP))
  emit(ins(inLEN))
  emit(ins(inJ0, afterLocation))
  emit(ins(inPOPL))
  emit(ins(inGET, index.md))
  emit(ins(inCALL, 1.md))
  emit(ins(inSWAP3))
  emit(ins(inSWAP))
  emit(ins(inPUSHL))
  emit(ins(inJMP, labelLocation))
  emit(ins(inLABEL, afterLocation))
  emit(ins(inPOP))
  compiler.symtable.del("__mapfn")

proc genFold(compiler: MCompiler, fn, default, list: MData,
             useDefault = true, right = true, pos: CodePosition = (0, 0)) =

  proc emit(inst: Instruction) =
    var inst = inst
    inst.pos = pos
    compiler.radd(inst)

  compiler.codeGen(fn)

  let index = compiler.symtable.defSymbol("__redfn")
  emit(ins(inSTO, index.md))
  compiler.codeGen(list)                         # list

  let after = compiler.makeSymbol()
  let emptyList = compiler.makeSymbol()
  if not useDefault:
    emit(ins(inLEN))                # list len
    emit(ins(inJ0, emptyList))      # list

  if right:
    emit(ins(inREV))                # list-rev

  if useDefault:
    compiler.codeGen(default)
  else:
    emit(ins(inPOPL))               # list-rev last

  emit(ins(inSWAP))                 # last list-rev

  let loop = compiler.addLabel(real)
  emit(ins(inLEN))                  # last list-rev len
  emit(ins(inJ0, after))            # last list-rev
  emit(ins(inPOPL))                 # last1 list-rev last2
  emit(ins(inSWAP3))                # list-rev last2 last1
  emit(ins(inSWAP))                 # list-rev last1 last2
  emit(ins(inGET, index.md))        # list-rev last1 last2 fn
  emit(ins(inCALL, 2.md))           # list-rev result
  emit(ins(inSWAP))                 # result list-rev
  emit(ins(inJMP, loop))

  if not useDefault:
    emit(ins(inLABEL, emptyList))
    compiler.codeGen(default)
    emit(ins(inSWAP)) # So that the pop at the end pops off the empty list

  emit(ins(inLABEL, after))
  emit(ins(inPOP))                  # result

defSpecial "reduce-right":
  verifyArgs("reduce-right", args, @[dNil, dNil])

  compiler.genFold(args[0], nilD, args[1], useDefault = false, right = true, pos = pos)

defSpecial "reduce-left":
  verifyArgs("reduce-left", args, @[dNil, dNil])

  compiler.genFold(args[0], nilD, args[1], useDefault = false, right = false, pos = pos)

defSpecial "fold-right":
  verifyArgs("fold-right", args, @[dNil, dNil, dNil])

  compiler.genFold(args[0], args[1], args[2], useDefault = true, right = true, pos = pos)

defSpecial "fold-left":
  verifyArgs("fold-left", args, @[dNil, dNil, dNil])

  compiler.genFold(args[0], args[1], args[2], useDefault = true, right = false, pos = pos)

defSpecial "call":
  verifyArgs("call", args, @[dNil, dNil])
  compiler.codeGen(args[1])
  compiler.codeGen(args[0])

  emit(ins(inACALL))

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
    emit(ins(inSTO, symIndex.md))

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
  emit(ins(inTRY, exceptLabel))
  compiler.codeGen(args[0])
  emit(ins(inETRY))
  emit(ins(inJMP, endLabel))
  emit(ins(inLABEL, exceptLabel))
  let errorIndex = compiler.symtable.defSymbol("error")
  emit(ins(inSTO, errorIndex.md))
  compiler.codeGen(args[1])

  # Out of rescue scope, so unbind "error" symbol
  compiler.symtable.del("error")

  emit(ins(inLABEL, endLabel))
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
    emit(ins(inJT, condLabel))

  emit(ins(inJMP, elseLabel))

  if not hadElseClause:
    compileError("cond: else clause required")

  for idx, arg in args:
    let larg = arg.listVal
    if larg.len == 1:
      emit(ins(inLABEL, elseLabel))
      compiler.codeGen(larg[0])
      emit(ins(inLABEL, endLabel))
      break

    let condLabel = branchLabels[idx]
    emit(ins(inLABEL, condLabel))
    compiler.codeGen(larg[1])
    emit(ins(inJMP, endLabel))

defSpecial "or":
  if args.len == 0:
    emit(ins(inPUSH, 0.md))
    return

  let endLabel = compiler.makeSymbol()
  for i in 0..args.len-2:
    compiler.codeGen(args[i])
    emit(ins(inDUP))
    emit(ins(inJT, endLabel))
    emit(ins(inPOP))

  compiler.codeGen(args[^1])

  # none of them turned out to be true
  emit(ins(inLABEL, endLabel))

defSpecial "and":
  if args.len == 0:
    emit(ins(inPUSH, 1.md))
    return

  let endLabel = compiler.makeSymbol()
  for i in 0..args.len-2:
    compiler.codeGen(args[i])
    emit(ins(inDUP))
    emit(ins(inJNT, endLabel))
    emit(ins(inPOP))

  compiler.codeGen(args[^1])

  # none of them turned out to be false
  emit(ins(inLABEL, endLabel))

defSpecial "if":
  if args.len != 3:
    compileError("if takes 3 arguments (condition, if-true, if-false)")
  compiler.codeGen(@["cond".mds, @[args[0], args[1]].md, @[args[2]].md].md)

defSpecial "call-cc":
  verifyArgs("call-cc", args, @[dNil])
  # continuations will be of the form (cont <ID>)
  let contLabel = compiler.makeSymbol()
  emit(ins(inMCONT, contLabel))
  emit(ins(inPUSH, "cont".mds))
  emit(ins(inSWAP))
  emit(ins(inCLIST, 2.md))
  emit(ins(inCLIST, 1.md))

  compiler.codeGen(args[0])
  emit(ins(inACALL))
  emit(ins(inLABEL, contLabel))
