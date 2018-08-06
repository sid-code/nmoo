import tables
import options
import strutils
import sequtils

import types

const MaxMacroDepth = 100 # TODO: Make this world-configurable??
const compilerDefaultOptions: set[MCompilerOptions] = {}

proc codeGen*(compiler: MCompiler, data: MData): MData
proc render*(compiler: MCompiler): CpOutput
proc compileCode*(code: MData, programmer: MObject,
                  options = compilerDefaultOptions,
                  syntaxTransformers: TableRef[string, SyntaxTransformer] = nil): CpOutput
proc toCST*(data: MData): CSymTable

import scripting
import objects

import tasks

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
proc newCompiler(programmer: MObject, options: set[MCompilerOptions]): MCompiler =
  MCompiler(
    programmer: programmer,
    real: @[],
    subrs: @[],
    options: options,
    symtable: newCSymTable(),
    symgen: newSymGen(),
    depth: 0,
    syntaxTransformers: newTable[string, SyntaxTransformer]())


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

template compileError(msg: string) =
  var error = E_COMPILE.md(msg)
  return error

template compileError(msg: string, pos: CodePosition) =
  var error = E_COMPILE.md(msg)
  error.trace.add( ("compilation", pos) )
  return error

template compileError(errord: MData) =
  return errord

template propogateError(error: MData) =
  let errorV = error
  if errorV != E_NONE.md:
    return errorV

template propogateError(error: MData, traceLine: string, pos: CodePosition) =
  var errorV = error
  if errorV != E_NONE.md:
    errorV.trace.add( (traceLine, pos) )
    return errorV

proc getSymbol(symtable: CSymTable, name: string): MData =
  if symtable.hasKey(name):
    return symtable[name].md
  else:
    compileError("unbound symbol '$1'" % [name])

proc getSymInst(symtable: CSymTable, sym: MData): Instruction =
  let pos = sym.pos
  let name = sym.symVal

  if builtinExists(name):
    return ins(inPUSH, name.mds, pos)
  else:
    let index = symtable.getSymbol(name)
    if index.isType(dErr):
      return ins(inGGET, name.mds, pos)
    else:
      return ins(inGET, index, pos)


var specials = initTable[string, SpecialProc]()
proc specialExists(name: string): bool =
  specials.hasKey(name)

proc macroExists(compiler: MCompiler, name: string): bool =
  compiler.syntaxTransformers.hasKey(name)


proc staticEval(compiler: MCompiler, code: MData, name = "compile-time task"):
                  tuple[compilationError: MData, tr: TaskResult] =
  let programmer = compiler.programmer
  let world = programmer.getWorld()

  let ocompiler = newCompiler(programmer, compiler.options)
  ocompiler.syntaxTransformers = compiler.syntaxTransformers
  let compilationError = ocompiler.codeGen(code)
  if compilationError != E_NONE.md:
    result.compilationError = compilationError
    return

  let compiled = ocompiler.render()
  let symtable = newSymbolTable()

  let staticTask = world.addTask(
    name = name,
    self = programmer,
    player = programmer,
    caller = programmer,
    owner = programmer,
    symtable = symtable,
    code = compiled)

  return (E_NONE.md, staticTask.run())

proc callTransformer(compiler: MCompiler, name: string, code: MData): MData =
  let transformer = compiler.syntaxTransformers[name]
  let callCode = @["call".mds, transformer.code, @[@["quote".mds, code].md].md].md
  var (cerr, tr) = compiler.staticEval(callCode)
  propogateError(cerr, "during compilation of macro code", code.pos)

  case tr.typ:
    of trFinish:
      return tr.res
    of trSuspend:
      compileError("macro " & name & " unexpectedly suspended", code.pos)
    of trError:
      compileError(tr.err)
    of trTooLong:
      compileError("macro " & name & "  took too long", code.pos)

template defSpecial(name: string, body: untyped) {.dirty.} =
  specials[name] = proc (compiler: MCompiler, args: seq[MData], pos: CodePosition): MData =
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
    return E_NONE.md

# dNil means any type is allowed
template verifyArgs(name: string, args: seq[MData], spec: seq[MDataType], varargs = false) =
  if varargs:
    if args.len < spec.len - 1:
      compileError("$1: expected at least $2 arguments but got $3" %
                   [$name, $(spec.len - 1), $args.len])
  else:
    if args.len != spec.len:
      compileError("$1: expected $2 arguments but got $3" % [name, $spec.len, $args.len])

  for o, e in args.zip(spec).items:
    if e != dNil and not o.isType(e):
      compileError("$1: expected argument of type $2 but got $3" %
        [name, $e, $o.dtype])

