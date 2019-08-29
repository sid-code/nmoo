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

import types

proc send*(client: Client, msg: string) {.async.}
proc findClient*(player: MObject): Client
proc askForInput*(task: Task, client: Client)
proc supplyTaskWithInput(client: Client, input: string)
proc inputTaskRunning(client: Client): bool
proc requiresInput(client: Client): bool

const SideChannelEscapeChar* = '\x1C'

var clog: ConsoleLogger

import objects
import verbs
import builtins
import persist
import tasks
import sidechannel


var world: World = nil

proc `==`(c1, c2: Client): bool = c1.player == c2.player

var clients {.threadvar.}: seq[Client]

proc findClient*(player: MObject): Client =
  for client in clients:
    if client.player == player:
      return client

  return nil

proc callDisconnect(player: MObject) =
  let dcTask = player.verbCall("disconnect", world.verbObj, world.verbObj, @[])
  if not isNil(dcTask):
    discard dcTask.run()

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
proc setInputTask(client: Client, inputTask: Task) =
  client.currentInputTask = inputTask

proc inputTaskRunning(client: Client): bool =
  let inputTask = client.currentInputTask
  return (not isNil(inputTask)) and inputTask.status notin {tsDone}

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
    let task = client.player.handleCommand(last)
    if isNil(task):
      client.flushOut()
    else:
      if task.taskType == ttInput:
        client.setInputTask(task)

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
proc askForInput*(task: Task, client: Client) =
  when defined(debug): debug "Task ", task.name, " asked for input!"
  client.tasksWaitingForInput.add(task)
  client.flushOut()

proc supplyTaskWithInput(client: Client, input: string) =
  let task = client.tasksWaitingForInput.pop()
  when defined(debug): debug "Supplied task ", task.name, " with input ", input
  # FIXME: if input is empty, this might result in invalid state
  task.resume(input.md)

# Called whenever a task finishes. This is used to determine when
# to flush queues/etc
proc taskFinished(task: Task) =
  if task.status in {tsDone, tsSuspended}:
    flushOutAll()

  if task.taskType == ttInput:
    let callerClient = findClient(task.caller)
    if isNil(callerClient):
      return

    if task.status == tsAwaitingInput:
      discard callerClient.unqueueIn()
    elif task.status == tsAwaitingResult:
      callerClient.setInputTask(task.world.getTaskByID(task.waitingFor))
    elif task.status == tsDone and task == callerClient.currentInputTask:
      if task.callback > -1:
        let cbTask = world.getTaskByID(task.callback)
        callerClient.setInputTask(cbTask)
        if isNil(cbTask):
          discard callerClient.unqueueIn()
      else:
        let res = task.top()
        if res.isType(dErr):
          callerClient.queueOut($res & "\r\n")
          discard callerClient.unqueueOut()

        discard callerClient.unqueueIn()
    elif task.status == tsSuspended and task == callerClient.currentInputTask:
      callerClient.setInputTask(nil)
      discard callerClient.unqueueIn()

proc determinePlayer(world: World, address: string): tuple[o: MObject, msg: string] =
  result.o = nil
  result.msg = "*** Could not connect; the server is not set up correctly. ***"

  let hcTask = world.verbObj.verbCall("handle-new-connection", world.verbObj, world.verbObj, @[address.md])

  if isNil(hcTask):
    return
  let tr = hcTask.run
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
        let oldClient = findClient(newPlayer)
        if not isNil(oldClient):
          # We need to close the old client
          await oldClient.send("*** Your character has been connected to from $#. ***\r\n" % address)
          removeClient(oldClient)

        client.player = newPlayer
        newPlayer.output = ssend
        let greetTask = newPlayer.verbCall("greet", newPlayer, newPlayer, @[], taskType = ttInput)
        if not isNil(greetTask): discard greetTask.run()
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

  server.bindAddr(port, host)
  server.listen()

  while true:
    let (address, socket) = await server.acceptAddr()
    let client = Client(
      sock: socket,
      player: nil,
      outputQueue: @[],
      inputQueue: @[],
      tasksWaitingForInput: @[],
      currentInputTask: nil)

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
    worldName = "min"
  else:
    worldName = paramStr(1)
  info "Loading world \"$#\"." % worldName

  if not existsDir("worlds" / worldName):
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
  let initTask = world.verbObj.verbCall("server-started", world.verbObj, world.verbObj, @[])
  if isNil(initTask):
    warn "Server doesn't specify #0:server-started"
    return true
  let tr = initTask.run()
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

proc tick(world: World) =
  world.tasks.keepItIf(it.status != tsDone)
  for idx in world.tasks.low..world.tasks.high:
    let task = world.tasks[idx]
    if task.status == tsDone:
      if defined(showTicks):
        debug "Task " & task.name & " finished, used " & $task.tickCount & " ticks."

    if task.status == tsSuspended:
      let suspendedUntil = task.suspendedUntil
      if suspendedUntil != fromUnix(0) and getTime() >= suspendedUntil:
        task.resume(nilD)

    if not task.isRunning(): continue
    try:
      let tr = task.run(task.tickQuota)
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
    fatal getCurrentExceptionMsg()
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

