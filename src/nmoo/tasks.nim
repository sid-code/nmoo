{.experimental: "notnil".}
import tables
import hashes
import strutils
import objects
import sequtils
import times
import std/options
import std/sugar

import types
import builtindef
import logging
## VM (Task)

# Some procs that builtins.nim needs
proc spush*(task: Task, what: MData, depth = -1) =
  task.stack.add(what)
  when defined(depthStack):
    let realDepth = if depth == -1: task.frames.len else: depth
    task.depthStack.add(realDepth)

proc spop*(task: Task): MData =
  result = task.stack.pop()
  when defined(depthStack):
    let poppedDepth = task.depthStack.pop()
    let curDepth = task.frames.len
    if curDepth != poppedDepth:
      warn "task violated depth stack"

proc resume*(task: Task, val: MData)
proc isRunning*(task: Task): bool = task.status in {tsRunning, tsReceivedInput}
proc finish*(task: Task)
proc addCoreGlobals*(st: SymbolTable): SymbolTable

proc addTask*(world: World, name: string, self, player, caller, owner: MObject,
              symtable: SymbolTable, code: CpOutput, taskType = ttFunction,
              callback = none(TaskID)): TaskID

proc setStatus*(task: Task, newStatus: TaskStatus) =
  when defined(debug):
    debug "Task ", task.name, " entered state ", newStatus
  task.status = newStatus
  if newStatus != tsRunning:
    task.world.taskFinishedCallback(task.world, task.id)

proc run*(world: World, task: Task, limit = -1): TaskResult

import compile
import builtins

proc hash(itype: InstructionType): auto = ord(itype).hash

proc newVSymTable: VSymTable = initTable[int, MData]()

proc combine(cst: CSymTable, vst: VSymTable): SymbolTable =
  result = newSymbolTable()
  for key, val in cst:
    result[key] = vst[val]

proc curFrame(task: Task): Frame =
  task.frames[task.frames.len - 1]
proc curST(task: Task): var VSymTable =
  task.curFrame().symtable

proc pushFrame(task: Task, symtable: VSymTable) =
  let frame = Frame(symtable: symtable, calledFrom: task.pc, tries: @[])
  task.frames.add(frame)

proc popFrame(task: Task) =
  task.pc = task.curFrame().calledFrom
  discard task.frames.pop()

proc collect(task: Task, num: int): seq[MData] =
  let stackLen = task.stack.len
  if stackLen < num:
    return @[]

  newSeq(result, num)
  for i in 1 .. num:
    result[num - i] = task.stack[stackLen - i]
  task.stack.setLen(stackLen - num)

proc currentTraceLine(task: Task): (string, CodePosition) =
  let pos = task.code[task.pc].pos
  return ( task.name, pos )

proc doError*(task: Task, error: MData) =
  # prepare the error for modifying
  # each stack frame/task callback will be a line
  var error = error

  # unwind the stack

  while task.frames.len > 0:
    let frame = task.curFrame()

    if frame.tries.len == 0:
      error.trace.add(task.currentTraceLine())
      task.popFrame()
      continue

    let top = frame.tries.pop()

    task.pc = top
    task.spush(error)

    return

  task.spush(error)
  task.finish()

proc setCallPackage(task: Task, package: Package, builtin: MData, args: seq[MData]) =
  task.hasCallPackage = true
  task.callPackage = package
  task.builtinToCall = builtin
  task.builtinArgs = args
  if package.ptype == ptInput:
    task.setStatus(tsAwaitingInput)

proc builtinCall(task: Task, builtin: MData, args: seq[MData], phase = 0) =
  let builtinName = builtin.symVal
  if builtinExists(builtinName):
    let bproc = builtindef.builtins[builtinName]

    # we pass in task.globals as the symtable because some builtins
    # ask for "caller" etc
    let res = bproc(
      args = args,
      world = task.world,
      self = task.self,
      player = task.player,
      caller = task.caller,
      owner = task.owner,
      pos = builtin.pos,
      symtable = task.globals,
      phase = phase,
      tid = task.id)

    if res.ptype == ptData:
      let val = res.val

      if val.isType(dErr):
        task.doError(val)
      else:
        task.spush(val)
    elif res.ptype in {ptCall, ptInput}:
      task.setCallPackage(res, builtin, args)
  else:
    task.doError(E_BUILTIN.md("unknown builtin '$1'" % builtinName))


