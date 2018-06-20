import asyncnet
import asyncdispatch
import asynchttpserver
import boost/io/asyncstreams
import tables

import nmoo/server
import nmoo/sidechannel
import nmoo/bytedump
import nmoo/types

proc arc4random: uint32 {.importc: "arc4random".}

type
  AsyncSideChannelClient = object
    sock: AsyncSocket
    processing: TableRef[uint32, Future[MData]]

proc connect(host: string, port: Port): Future[AsyncSocket] {.async.} =
  let sock = newAsyncSocket()
  await sock.connect(host, port)
  return sock

proc writeRequest(sock: AsyncSocket, id: uint32, req: MData) {.async.} =
  let stream = newAsyncSocketStream(sock)
  await stream.writeLine("\x1C")
  await stream.writeUint32(id)
  await stream.writeMData(req)

proc request(scc: AsyncSideChannelClient, req: MData): Future[MData] =
  let retFuture = newFuture[MData]("request")
  var id: uint32
  while true:
    id = arc4random()
    if id notin scc.processing:
      break

  scc.processing[id] = retFuture
  asyncCheck writeRequest(scc.sock, id, req)
  return retFuture

proc reader(scc: AsyncSideChannelClient) {.async.} =
  while true:
    let c = await scc.sock.recv(1)
    if c.len == 0:
      break

    if c[0] == SideChannelEscapeChar:
      let stream = newAsyncSocketStream(scc.sock)
      let id = await stream.readUint32()
      let d = await stream.readMData()
      if id in scc.processing:
        let fut = scc.processing[id]
        scc.processing.del(id)

        fut.complete(d)

proc main {.async.} =
  let sock = await connect("0.0.0.0", Port(4444))
  let scc = AsyncSideChannelClient(sock: sock, processing: newTable[uint32, Future[MData]]())

  asyncCheck reader(scc)

  echo await scc.request(@["echo".mds, "hi".md].md)
  echo await scc.request(@["let".mds, @[ @[ "x".mds, 5.md].md ].md,
                           @["+".mds, "x".mds, 1.md].md].md)


waitFor main()
