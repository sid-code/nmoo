import types, verbs, scripting, builtins, tables, strutils, sequtils, algorithm

type
  Instruction = object
    itype: InstructionType
    operand: MData

  InstructionType = enum
    inPUSH, inCALL, inLABEL, inRET, inJ0, inJN0, inSTO, inGET, inREM, inCLIST

  SymGen = ref object
    ## Used for generating label names
    counter: int
    prefix: string

  CSymTable = Table[string, int]
  
  MCompiler = ref object
    subrs, real: seq[Instruction]
    labels: CSymTable
    symtable: CSymTable
    symgen: SymGen

  SpecialProc = proc(compiler: MCompiler, args: seq[MData])

  CompilerError = object of Exception

proc newCSymTable: CSymTable = initTable[string, int]()
proc newSymGen(prefix: string): SymGen = SymGen(counter: 0, prefix: prefix)
proc newSymGen: SymGen = newSymGen("L")
proc genSym(symgen: SymGen): string =
  result = "$1$2" % [symgen.prefix, $symgen.counter]
  symgen.counter += 1

template ins(typ: InstructionType, op: MData): Instruction =
  Instruction(itype: typ, operand: op)

template ins(typ: InstructionType): Instruction =
  ins(typ, nilD)

proc `$`(ins: Instruction): string =
  "$1\t$2" % [($ins.itype)[2 .. -1], ins.operand.toCodeStr()]

proc `$`(cpo: MCompiler): string =
  result = ""
  for ins in cpo.subrs:
    result &= $ins & "\n"
  for ins in cpo.real:
    result &= $ins & "\n"

proc compileError(msg: string) =
  raise newException(CompilerError, "Compiler error: " & msg)

proc getSymbol(symtable: CSymTable, name: string): int =
  try:
    return symtable[name]
  except:
    compileError("unbound symbol '$1'" % [name])

proc augmentWith(c1, c2: MCompiler) =
  c1.subrs.add(c2.subrs)
  c1.real.add(c2.real)

template addCode(what: expr) {.immediate.} =
  augmentWith(codeGen(what, symtable, symgen))

var specials = initTable[string, SpecialProc]()
proc specialExists(name: string): bool =
  specials.hasKey(name)

proc checkType(value: MData, expected: MDataType) =
  if not value.isType(expected):
    compileError("expected argument of type " & $expected & " instead got " & $value.dType)

template defSpecial(name: string, body: stmt) {.immediate, dirty.} =
  proc spec(compiler: MCompiler, args: seq[MData]) =
    body

  specials[name] = spec

# dNil means any type is allowed
proc verifyArgs(name: string, args: seq[MData], spec: seq[MDataType]) =
  if args.len != spec.len:
    compileError("$1: expected $2 arguments but got $3" %
      [name, $spec.len, $args.len])

  for o, e in args.zip(spec).items:
    if e != dNil and not o.isType(e):
      compileError("$1: expected argument of type $2 but got $3" %
        [name, $e, $o.dtype])

# Forward declaration
proc codeGen(compiler: MCompiler, data: MData)

proc codeGen(compiler: MCompiler, code: seq[MData]) =
  if code.len == 0:
    return

  var symtable = compiler.symtable

  let first = code[0]

  if first.isType(dSym):
    let name = first.symVal
    if specialExists(name):
      let
        args = code[1 .. -1]
        prok = compile.specials[name]
      prok(compiler, args)
    elif builtinExists(name):
      for arg in code[1 .. -1]:
        compiler.codeGen(arg)
      compiler.real.add(ins(inCALL, @[first, (code.len - 1).md].md))
    else:
      let symIndex = symtable.getSymbol(name)
      compiler.real.add(ins(inGET, symIndex.md))
  else:
    for data in code:
      compiler.codeGen(data)
    compiler.real.add(ins(inCLIST, code.len.md))

proc codeGen(compiler: MCompiler, data: MData) =
  if data.isType(dList):
    compiler.codeGen(data.listVal)
  elif data.isType(dSym):
    compiler.real.add(ins(inGET, compiler.symtable.getSymbol(data.symVal).md))
  else:
    compiler.real.add(ins(inPUSH, data))

template defSymbol(symtable: CSymTable, name: string): int =
  let index = symtable.len
  symtable[name] = index
  index

defSpecial "lambda":
  verifyArgs("lambda", args, @[dList, dNil])

  let bounds = args[0].listVal
  
  let labelLocation = compiler.subrs.len
  compiler.subrs.add(ins(inLABEL, compiler.symgen.genSym().mds))

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
    let index = compiler.symtable.getSymbol(name)
    compiler.subrs.add(ins(inREM, index.md))
    compiler.symtable.del(name)
  compiler.subrs.add(ins(inRET))
  compiler.subrs.add(addedSubrs)

  compiler.real.add(ins(inPUSH, labelLocation.md))
    

when isMainModule:
  var parser = newParser("""
  (do (lambda (x y) (+ x y)) (lambda (z) (lambda (w) (echo w z))))
  """)

  var compiler = MCompiler(
    real: @[],
    subrs: @[],
    symtable: newCSymTable(),
    labels: newCSymTable(),
    symgen: newSymGen())
  compiler.codeGen(parser.parseList())
  echo compiler
