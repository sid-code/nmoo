import types, objects, verbs, builtins, persist, tasks
import asyncnet, asyncdispatch, strutils

var clients {.threadvar.}: seq[AsyncSocket]

echo "Loading world... "
let world = loadWorld("min")

# TODO: make a better way to get this
# get the generic player
var genericPlayer: MObject = nil
for o in world.getObjects()[]:
  if o != nil:
    if o.getPropVal("name") == "generic player".md:
      genericPlayer = o

if genericPlayer == nil:
  stderr.write "fatal: there is no generic player"
  quit 1

proc processClient(client: AsyncSocket) {.async.} =
  await client.send("welcome!\c\L")
  let player = genericPlayer.createChild()
  world.add(player)
  player.setPropR("name", "a guest")
  proc ssend(obj: MObject, msg: string) =
    discard client.send(msg & "\c\L")

  player.output = ssend
  
  while true:
    let line = await client.recvLine()
    discard player.handleCommand(line)

var server: AsyncSocket
const
  host = "192.168.0.8"
  port = 4444

proc serve() {.async.} =
  clients = @[]
  server = newAsyncSocket()
  server.bindAddr(Port(port), host)
  server.listen()

  while true:
    let client = await server.accept()
    clients.add client

    asyncCheck processClient(client)

proc handler() {.noconv.} =
  if server != nil and not server.isClosed():
    echo "Closing socket"
    server.close()

  echo "Exit"
  quit 0

setControlCHook(handler)

echo "Starting server:  host=$1   port=$2" % [host, $port]
asyncCheck serve()
echo "Listening for connections (end with ^C)"
while true:
  for idx, task in world.tasks:
    task.step()
    if task.done:
      system.delete(world.tasks, idx)

  poll()