proc codeGen*(compiler: MCompiler, code: seq[MData], pos: CodePosition): MData =
  if code.len == 0:
    compiler.radd(ins(inCLIST, 0.md, pos))
    return E_NONE.md

  let first = code[0]

  if first.isType(dSym):
    let name = first.symVal
    if compiler.macroExists(name):
      let transformedCode = compiler.callTransformer(name, code.md)

      if compiler.depth >= MaxMacroDepth:
        return E_MAXREC.md("maximum macro recursion depth exceeded")

      compiler.depth += 1
      var error = compiler.codeGen(transformedCode)
      compiler.depth -= 1

      if error != E_NONE.md:
        error.trace.add( ("macro call from", pos) )
        return error

      return E_NONE.md
    elif specialExists(name):
      let
        args = code[1 .. ^1]
        prok = compile.specials[name]

      propogateError(prok(compiler, args, pos))
      return E_NONE.md
    elif builtinExists(name):
      for arg in code[1 .. ^1]:
        propogateError(compiler.codeGen(arg))

      compiler.radd(ins(inPUSH, first, first.pos))
      compiler.radd(ins(inCALL, (code.len - 1).md, first.pos))
      return E_NONE.md
    else: # just spit out an ACALL and hope nothing blows up
      let numArgs = code.len - 1
      compiler.radd(ins(inPUSH, first, first.pos))
      for arg in code[1 .. ^1]:
        propogateError(compiler.codeGen(arg))

      compiler.radd(ins(inCLIST, numArgs.md, first.pos))
      propogateError(compiler.codeGen(first))
      compiler.radd(ins(inACALL, numArgs.md, first.pos))
      return E_NONE.md

  else:
    for data in code:
      propogateError(compiler.codeGen(data))

    compiler.radd(ins(inCLIST, code.len.md, pos))
    return E_NONE.md

proc codeGen*(compiler: MCompiler, data: MData): MData =
  if data.isType(dList):
    propogateError(compiler.codeGen(data.listVal, data.pos))
  elif data.isType(dSym):
    let name = data.symVal
    if name[0] == '$':
      let pos = data.pos
      var sym = "getprop".mds
      sym.pos = pos
      var expanded = @[sym, 0.ObjID.md, name[1..^1].md].md
      expanded.pos = pos

      return compiler.codeGen(expanded)
    else:
      try:
        compiler.radd(compiler.symtable.getSymInst(data))
      except:
        compiler.radd(ins(inPUSH, data, data.pos))
  else:
    compiler.radd(ins(inPUSH, data, data.pos))

  return E_NONE.md

# Quoted data needs no extra processing UNLESS quasiquoted in which case we need to watch for unqotes.
proc codeGenQ(compiler: MCompiler, code: MData, quasi: bool): MData =
  if code.isType(dList):
    let list = code.listVal

    if quasi and list.len > 0 and list[0] == "unquote".mds:
      if list.len == 2:
        propogateError(compiler.codeGen(list[1]))
      else:
        compileError("unquote: too many arguments", code.pos)
    else:
      for item in list:
        propogateError(compiler.codeGenQ(item, quasi))
      let pos = code.pos
      compiler.radd(ins(inCLIST, list.len.md, pos))
  else:
    compiler.radd(ins(inPUSH, code))

  return E_NONE.md

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
  return (entry, code, E_NONE.md)

proc compileCode*(forms: seq[MData], programmer: MObject, options = compilerDefaultOptions): CpOutput =
  let compiler = newCompiler(programmer, options)

  for form in forms:
    let error = compiler.codeGen(form)
    if error != E_NONE.md:
      return (0, nil, error)

  return compiler.render

proc compileCode*(code: MData, programmer: MObject,
                  options = compilerDefaultOptions,
                  syntaxTransformers: TableRef[string, SyntaxTransformer] = nil): CpOutput =
  let compiler = newCompiler(programmer, options)
  if not isNil(syntaxTransformers):
    compiler.syntaxTransformers = syntaxTransformers

  let error = compiler.codeGen(code)
  if error != E_NONE.md:
    return (0, nil, error)

  return compiler.render

proc compileCode*(code: string, programmer: MObject, options = compilerDefaultOptions): CpOutput =
  var parser = newParser(code)
  return compileCode(parser.parseFull(), programmer, options)

defSpecial "quote":
  verifyArgs("quote", args, @[dNil])

  propogateError(compiler.codeGenQ(args[0], false))

defSpecial "quasiquote":
  verifyArgs("quasiquote", args, @[dNil])

  propogateError(compiler.codeGenQ(args[0], true))