var instImpls = initTable[InstructionType, InstructionProc]()

template impl(itype: InstructionType, body: untyped) {.dirty.} =
  instImpls[itype] =
    proc(world: World, tid: TaskID, operand: MData) =
      let task = world.getTaskByID(tid)
      body

proc top*(task: Task): MData =
  let size = task.stack.len
  if size == 0:
    return nilD
  else:
    return task.stack[size - 1]

let foreignLambdaCache = newTable[MData, CpOutput]()

proc foreignLambdaCall(task: Task, symtable: SymbolTable, lambda: seq[MData]) =
  task.setStatus(tsAwaitingResult)

  var lambda = lambda
  lambda[3] = 0.md # it doesn't matter where the lambda came from.
  let expression = lambda[5]

  var instructions: CpOutput

  let cacheEntry = @[lambda.md, task.player.md].md
  if foreignLambdaCache.hasKey(cacheEntry):
    instructions = foreignLambdaCache[cacheEntry]
  else:
    instructions = compileCode(expression, task.player)
    foreignLambdaCache[cacheEntry] = instructions

  discard task.world.addTask(
    name = task.name & "-lambda",
    self = task.self,
    player = task.player,
    caller = task.caller,
    owner = task.owner,
    symtable = symtable,
    code = instructions,
    callback = some(task.id), # Resume this task when done
    taskType = task.taskType)


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

impl inDUP:
  let top = task.top()
  task.spush(top)

impl inGTID:
  task.spush(task.id.int.md)

impl inPOP:
  discard task.spop()

impl inLABEL:
  discard #this is a dummy instruction

impl inJ0:
  let where = operand.intVal
  let what = task.spop()
  if what == 0.md:
    task.pc = where

impl inJT:
  let where = operand.intVal
  let what = task.spop()
  if what.truthy:
    task.pc = where

impl inJNT:
  let where = operand.intVal
  let what = task.spop()
  if not what.truthy:
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

impl inGSTO:
  let name = operand.symVal
  let top = task.spop()
  task.globals[name] = top

impl inCLIST:
  let size = operand.intVal
  task.spush(task.collect(size).md)

impl inMENV:
  var newST: VSymTable
  deepCopy(newST, task.curST())
  let envID = task.symtables.len
  task.symtables.add(newST)
  let cst = task.spop().toCST()

  # push the environment's ID onto the stack so that it can be accessed
  task.spush(envID.md)
  task.spush(cst.combine(newST).toData())

impl inMCONT:
  var cont: Continuation
  cont.pc = operand.intVal
  cont.globals = task.globals
  deepCopy(cont.stack, task.stack)
  deepCopy(cont.frames, task.frames)

  # push the continuation's ID onto the stack so that it can be accessed
  let contID = task.continuations.len
  task.spush(contID.md)
  task.continuations.add(cont)

proc nextInstruction(task: Task): Instruction =
  var pc = task.pc
  while true:
    pc += 1
    let inst = task.code[pc]
    if inst.itype == inLABEL:
      continue

    if inst.itype == inJMP:
      pc = inst.operand.intVal
    else:
      return inst

proc callContinuation(task: Task, contID: int) =
  if contID >= task.continuations.len:
    task.doError(E_ARGS.md("continuation id: " & $contID & " does not exist."))
    return

  let res = task.spop()

  let cont = task.continuations[contID]
  task.pc = cont.pc
  deepCopy(task.stack, cont.stack)
  deepCopy(task.frames, cont.frames)

  task.spush(res)

