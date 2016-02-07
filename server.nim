import types
# import editserv/editserv
import asyncnet, asyncdispatch, strutils, net
import logging

proc taskFinished*(task: Task)
proc findClient*(player: MObject): Client
proc askForInput*(task: Task, client: Client)
import objects, verbs, builtins, persist, tasks

var world: World = nil
var clog: ConsoleLogger

proc `==`(c1, c2: Client): bool = c1.player == c2.player

var clients {.threadvar.}: seq[Client]

proc removeClient(client: Client) =
  let index = clients.find(client)
  if index >= 0:
    system.delete(clients, index)

proc findClient*(player: MObject): Client =
  for client in clients:
    if client.player == player:
      return client

  return nil

proc callDisconnect(player: MObject) =
  let dcTask = player.verbCall("disconnect", world.verbObj, @[])
  if not isNil(dcTask):
    let res = dcTask.run()

proc close(client: Client) =
  let player = client.player
  if not isNil(player):
    player.callDisconnect()

  client.sock.close()

proc send(client: Client, msg: string) {.async.} =
  await client.sock.send(msg)

proc recvLine(client: Client): Future[string] {.async.} =
  return await client.sock.recvLine()

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

# Forward declaration for the following proc
proc supplyTaskWithInput(client: Client, input: string)

proc unqueueIn(client: Client): bool =
  if client.inputQueue.len == 0:
    return false

  let last = client.inputQueue.pop()
  if client.tasksWaitingForInput.len > 0:
    client.supplyTaskWithInput(last)
  else:
    let task = client.player.handleCommand(last)
    if isNil(task):
      client.flushOut()
    else:
      if task.taskType == ttInput:
        client.inputTaskRunning = true

  return true

proc clearIn(client: Client) =
  setLen(client.inputQueue, 0)

proc clearInAll =
  for client in clients:
    client.clearIn()

## stuff for the read builtin

# to be called from the read builtin
proc askForInput*(task: Task, client: Client) =
  client.tasksWaitingForInput.add(task)
  client.flushOut()
  discard client.unqueueIn() # This may or may not succeed, but it doesn't really matter.

proc supplyTaskWithInput(client: Client, input: string) =
  let task = client.tasksWaitingForInput.pop()
  task.spush(input.md)
  task.resume()

# Called whenever a task finishes. This is used to determine when
# to flush queues/etc
proc taskFinished*(task: Task) =
  if task.taskType == ttInput:
    let callerClient = findClient(task.caller)
    if isNil(callerClient):
      return

    flushOutAll()

    callerClient.inputTaskRunning = false
    discard callerClient.unqueueIn()

proc determinePlayer(world: World, address: string): tuple[o: MObject, msg: string] =
  result.o = nil
  result.msg = "*** Could not connect; the server is not set up correctly. ***"

  let hcTask = world.verbObj.verbCall("handle-new-connection", world.verbObj, @[address.md])

  if isNil(hcTask):
    return
  let tr = hcTask.run
  case tr.typ:
    of trFinish:
      if tr.res.isType(dObj):
        result.o = world.dataToObj(tr.res)
      else:
        if tr.res.isType(dStr):
          result.msg = tr.res.strVal
    of trSuspend:
      world.verbObj.send("The task for #0:handle-new-connection got suspended!")
    of trError:
      world.verbObj.send("The task for #0:handle-new-connection had an error.")
    of trTooLong:
      world.verbObj.send("The task for #0:handle-new-connection ran for too long!")

proc fixUp(line: string): string =
  # TODO
  return line

proc processClient(client: Client, address: string) {.async.} =

  var (player, msg) = determinePlayer(world, address)
  client.player = player

  if isNil(player):
    await client.send(msg & "\c\L")
    client.close()
    return

  clients.add(client)

  await client.send("Welcome to the server!\c\L")
  proc ssend(obj: MObject, msg: string) =
    client.queueOut(msg & "\c\L")

  client.player.output = ssend

  var connected = false

  while true:
    var line = await client.recvLine()

    # I think this means the client closed the connection?
    if line[0] == '\0':
      if not isNil(client.player):
        client.player.callDisconnect()
      removeClient(client)
      break

    line = line.strip().fixUp()

    if connected:
      client.queueIn(line)
      if not client.inputTaskRunning: # get it started!
        discard client.unqueueIn()
    else:
      let newPlayer = client.player.handleLoginCommand(line)
      if not isNil(newPlayer):
        connected = true
        client.player.callDisconnect()
        # Find out if the player is already connected
        let oldClient = findClient(newPlayer)
        if not isNil(oldClient):
          # We need to close the old client
          await oldClient.send("*** Your character has been connected to from $#. ***\c\L" % address)
          oldClient.close()
          removeClient(oldClient)

        client.player = newPlayer
        newPlayer.output = ssend
        let greetTask = newPlayer.verbCall("greet", newPlayer, @[], taskType = ttInput)
        if not isNil(greetTask): discard greetTask.run()

var server: AsyncSocket
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
      fatal "World specified invalid host $#" % host
      quit 1
    result.host = host
  else:
    warn "Server doesn't define #0.host, using default host $#" % defaultHost

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
      tasksWaitingForInput: @[])

    asyncCheck processClient(client, address)

proc cleanUp() =
  if server != nil and not server.isClosed():
    info "Closing connections"
    for client in clients:
      info "Closing a client..."
      waitFor client.send("Server is going down!\c\L")
      client.close()
    server.close()

  world.persist()

proc handler() {.noconv.} =
  cleanup()
  info "Exit"
  quit 0

proc main =
  clog = newConsoleLogger()
  addHandler(clog)

  info "Loading world... "
  world = loadWorld("min")

  world.verbObj.output = proc(obj: MObject, msg: string) =
    info "#0: " & msg

  setControlCHook(handler)

  (host, port) = getHostAndPort()

  info "Starting server:  host=$1   port=$2" % [host, $port]
  asyncCheck serve()

  info "Listening for connections (end with ^C)"

  try:
    while true:
      # experimental!
      for x in 1..100:
        world.tick()
      poll(1)
  finally:
    cleanUp()

main()

## Old code for editserver
#
# let editord = world.getGlobal("editor")
# if editord.isType(dObj):
#   let editor = world.dataToObj(editord)
#   if not isNil(editor):
#     let eportd = editor.getPropVal("port")
#     let eport = if eportd.isType(dInt): Port(eportd.intVal) else: Port(port.int + 1)
#
#     let eserv = newEditServer(editor)
#
#     info "Starting edit server:  host=$1   port=$2" % [host, $eport]
#     asyncCheck eserv.serve(eport, host)