defSpecial "lambda":
  verifyArgs("lambda", args, @[dList, dNil])

  let bounds = args[0].listVal
  let expression = args[1]

  let labelName = compiler.addLabel(subrs)

  for bound in bounds.reversed():
    if not bound.isType(dSym):
      compileError("lambda variables can only be symbols", bound.pos)
    let name = bound.symVal
    let index = compiler.symtable.defSymbol(name)
    compiler.subrs.add(ins(inSTO, index.md))

  let
    subrsBeforeSize = compiler.subrs.len
    realBeforeSize = compiler.real.len

  propogateError(compiler.codeGen(expression))

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
  propogateError(compiler.codeGen(fn))

  let index = compiler.symtable.defSymbol("__mapfn")
  emit(ins(inSTO, index.md))
  propogateError(compiler.codeGen(args[1]))
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

template genFold(compiler: MCompiler, fn, default, list: MData,
                 useDefault = true, right = true, pos: CodePosition = (0, 0)) =

  proc emitx(inst: Instruction) =
    var inst = inst
    inst.pos = pos
    compiler.radd(inst)

  propogateError(compiler.codeGen(fn))

  let index = compiler.symtable.defSymbol("__redfn")
  emitx(ins(inSTO, index.md))
  propogateError(compiler.codeGen(list))  # list

  let after = compiler.makeSymbol()
  let emptyList = compiler.makeSymbol()
  if not useDefault:
    emitx(ins(inLEN))                # list len
    emitx(ins(inJ0, emptyList))      # list

  if right:
    emitx(ins(inREV))                # list-rev

  if useDefault:
    propogateError(compiler.codeGen(default))
  else:
    emitx(ins(inPOPL))               # list-rev last

  emitx(ins(inSWAP))                 # last list-rev

  let loop = compiler.addLabel(real)
  emitx(ins(inLEN))                  # last list-rev len
  emitx(ins(inJ0, after))            # last list-rev
  emitx(ins(inPOPL))                 # last1 list-rev last2
  emitx(ins(inSWAP3))                # list-rev last2 last1
  emitx(ins(inSWAP))                 # list-rev last1 last2
  emitx(ins(inGET, index.md))        # list-rev last1 last2 fn
  emitx(ins(inCALL, 2.md))           # list-rev result
  emitx(ins(inSWAP))                 # result list-rev
  emitx(ins(inJMP, loop))

  if not useDefault:
    emitx(ins(inLABEL, emptyList))
    propogateError(compiler.codeGen(default))
    emitx(ins(inSWAP)) # So that the pop at the end pops off the empty list

  emitx(ins(inLABEL, after))
  emitx(ins(inPOP))                  # result

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
  propogateError(compiler.codeGen(args[1]))
  propogateError(compiler.codeGen(args[0]))

  emit(ins(inACALL))

defSpecial "static-eval":
  if args.len == 0:
    compileError("static-eval: requires at least one argument", pos)

  for arg in args:
    var (cerr, tr) = compiler.staticEval(arg)
    propogateError(cerr, "during compile-time compilation(!)", arg.pos)
    case tr.typ:
      of trFinish:
        propogateError(compiler.codeGen(tr.res))
      of trSuspend:
        compileError("compile-time evaluation unexpectedly suspended", pos)
      of trError:
        compileError("compile-time evaluation had an error", pos)
      of trTooLong:
        compileError("compile-time evaluation took too long", pos)
    

defSpecial "define":
  verifyArgs("define", args, @[dSym, dNil])

  let symbol = args[0]
  let value = args[1]
  propogateError(compiler.codeGen(value))
  emit(ins(inDUP, symbol))
  emit(ins(inGSTO, symbol))

defSpecial "let":
  verifyArgs("let", args, @[dList, dNil], varargs = true)

  # Keep track of what's bound so we can unbind them later
  var binds: seq[string]
  newSeq(binds, 0)

  let asmts = args[0].listVal
  for assignd in asmts:
    if not assignd.isType(dList):
      compileError("let: first argument must be a list of 2-size lists", pos)
    let assign = assignd.listVal
    if not assign.len == 2:
      compileError("let: first argument must be a list of 2-size lists", pos)

    let sym = assign[0]
    let val = assign[1]

    if not sym.isType(dSym):
      compileError("let: only symbols can be bound", pos)

    propogateError(compiler.codeGen(val))
    let symIndex = compiler.symtable.defSymbol(sym.symVal)
    binds.add(sym.symVal)
    emit(ins(inSTO, symIndex.md))

  for i in 1..args.len-1:
    if i > 1: emit(ins(inPOP))
    propogateError(compiler.codeGen(args[i]))

  # We're outside scope so unbind the symbols
  for bound in binds:
    compiler.symtable.del(bound)

