# This code starts a TCP server that people can control their players
# through

import asyncnet
import asyncdispatch
import strutils
import net
import streams
import times
import math
import logging
import os
import options
import sequtils
import logfmt
import std/sugar
import std/tables
import std/options

import types

proc send*(client: Client, msg: string) {.async.}
proc findClient*(player: MObject): Option[Client]
proc askForInput*(world: World, tid: TaskID, client: Client)
proc supplyTaskWithInput(client: Client, input: string)
proc inputTaskRunning(client: Client): bool
proc requiresInput(client: Client): bool

const SideChannelEscapeChar* = '\x1C'

var clog: ConsoleLogger

import objects
import verbs
import builtindef
import builtins
import persist
import tasks
import sidechannel


var world: World = nil

proc `==`(c1, c2: Client): bool = c1.player == c2.player

var clients {.threadvar.}: seq[Client]

proc findClient*(player: MObject): Option[Client] =
  for client in clients:
    if client.player == player:
      return some(client)

  return none(Client)

proc callDisconnect(player: MObject) =
  var dcTask: Option[TaskID]
  verbCall(dcTask, player, "disconnect", world.verbObj, world.verbObj, @[])

  dcTask.map(proc (t: TaskID) = discard world.run(t))

proc close(client: Client) =
  client.sock.close()

proc removeClient(client: Client) =
  let player = client.player
  if not isNil(player):
    player.callDisconnect()

  if client.inputTaskRunning() and client.requiresInput():
    client.supplyTaskWithInput("")

  let index = clients.find(client)
  if index >= 0:
    system.delete(clients, index)

  client.close()

proc send*(client: Client, msg: string) {.async.} =
  await client.sock.send(msg)

proc recvLine(client: Client): Future[string] {.async.} =
  return await client.sock.recvLine()

# client input task procs
proc setInputTask(client: Client, tid: TaskID) =
  client.currentInputTask = some(tid)
proc clearInputTask(client: Client) =
  client.currentInputTask = none(TaskID)

proc inputTaskRunning(client: Client): bool =
  let inputTask = client.currentInputTask
  return inputTask
    .flatMap((tid: TaskID) => world.getTaskById(tid))
    .map(t => t.status notin {tsDone})
    .get(false)

proc requiresInput(client: Client): bool =
  client.tasksWaitingForInput.len > 0 or not client.inputTaskRunning()


## I/O Queues
#
# TODO: add some kind of documentation here?
proc queueOut(client: Client, msg: string) =
  client.outputQueue.insert(msg, 0)

proc unqueueOut(client: Client): bool =
  if client.outputQueue.len == 0:
    return false

  let last = client.outputQueue.pop()
  discard client.send(last)
  return true

proc flushOut(client: Client) =
  while client.unqueueOut():
    discard

proc flushOutAll =
  for client in clients:
    client.flushOut()

proc queueIn(client: Client, msg: string) =
  client.inputQueue.insert(msg, 0)

proc unqueueIn(client: Client): bool =
  if client.inputQueue.len == 0:
    return false

  let last = client.inputQueue.pop()
  when defined(debug):
    debug "Tasks currently waiting for input: ", client.tasksWaitingForInput.len

  if client.tasksWaitingForInput.len > 0:
    client.supplyTaskWithInput(last)
  else:
    let tid = client.player.handleCommand(last)
    if tid.isNone:
      client.flushOut()
    else:
      let taskO = world.getTaskByID(tid.unsafeGet)
      if taskO.isSome and taskO.unsafeGet.taskType == ttInput:
        client.setInputTask(tid.unsafeGet)

  return true

proc unqueueAll =
  for client in clients:
    discard client.unqueueIn()

proc clearIn(client: Client) =
  setLen(client.inputQueue, 0)

proc clearInAll =
  for client in clients:
    client.clearIn()

## stuff for the read builtin

# to be called from the read builtin
proc askForInput*(world: World, tid: TaskID, client: Client) =
  when defined(debug): debug "Task ", $tid, " asked for input!"
  client.tasksWaitingForInput.add(tid)
  client.flushOut()

proc supplyTaskWithInput(client: Client, input: string) =
  let tid = client.tasksWaitingForInput.pop()
  when defined(debug): debug "Supplied task ", tid, " with input ", input
  let task = world.getTaskById(tid)
  if task.isNone:
    warn "Tried to supply nonexistent task ", tid, " with input"
  # FIXME: if input is empty, this might result in invalid state
  task.unsafeGet.resume(input.md)

