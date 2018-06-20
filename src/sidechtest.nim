import asyncnet
import asyncdispatch
import asynchttpserver
import boost/io/asyncstreams

import nmoo/server
import nmoo/sidechannel
import nmoo/bytedump
import nmoo/types

proc connect(host: string, port: Port): Future[AsyncSocket] {.async.} =
  let sock = newAsyncSocket()
  await sock.connect(host, port)
  return sock

proc echoLines(sock: AsyncSocket) {.async.} =
  while true:
    let c = await sock.recv(1)
    stdout.write c
    if c[0] == SideChannelEscapeChar:
      let stream = newAsyncSocketStream(sock)
      let id = await stream.readUint32()
      let d = await stream.readMData()
      echo "id: " & $id
      echo $d

proc main {.async.} =
  let sock = await connect("0.0.0.0", Port(4444))
  asyncCheck echoLines(sock)
  let stream = newAsyncSocketStream(sock)
  echo "giving header"
  await stream.writeLine("\x1C")
  await stream.writeUint32(10101)
  #await stream.writeMData(@["echo".mds, "hi".md].md)
  await stream.writeMData(@["echo".mds, "hi".md].md)
  #runForever()

waitFor main()
runForever()