impl inCALL:
  let what = task.spop()
  let numArgs = operand.intVal
  if what.isType(dList):
    # It's a lambda or continuation call
    let lcall = what.listVal
    if lcall.len == 2:
      if lcall[0] != "cont".mds:
        task.doError(E_ARGS.md("invalid continuation format"))
        return

      #try:
      let contID = lcall[1].intVal
      if numArgs != 1:
        task.doError(E_ARGS.md("continuations only take 1 argument"))
        return

      let args = task.collect(numArgs)
      if args.len != numArgs:
        task.doError(E_INTERNAL.md("missing argument to continuation"))
        return

      task.spush(args[0])
      task.callContinuation(contID)

      #except:
      #  task.doError(E_ARGS.md("invalid continuation (error)"))

    elif lcall.len == 6:
      try:
        let jmploc = lcall[0]
        let env = lcall[1].intVal
        let envData = lcall[2]
        let origin = TaskID(lcall[3].intVal)
        let bounds = lcall[4].listVal.map(proc (x: MData): string = x.symVal)
        let expectedNumArgs = bounds.len
        let expression = lcall[5]

        if expectedNumArgs != numArgs:
          task.doError(E_ARGS.md("lambda expected $1 args but got $2" %
                                 [$expectedNumArgs, $numArgs]))
          return

        if origin == task.id:
          if task.nextInstruction().itype == inRET:
            # we have a tail call!
            # there's no need to push another stack frame
            discard
          else:
            task.pushFrame(symtable = task.symtables[env])
          task.pc = jmploc.intVal
        else:
          let args = task.collect(numArgs)
          if args.len != numArgs:
            task.doError(E_INTERNAL.md("insufficient arguments for lambda (need " & $numArgs & ")"))
            return

          var symtable = envData.toST()
          for name, val in task.globals:
            symtable[name] = val

          for idx, name in bounds:
            symtable[name] = args[idx]

          task.foreignLambdaCall(symtable = symtable, lambda = lcall)
      except:
        task.doError(E_ARGS.md("invalid lambda"))
    else:
      task.doError(E_ARGS.md("can't call " & $lcall))
  elif what.isType(dSym):
    # It's a builtin call
    let args = task.collect(numArgs)
    if args.len == numArgs:
      task.builtinCall(what, args)
    else:
      task.doError(E_INTERNAL.md("insufficient arguments for builtin (need " & $numArgs & ")"))
  else:
    task.doError(E_ARGS.md("cannot call '$1'" % [$what]))

impl inRET:
  task.popFrame()

impl inRETJ:
  task.popFrame()
  task.pc = operand.intVal

impl inACALL:
  let what = task.spop()
  let argsd = task.spop()
  let args = argsd.listVal
  let depth = task.frames.len + 1
  for arg in args:
    task.spush(arg, depth=depth)
  task.spush(what, depth=depth)
  instImpls[inCALL](world, tid, args.len.md)

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
  let listd = task.top()
  if not listd.isType(dList):
    task.doError(E_INTERNAL.md("not a list: ".format(listd)))
    return

  let list = listd.listVal
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
  let label = operand.intVal
  task.curFrame().tries.add(label)

impl inETRY:
  discard task.curFrame.tries.pop()

impl inHALT:
  task.finish()

proc resume*(task: Task, val: MData) =
  task.setStatus(tsRunning)
  if val.isType(dErr):
    task.hasCallPackage = false
    task.doError(val)
  else:
    task.spush(val)

proc finish*(task: Task) =
  task.setStatus(tsDone)

  let callback = task.callback
  var res = task.top()

  callback.map(proc (t: TaskID) =
    let cbTask = task.world.getTaskByID(t)
    if not isNil(cbTask):
      cbTask.tickCount += task.tickCount
      cbTask.waitingFor = none(TaskID)
      cbTask.resume(res)
    else:
      # I've decided that a warning here should suffice. The maintainer should
      # make sure that the task's callback isn't crucial to the operation of
      # the system, and if it is, then debug more.

      warn "Warning: callback for task '$#' didn't exist." % [task.name])

proc registerCallback*(task, cbTask: Task) =
  cbTask.waitingFor = some(task.id)

proc doCallPackage(task: Task) =
  let phase = task.callPackage.phase
  let sym = task.builtinToCall
  var args = task.builtinArgs
  args.add(task.spop())

  task.hasCallPackage = false
  task.builtinCall(sym, args, phase = phase)

  if task.status == tsReceivedInput:
    task.setStatus(tsRunning)