# Called whenever a task finishes. This is used to determine when
# to flush queues/etc
proc taskFinished(world: World, tid: TaskID) =
  let taskO = world.getTaskByID(tid)
  if taskO.isNone:
    warn "Tried to finish nonexistent task ", tid
    return

  let task = taskO.unsafeGet
  if task.status in {tsDone, tsSuspended}:
    flushOutAll()

  if task.taskType == ttInput:
    let callerClientO = findClient(task.caller)
    if callerClientO.isNone:
      return

    let callerClient = callerClientO.get

    if task.status == tsAwaitingInput:
      discard callerClient.unqueueIn()
    elif task.status == tsAwaitingResult:
      task.waitingFor.map(proc(t: TaskID) = callerClient.setInputTask(t))
    elif task.status == tsDone and some(tid) == callerClient.currentInputTask:
      if task.callback.isSome:
        let cbTask = world.getTaskByID(task.callback.unsafeGet)
        callerClient.setInputTask(task.callback.unsafeGet)
        discard cbTask.map(_ => callerClient.unqueueIn())
      else:
        let res = task.top()
        if res.isType(dErr):
          callerClient.queueOut($res & "\r\n")
          discard callerClient.unqueueOut()

        discard callerClient.unqueueIn()
    elif task.status == tsSuspended and some(tid) == callerClient.currentInputTask:
      callerClient.clearInputTask()
      discard callerClient.unqueueIn()

proc determinePlayer(world: World, address: string): tuple[o: MObject, msg: string] =
  result.o = nil
  result.msg = "*** Could not connect; the server is not set up correctly. ***"

  var hcTask: Option[TaskID]
  verbCall(hcTask, world.verbObj, "handle-new-connection", world.verbObj, world.verbObj, @[address.md])

  if hcTask.isNone:
    return
  let tr = world.run(hcTask.unsafeGet)
  case tr.typ:
    of trFinish:
      if tr.res.isType(dObj):
        let playerO = world.dataToObj(tr.res)
        if playerO.isSome():
          result.o = playerO.get()
        else:
          world.verbObj.send("The task for #0:handle-new-connection returned a non-object!")
      else:
        if tr.res.isType(dStr):
          result.msg = tr.res.strVal
    of trSuspend:
      world.verbObj.send("The task for #0:handle-new-connection got suspended!")
    of trError:
      world.verbObj.send("The task for #0:handle-new-connection had an error.")
    of trTooLong:
      world.verbObj.send("The task for #0:handle-new-connection ran for too long!")

proc fixUp(line: var string) =
  if line[^1] == "\n"[0]:
    line.setLen(line.len - 1)

  # TODO: add more?

proc processClient(client: Client, address: string) {.async.} =

  var (player, msg) = determinePlayer(world, address)
  client.player = player

  if isNil(player):
    await client.send(msg & "\r\n")
    client.close()
    return

  clients.add(client)

  await client.send("Welcome to the server!\r\n")

  # This proc is how the player object communicates with the
  # connection. It's set to a variable and not directly to
  # `client.player.output` because it's re-used later.
  proc ssend(obj: MObject, msg: string) =
    client.queueOut(msg & "\r\n")
    discard client.unqueueOut()
    # TODO: Make it so output is unqueued only between tasks

  # This is a dummy version of `ssend`
  proc devnull(obj: MObject, msg: string) =
    discard obj
    discard msg

  # Has the player connected to an existing character?
  var connected = false

  while true:
    var line = await client.recvLine()

    # Disconnection check
    if line.len == 0 or line[0] == '\0':
      removeClient(client)
      break

    # Check side channel escape code before basically everything else.
    if line[0] == SideChannelEscapeChar:
      client.player.output = devnull
      await client.processEscapeSequence()
      continue

    client.player.output = ssend

    when defined(debug): debug "Received ", line

    line.fixUp()

    if connected:
      client.queueIn(line)
      if client.requiresInput(): # get it started!
        discard client.unqueueIn()
    else:
      let newPlayer = client.player.handleLoginCommand(line)
      client.flushOut()
      if not isNil(newPlayer):
        connected = true
        client.player.callDisconnect()

        # Find out if the player is already connected
        let oldClientO = findClient(newPlayer)
        if oldClientO.isSome:
          let oldClient = oldClientO.get
          # We need to close the old client
          await oldClient.send("*** Your character has been connected to from $#. ***\r\n" % address)
          removeClient(oldClient)

        client.player = newPlayer
        newPlayer.output = ssend
        var greetTask: Option[TaskID]
        verbCall(greetTask, newPlayer, "greet", newPlayer, newPlayer, @[], taskType = ttInput)
        greetTask.map(
          proc (tid: TaskID) =
            discard world.run(tid))
        client.flushOut()

var server: asyncnet.AsyncSocket
const
  defaultHost = "localhost"
  defaultPort = Port(4444)

proc getHostAndPort: tuple[host: string, port: Port] =
  # Defaults
  result.host = defaultHost
  result.port = defaultPort

  let hostd = world.getGlobal("host")
  if hostd.isType(dStr):
    let host = hostd.strVal
    if not isIpAddress(host):
      fatal "World specified invalid host '$#'" % host
      quit 1
    result.host = host
  else:
    warn "Server doesn't define #0.host, using default host '$#'" % defaultHost

  let portd = world.getGlobal("port")
  if portd.isType(dInt):
    let port = portd.intVal
    if port < 0 or port > 65535:
      fatal "Invalid port $#" % $port
      quit 1

    result.port = Port(port)
  else:
    warn "Server doesn't specify #0.port, using default port $#" % $defaultPort

