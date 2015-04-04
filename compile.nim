import types, verbs, scripting, builtins, tables, hashes, strutils, sequtils
from algorithm import reversed

type
  Instruction = object
    itype: InstructionType
    operand: MData

  InstructionType = enum
    inPUSH, inCALL, inACALL, inLABEL, inRET, inJ0, inJN0,
    inLPUSH, # strictly for labels - gets replaced by the renderer
    inSTO, inGET, inGGET, inCLIST,
    inPOPL, inPUSHL, inLEN, inSWAP, inSWAP3, inSPLAT,
    inMENV, inGENV,
    inHALT

  SymGen = ref object
    ## Used for generating label names
    counter: int
    prefix: string

  CSymTable = Table[string, int]

  MCompiler = ref object
    subrs, real: seq[Instruction]
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

proc hash(itype: InstructionType): auto = ord(itype).hash

proc `$`(ins: Instruction): string =
  let itypeStr = ($ins.itype)[2 .. -1]
  if ins.operand == nilD:
    return itypeStr & "\t"
  else:
    return "$1\t$2" % [itypeStr, ins.operand.toCodeStr()]

proc `$`(compiler: MCompiler): string =
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
  raise newException(CompilerError, "Compiler error: " & msg)

proc getSymbol(symtable: CSymTable, name: string): int =
  if symtable.hasKey(name):
    return symtable[name]
  else:
    compileError("unbound symbol '$1'" % [name])

proc getSymInst(symtable: CSymTable, name: string): Instruction =
  try:
    let index = symtable.getSymbol(name)
    return ins(inGET, index.md)
  except:
    return ins(inGGET, name.mds)

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

# Forward declaration
proc codeGen(compiler: MCompiler, data: MData)

proc codeGen(compiler: MCompiler, code: seq[MData]) =
  if code.len == 0:
    compiler.real.add(ins(inCLIST, 0.md))
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
      compiler.real.add(ins(inPUSH, first))
      compiler.real.add(ins(inCALL, (code.len - 1).md))
    else:
      compiler.real.add(symtable.getSymInst(name))
  else:
    for data in code:
      compiler.codeGen(data)
    compiler.real.add(ins(inCLIST, code.len.md))

proc codeGen(compiler: MCompiler, data: MData) =
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

proc render(compiler: MCompiler): tuple[entry: int, code: seq[Instruction]] =
  ## Remove all label references and replace them
  ## with numbers that refer to there they jump to
  ##
  ## Instructions that still use labels:
  ##   J0, JN0, LPUSH

  var labels = newCSymTable()
  var code = compiler.subrs & compiler.real
  let entry = compiler.subrs.len

  for idx, inst in code:
    if inst.itype == inLABEL:
      labels[inst.operand.symVal] = idx

  for idx, inst in code:
    let op = inst.operand
    if inst.itype == inJ0 or inst.itype == inJN0:
      if op.isType(dSym):
        let label = op.symVal
        let jumpLoc = labels[label]
        code[idx] = ins(inst.itype, jumpLoc.md)
    elif inst.itype == inLPUSH:
      code[idx] = ins(inPUSH, labels[op.symVal].md)

  code.add(ins(inHALT))
  return (entry, code)

defSpecial "lambda":
  verifyArgs("lambda", args, @[dList, dNil])

  let bounds = args[0].listVal

  let labelName = compiler.addLabel(subrs)

  compiler.subrs.add(ins(inGENV))
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
  compiler.real.add(ins(inCLIST, 0.md))
  compiler.codeGen(args[1])
  let labelLocation = compiler.addLabel(real)
  compiler.real.add(ins(inPOPL))
  compiler.real.add(ins(inGET, index.md))
  compiler.real.add(ins(inCALL, 1.md))
  compiler.real.add(ins(inSWAP3))
  compiler.real.add(ins(inSWAP))
  compiler.real.add(ins(inPUSHL))
  compiler.real.add(ins(inSWAP))
  compiler.real.add(ins(inLEN))
  compiler.real.add(ins(inJ0, labelLocation))

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
## VM (Task)

type
  VSymTable = TableRef[int, MData]
  Task = ref object
    stack:     seq[MData]
    stStack:   seq[VSymTable]     ## Stack of symbol tables
    symtables: seq[VSymTable]     ## All of the symbol tables
    globals:   SymbolTable        ## Same type as used by parser
    code:      seq[Instruction]
    pc:        int                ## Program counter
    callstack: seq[int]

    world:     World
    owner:     MObject
    caller:    MObject

    done: bool
    suspended: bool
    restartTime: int
    tickCount: int

  InstructionProc = proc(task: Task, operand: MData)

proc newVSymTable: VSymTable = newTable[int, MData]()
proc curST(task: Task): VSymTable = task.stStack[task.stStack.len - 1]