proc step*(world: World, task: Task) =
  if not task.isRunning(): return

  if task.hasCallPackage:
    task.doCallPackage()
  else:
    let inst = task.code[task.pc]
    let itype = inst.itype
    let operand = inst.operand

    if instImpls.hasKey(itype):
      instImpls[itype](world, task.id, operand)
    else:
      raise newException(Exception, "instruction '$1' not implemented" % [$itype])

    task.pc += 1
    task.tickCount += 1
    if task.tickCount >= task.tickQuota:
      task.doError(E_QUOTA.md("task has exceeded tick quota"))

proc run*(world: World, task: Task, limit = -1): TaskResult =
  if limit > -1:
    task.tickQuota = limit

  while task.tickQuota > 0:
    case task.status:
      of tsSuspended, tsAwaitingInput, tsReceivedInput:
        return TaskResult(typ: trSuspend)
      of tsAwaitingResult:
        let otask = task.waitingFor.map(x => task.world.getTaskByID(x)).get(nil)

        if isNil(otask):
          return TaskResult(typ: trSuspend)
        var res = world.run(otask, limit=task.tickQuota)
        if res.typ in {trError, trTooLong, trSuspend}:
          if res.typ == trError:
            res.err.trace.add(task.currentTraceLine())
          return res

        task.waitingFor.map(
          proc (id: TaskID) =
            # TODO: FIX THIS
            system.delete(task.world.tasks, int32(id)))

      of tsDone:
        let res = task.top()
        if res.isType(dErr):
          return TaskResult(typ: trError, err: res)
        else:
          return TaskResult(typ: trFinish, res: res)
      of tsRunning:
        world.step(task)
        task.tickQuota -= 1

  return TaskResult(typ: trTooLong)

proc addCoreGlobals*(st: SymbolTable): SymbolTable =
  result = st
  result["nil"] = nilD

proc createTask*(id: TaskID, name: string, startTime: Time, compiled: CpOutput,
           world: World, self, player, caller, owner: MObject,
           globals = newSymbolTable(), tickQuota: int, taskType: TaskType,
           callback: Option[TaskID]): Task not nil =
  let st = newVSymTable()
  let (entry, code, err) = compiled

  let globals = addCoreGlobals(globals)

  var task = Task(
    id: id,
    name: name,
    startTime: startTime,

    stack: @[],
    symtables: @[st],
    globals: globals,
    code: code,
    pc: entry,

    frames: @[],
    continuations: @[],

    world: world,
    self: self,
    player: player,
    caller: caller,
    owner: owner,

    status: tsRunning,
    suspendedUntil: fromUnix(0),
    tickCount: 0,
    tickQuota: tickQuota,

    hasCallPackage: false,
    callPackage: nilD.pack,
    builtinToCall: "".mds,
    builtinArgs: @[],

    taskType: taskType,
    callback: callback,
    waitingFor: none(TaskID)

  )

  when defined(depthStack):
    task.depthStack = @[]

  task.pushFrame(newVSymTable())
  return task

proc addTask*(world: World, name: string, self, player, caller, owner: MObject,
              symtable: SymbolTable, code: CpOutput, taskType = ttFunction,
              callback = none(TaskID)): TaskID =
  let tickQuotad = world.getGlobal("tick-quota")
  let tickQuota = if tickQuotad.isType(dInt): tickQuotad.intVal else: 20000

  let newTask = createTask(
    id = TaskID(world.taskIDCounter),
    name = name,
    startTime = getTime(),
    compiled = code,
    world = world,
    self = self,
    player = player,
    caller = caller,
    owner = owner,
    globals = symtable,
    tickQuota = tickQuota,
    taskType = taskType,
    callback = callback)
  world.taskIDCounter += 1

  callback.map(proc (cbtask: TaskID) =
    let cbTask = world.getTaskByID(cbtask)
    if isNil(cbTask):
      warn "Warning: callback for task '", newTask.name, "' doesn't exist."
    else:
      newTask.registerCallback(cbTask))

  world.tasks.add(newTask)
  return newTask.id
