import types, compile, scripting, tables, hashes, strutils
## VM (Task)

# Some procs that builtins.nim needs
proc suspend*(task: Task)
proc resume*(task: Task)
proc spush*(task: Task, what: MData) = task.stack.add(what)
proc spop*(task: Task): MData = task.stack.pop()

import builtins

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
    task.spush(error)

    return

  task.spush(error)
  task.done = true
  task.caller.send("Task $# failed due to error:" % [task.name])
  task.caller.send($error)

proc setCallPackage(task: Task, package: Package, builtin: MData, args: seq[MData]) =
  task.hasCallPackage = true
  task.callPackage = package
  task.builtinToCall = builtin
  task.builtinArgs = args
  task.suspend()

proc builtinCall(task: Task, builtin: MData, args: seq[MData], phase = 0) =
  let builtinName = builtin.symVal
  if builtinExists(builtinName):
    let bproc = scripting.builtins[builtinName]

    # we pass in task.globals as the symtable because some builtins
    # ask for "caller" etc
    let res = bproc(
      args = args,
      world = task.world,
      caller = task.caller,
      owner = task.owner,
      pos = builtin.pos,
      symtable = task.globals,
      phase = phase,
      task = task)

    if res.ptype == ptData:
      let val = res.val

      if val.isType(dErr):
        task.doError(val)
      else:
        task.spush(val)
    elif res.ptype == ptCall:
      task.setCallPackage(res, builtin, args)
  else:
    task.doError(E_BUILTIN.md("unknown builtin '$1'" % builtinName))


var instImpls = initTable[InstructionType, InstructionProc]()

template impl(itype: InstructionType, body: stmt) {.immediate, dirty.} =
  instImpls[itype] =
    proc(task: Task, operand: MData) =
      body

proc top(task: Task): MData =
  let size = task.stack.len
  if size == 0:
    return nilD
  else:
    return task.stack[size - 1]

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

impl inPOP:
  discard task.spop()

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
  if task.globals.hasKey(name):
    let value = task.globals[name]
    task.spush(value)
  else:
    task.doError(E_UNBOUND.md("unbound symbol '$1'" % name))

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
      task.pushFrame(symtable = task.symtables[env.intVal])
      task.pc = jmploc.intVal
    else:
      task.doError(E_ARGS.md(
        "lambda expected $1 args but got $2" %
          [$expectedNumArgs, $numArgs]))
  elif what.isType(dSym):
    # It's a builtin call
    let args = task.collect(numArgs)
    task.builtinCall(what, args)
  else:
    raise newException(Exception, "cannot call '$1'" % [$what])

impl inRET:
  task.popFrame()

impl inRETJ:
  task.popFrame()
  task.pc = operand.intVal

impl inACALL:
  let what = task.spop()
  let argsd = task.spop()
  let args = argsd.listVal
  for arg in args:
    task.spush(arg)
  task.spush(what)
  instImpls[inCALL](task, args.len.md)

# algorithm.reversed is broken
proc reversed[T](list: seq[T]): seq[T] =
  newSeq(result, 0)
  for i in countdown(list.len - 1, 0):
    result.add(list[i])

# extremely niche instruction, used for
# reversing lists by the map instruction
impl inREV:
  var list = task.spop().listVal
  task.spush(list.reversed().md)

impl inPOPL:
  var list = task.spop().listVal
  let last =
    if list.len == 0:
      nilD
    else:
      list.pop()

  task.spush(list.md)
  task.spush(last)

impl inPUSHL:
  let newVal = task.spop()
  var list = task.spop().listVal

  list.add(newVal)
  task.spush(list.md)

impl inLEN:
  var list = task.top().listVal
  task.spush(list.len.md)

impl inSWAP:
  let
    a = task.spop()
    b = task.spop()

  task.spush(a)
  task.spush(b)

impl inSWAP3:
  let
    a = task.spop()
    b = task.spop()
    c = task.spop()

  task.spush(b)
  task.spush(a)
  task.spush(c)

impl inTRY:
  let labels = operand.listVal
  task.curFrame().tries.add(labels[0].intVal)

impl inETRY:
  discard task.curFrame.tries.pop()

impl inHALT:
  task.done = true

proc getTaskByID*(world: World, id: int): Task =
  for task in world.tasks:
    if task.id == id:
      return task

  return nil

proc finish(task: Task) =
  let callback = task.callback
  if callback >= 0:
    let cbTask = task.world.getTaskByID(callback)
    if cbTask != nil:
      cbTask.callbackResult = task.top()
      cbTask.resume()
    else:
      # I've decided that a warning here should suffice. The maintainer should
      # make sure that the task's callback isn't crucial to the operation of
      # the system, and if it is, then debug more.

      echo "Warning: callback for task '$#' didn't exist." % [task.name]

proc suspend*(task: Task) = task.suspended = true
proc resume*(task: Task) = task.suspended = false

proc doCallPackage(task: Task) =
  let phase = task.callPackage.phase
  let sym = task.builtinToCall
  var args = task.builtinArgs
  args.add(task.callbackResult)

  task.hasCallPackage = false
  task.builtinCall(sym, args, phase = phase)

proc step*(task: Task) =
  if task.suspended: return

  if task.hasCallPackage:
    task.doCallPackage()
  else:
    let inst = task.code[task.pc]
    let itype = inst.itype
    let operand = inst.operand

    if instImpls.hasKey(itype):
      instImpls[itype](task, operand)
    else:
      raise newException(Exception, "instruction '$1' not implemented" % [$itype])

    if task.done:
      task.finish()

    task.pc += 1
    task.tickCount += 1

proc task*(id: int, name: string, compiled: CpOutput, world: World, owner: MObject,
           caller: MObject, globals = newSymbolTable(), callback: int): Task =
  let st = newVSymTable()
  let (entry, code) = compiled
  var task = Task(
    id: id,
    name: name,
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
    tickCount: 0,

    hasCallPackage: false,
    callPackage: nilD.pack,
    builtinToCall: "".mds,
    builtinArgs: @[],
    callbackResult: nilD,

    callback: callback

  )

  task.pushFrame(newVSymTable())
  return task

