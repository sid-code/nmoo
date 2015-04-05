import types, compile, scripting, builtins, tables, hashes, strutils
## VM (Task)

proc hash(itype: InstructionType): auto = ord(itype).hash

proc newVSymTable: VSymTable = newTable[int, MData]()
proc curFrame(task: Task): Frame =
  task.frames[task.frames.len - 1]
proc curST(task: Task): VSymTable =
  task.curFrame().symtable

proc pushFrame(task: Task, symtable: VSymTable) =
  let frame = Frame(symtable: symtable, calledFrom: task.pc, tries: @[])
  task.frames.add(frame)

proc popFrame(task: Task) =
  task.pc = task.curFrame().calledFrom
  discard task.frames.pop()

proc spush(task: Task, what: MData) = task.stack.add(what)
proc spop(task: Task): MData = task.stack.pop()
proc collect(task: Task, num: int): seq[MData] =
  newSeq(result, 0)
  for i in 0 .. num - 1:
    discard i
    result.insert(task.spop(), 0)

proc doError(task: Task, error: MData) =
  # unwind the stack
  while task.frames.len > 0:
    let tries = task.curFrame().tries

    if tries.len == 0:
      task.popFrame()
      continue

    let top = tries[tries.len - 1]
    task.pc = top
    return

  task.spush(error)
  task.done = true


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

impl inJMP:
  let where = operand.intVal
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
      task.pushFrame(
        symtable = task.symtables[env.intVal]
      )
      task.pc = jmploc.intVal
    else:
      task.doError(E_ARGS.md(
        "lambda expected $1 args but got $2" %
          [$expectedNumArgs, $numArgs]))
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
      task.doError(res)
    else:
      task.spush(res)

  else:
    raise newException(Exception, "cannot call '$1'" % [$what])

impl inRET:
  task.popFrame()

impl inACALL:
  let what = task.spop()
  let argsd = task.spop()
  let args = argsd.listVal
  for arg in args:
    task.spush(arg)
  task.spush(what)
  instImpls[inCALL](task, args.len.md)

impl inTRY:
  let labels = operand.listVal
  task.curFrame().tries.add(labels[0].intVal)

impl inETRY:
  discard task.curFrame.tries.pop()

impl inHALT:
  task.done = true

proc step*(task: Task) =
  let inst = task.code[task.pc]
  let itype = inst.itype
  let operand = inst.operand

  if instImpls.hasKey(itype):
    instImpls[itype](task, operand)
  else:
    raise newException(Exception, "instruction '$1' not implemented" % [$itype])

  task.pc += 1
  task.tickCount += 1

proc task*(compiled: CpOutput, world: World, owner: MObject,
                       caller: MObject, globals = initSymbolTable()): Task =
  let st = newVSymTable()
  let (entry, code) = compiled
  var task = Task(
    stack: @[],
    symtables: @[st],
    globals: globals,
    code: code,
    pc: entry,

    frames: @[],

    world: world,
    owner: owner,
    caller: caller,

    done: false,
    suspended: false,
    restartTime: 0,
    tickCount: 0

  )

  task.pushFrame(newVSymTable())
  return task

when isMainModule:
  # var parser = newParser("""
  # (do (lambda (x y) (+ x y)) (lambda (z a b c) (lambda (w) (echo w z))))
  # """)
  # (let ((addThree
  #           (let ((makeAdder
  #                   (lambda (x)
  #                     (lambda (y)
  #                       (+ "hi" y)))))

  #              (call makeAdder (3)))))

  #     (call addThree (5)))
  var parser = newParser("""
  (let ((x (lambda () (+ "hi" 4))))
    (try (call x ()) (4)))
  """)

  var compiler = MCompiler(
    real: @[],
    subrs: @[],
    symtable: newCSymTable(),
    symgen: newSymGen())
  compiler.codeGen(parser.parseList())
  var task = compiler.task(nil, nil, nil)
  echo compiler
  while not task.done:
    #echo task.code[task.pc]
    task.step()
    #echo task.stack
    #echo task.symtables
    #echo task.pc
  echo task.stack