defSpecial "define-syntax":
  verifyArgs("define-syntax", args, @[dSym, dNil])

  let name = args[0].symVal
  if compiler.macroExists(name):
    compileError("define-syntax: macro " & name & " already exists.", pos)

  compiler.syntaxTransformers[name] = SyntaxTransformer(code: args[1])
  emit(ins(inPUSH, nilD))

defSpecial "try":
  let alen = args.len
  if alen != 2 and alen != 3:
    compileError("try: 2 or 3 arguments required", pos)

  let exceptLabel = compiler.makeSymbol()
  let endLabel = compiler.makeSymbol()
  emit(ins(inTRY, exceptLabel))
  propogateError(compiler.codeGen(args[0]))
  emit(ins(inETRY))
  emit(ins(inJMP, endLabel))
  emit(ins(inLABEL, exceptLabel))
  let errorIndex = compiler.symtable.defSymbol("error")
  emit(ins(inSTO, errorIndex.md))
  propogateError(compiler.codeGen(args[1]))

  # Out of rescue scope, so unbind "error" symbol
  compiler.symtable.del("error")

  emit(ins(inLABEL, endLabel))
  if alen == 3:
    propogateError(compiler.codeGen(args[2]))

defSpecial "cond":
  let endLabel = compiler.makeSymbol()
  let elseLabel = compiler.makeSymbol()

  var branchLabels: seq[MData] = @[]
  var hadElseClause = false

  for arg in args:
    if not arg.isType(dList):
      compileError("cond: each argument to cond must be a list", pos)
    let larg = arg.listVal
    if larg.len == 0 or larg.len > 2:
      compileError("cond: each argument to cond must be of length 1 or 2", pos)

    if larg.len == 1:
      hadElseClause = true
      break

    let condLabel = compiler.makeSymbol()
    branchLabels.add(condLabel)

    propogateError(compiler.codeGen(larg[0]))
    emit(ins(inJT, condLabel))

  emit(ins(inJMP, elseLabel))

  if not hadElseClause:
    compileError("cond: else clause required", pos)

  for idx, arg in args:
    let larg = arg.listVal
    if larg.len == 1:
      emit(ins(inLABEL, elseLabel))
      propogateError(compiler.codeGen(larg[0]))
      emit(ins(inLABEL, endLabel))
      break

    let condLabel = branchLabels[idx]
    emit(ins(inLABEL, condLabel))
    propogateError(compiler.codeGen(larg[1]))
    emit(ins(inJMP, endLabel))

defSpecial "or":
  if args.len == 0:
    emit(ins(inPUSH, 0.md))
    return E_NONE.md

  let endLabel = compiler.makeSymbol()
  for i in 0..args.len-2:
    propogateError(compiler.codeGen(args[i]))
    emit(ins(inDUP))
    emit(ins(inJT, endLabel))
    emit(ins(inPOP))

  propogateError(compiler.codeGen(args[^1]))

  # none of them turned out to be true
  emit(ins(inLABEL, endLabel))

defSpecial "and":
  if args.len == 0:
    emit(ins(inPUSH, 1.md))
    return E_NONE.md

  let endLabel = compiler.makeSymbol()
  for i in 0..args.len-2:
    propogateError(compiler.codeGen(args[i]))
    emit(ins(inDUP))
    emit(ins(inJNT, endLabel))
    emit(ins(inPOP))

  propogateError(compiler.codeGen(args[^1]))

  # none of them turned out to be false
  emit(ins(inLABEL, endLabel))

defSpecial "list":
  let alen = args.len
  for arg in args:
    propogateError(compiler.codeGen(arg))

  emit(ins(inCLIST, alen.md))

defSpecial "if":
  if args.len != 3:
    compileError("if takes 3 arguments (condition, if-true, if-false)", pos)
  propogateError(compiler.codeGen(@["cond".mds, @[args[0], args[1]].md, @[args[2]].md].md))

defSpecial "call-cc":
  verifyArgs("call-cc", args, @[dNil])
  # continuations will be of the form (cont <ID>)
  let contLabel = compiler.makeSymbol()
  emit(ins(inMCONT, contLabel))
  emit(ins(inPUSH, "cont".mds))
  emit(ins(inSWAP))
  emit(ins(inCLIST, 2.md))
  emit(ins(inCLIST, 1.md))

  propogateError(compiler.codeGen(args[0]))
  emit(ins(inACALL))
  emit(ins(inLABEL, contLabel))