proc spush(task: Task, what: MData) = task.stack.add(what)
proc spop(task: Task): MData = task.stack.pop()
proc collect(task: Task, num: int): seq[MData] =
  newSeq(result, 0)
  for i in 0 .. num - 1:
    discard i
    result.insert(task.spop(), 0)

var instImpls = initTable[InstructionType, InstructionProc]()

template impl(itype: InstructionType, body: stmt) {.immediate, dirty.} =
  instImpls[itype] =
    proc(task: Task, operand: MData) =
      body

# Implementation of instructions
#
# To keep the code concise, I don't bother to check types- the compiler
# should in theory generate perfect code (or throw an error). If this
# causes problems later, I'll add type-checking
impl inGET:
  let index = operand.intVal
  let got = task.curST[index]
  task.spush(got)

impl inSTO:
  let what = task.spop()
  let index = operand.intVal
  task.curST[index] = what

impl inPUSH:
  task.spush(operand)

impl inLABEL:
  discard #this is a dummy instruction

impl inJ0:
  let where = operand.intVal
  let what = task.spop()
  if what == 0.md:
    task.pc = where

impl inJN0:
  let where = operand.intVal
  let what = task.spop()
  if what != 0.md:
    task.pc = where

impl inGGET:
  let name = operand.symVal
  let value = task.globals[name]

  task.spush(value)

impl inCLIST:
  let size = operand.intVal
  task.spush(task.collect(size).md)

impl inMENV:
  var newST: VSymTable
  deepCopy(newST, task.curST())
  let pos = task.symtables.len
  task.symtables.add(newST)
  task.spush(pos.md)

impl inGENV:
  let envIndex = task.spop().intVal
  task.stStack.add(task.symtables[envIndex])

impl inCALL:
  let what = task.spop()
  let numArgs = operand.intVal
  if what.isType(dList):
    # It's a lambda call
    let lcall = what.listVal
    let jmploc = lcall[0]
    let env = lcall[1]
    let expectedNumArgs = lcall[2].intVal
    if expectedNumArgs == numArgs:
      task.spush(env)
      task.callstack.add(task.pc)
      task.pc = jmploc.intVal
    else:
      discard
      # Figure out what to do with the error
  elif what.isType(dSym):
    # It's a builtin call
    let builtinName = what.symVal

    # builtinName is guaranteed to hold a valid builtin
    let bproc = scripting.builtins[builtinName]
    let args = task.collect(numArgs)

    # we pass in task.globals as the symtable because some builtins
    # ask for "caller" etc
    let res = bproc(args, task.world, task.owner, task.caller, task.globals)

    if res.isType(dErr):
      discard
      # Figure out what to do with the error
    else:
      task.spush(res)

  else:
    raise newException(Exception, "cannot call '$1'" % [$what])

impl inRET:
  let backto = task.callstack.pop()
  discard task.stStack.pop()
  task.pc = backto
impl inACALL:
  let what = task.spop()
  let argsd = task.spop()
  let args = argsd.listVal
  for arg in args:
    task.spush(arg)
  task.spush(what)
  instImpls[inCALL](task, args.len.md)

impl inHALT:
  task.done = true

proc step(task: Task) =
  let inst = task.code[task.pc]
  let itype = inst.itype
  let operand = inst.operand

  if instImpls.hasKey(itype):
    instImpls[itype](task, operand)
  else:
    return

  task.pc += 1
  task.tickCount += 1

proc taskFromCompiler(compiler: MCompiler, world: World, owner: MObject,
                      caller: MObject, globals = initSymbolTable()): Task =
  let st = newVSymTable()
  let (entry, code) = compiler.render
  return Task(
    stack: @[],
    stStack: @[st],
    symtables: @[st],
    globals: globals,
    code: code,
    pc: entry,
    callstack: @[],

    world: world,
    owner: owner,
    caller: caller,

    done: false,
    suspended: false,
    restartTime: 0,
    tickCount: 0

  )

when isMainModule:
  # var parser = newParser("""
  # (do (lambda (x y) (+ x y)) (lambda (z a b c) (lambda (w) (echo w z))))
  # """)
  var parser = newParser("""
  (let ((addThree
            (let ((makeAdder
                    (lambda (x)
                      (lambda (y)
                        (+ x y)))))

               (call makeAdder (3)))))

      (call addThree (5)))
  """)

  var compiler = MCompiler(
    real: @[],
    subrs: @[],
    symtable: newCSymTable(),
    symgen: newSymGen())
  compiler.codeGen(parser.parseList())
  var task = taskFromCompiler(compiler, nil, nil, nil)
  echo compiler
  while not task.done:
    #echo task.code[task.pc]
    task.step()
    #echo task.stack
    #echo task.symtables
    #echo task.pc
  echo task.stack