var host: string
var port: Port

proc serve {.async.} =
  clients = @[]
  server = newAsyncSocket()
  server.setSockOpt(OptReuseAddr, true)

  when defined(includeWizardUtils):
    defBuiltin "clients":
      if not isWizard(task.owner):
        E_PERM.md("only wizards can use the " & bname & " builtin").pack
      else:
        clients.mapIt(@[it.player.md, it.address.md].md).md.pack

  server.bindAddr(port, host)
  server.listen()

  while true:
    let (address, socket) = await server.acceptAddr()
    let client = Client(
      address: address,
      sock: socket,
      player: nil,
      outputQueue: @[],
      inputQueue: @[],
      tasksWaitingForInput: @[],
      currentInputTask: none(TaskID))

    asyncCheck processClient(client, address)

proc cleanUp() =
  if server != nil and not server.isClosed():
    info "Closing connections"
    var index = clients.len
    while index > 0:
      dec index
      let client = clients[index]
      info "Closing a client..."
      waitFor client.send("Server is going down!\r\n")
      removeClient(client)
    server.close()

  world.persist()
  debug "Releasing lock."
  if not releaseLock(world.name):
    fatal "Failed to release lock!"

proc handler() {.noconv.} =
  info "Shutting down..."
  raise newException(Exception, "Received SIGINT")

proc initWorld =
  var worldName: string
  if paramCount() < 1:
    worldName = "core"
  else:
    worldName = paramStr(1)
  info "Loading world \"$#\"." % worldName

  if not dirExists("worlds" / worldName):
    fatal "World \"$#\" doesn't exist." % worldName;
    quit(1)

  if not acquireLock(worldName):
    fatal "Failed to acquire lock ($#)." % worldName
    quit(1)

  try:
    world = loadWorld(worldName)
  except:
    let msg = getCurrentExceptionMsg()
    discard releaseLock(worldName)
    fatal "Error while loading world: $#".format(msg)
    quit(1)

  try:
    world.check()
  except InvalidWorldError:
    let exception = getCurrentException()
    warn "Invalid world: " & exception.msg & "."

  world.taskFinishedCallback = taskFinished
  world.verbObj.output = proc(obj: MObject, msg: string) =
    info "#0: " & msg

proc runInitVerb(world: World): bool =
  var initTask: Option[TaskID]
  verbCall(initTask, world.verbObj, "server-started", world.verbObj, world.verbObj, @[])
  if initTask.isNone:
    warn "Server doesn't specify #0:server-started"
    return true
  let tr = world.run(initTask.unsafeGet)
  case tr.typ:
    of trFinish:
      world.verbObj.send("The task for #0:server-started returned " & $tr.res)
      return true
    of trSuspend:
      world.verbObj.send("The task for #0:server-started got suspended!")
      return false
    of trError:
      world.verbObj.send("The task for #0:server-started had an error.")
      return false
    of trTooLong:
      world.verbObj.send("The task for #0:server-started ran for too long!")
      return false

proc pruneFinishedTasks(world: World) =
  var prune: seq[TaskID] = @[]
  for tid, task in world.tasks.pairs:
    if task.status == tsDone:
      prune.add(tid)
  for tid in prune:
      world.tasks.del(tid)

proc tick(world: World) =
  let tids = toSeq(world.tasks.keys)
  for tid in tids:
    let task = world.tasks[tid]
    if task.status == tsDone:
      if defined(showTicks):
        debug "Task " & task.name & " finished, used " & $task.tickCount & " ticks."

    if task.status == tsSuspended:
      let suspendedUntil = task.suspendedUntil
      if suspendedUntil != fromUnix(0) and getTime() >= suspendedUntil:
        task.resume(nilD)

    if not task.isRunning(): continue
    try:
      let tr = world.run(tid, task.tickQuota)
      case tr.typ:
        of trFinish, trSuspend:
          discard
        of trTooLong:
          task.player.send("Your task ran for too long, so it was terminated.")
        of trError:
          task.player.send($tr.err)
    except:
      let exception = getCurrentException()
      warn exception.repr
      task.doError(E_INTERNAL.md(exception.msg))
  world.pruneFinishedTasks()

proc startServer {.async.} =
  if runInitVerb(world):
    (host, port) = getHostAndPort()

    info "Starting server:  host=$1   port=$2" % [host, $port]
    await serve()


proc mainLoop =
  var totalPulses = 0
  var totalPulseTime = 0.0

  setControlCHook(handler)

  try:
    while true:
      poll()
      # handle input
      world.tick()
      unqueueAll()

  except:
    fatal getCurrentExceptionMsg(), "\n", getCurrentException().getStackTrace()
  finally:
    cleanUp()

proc start* =
  clog = newConsoleLogger(fmtStr=MLogFmtStr)
  addHandler(clog)

  initWorld()

  # start the nmoo server
  asyncCheck startServer()
  # start the edit server
  #asyncCheck startEditServer(world, Port(8080))

  info "Terminate with ^C"

  mainLoop()
