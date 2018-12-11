import asyncnet
import asyncdispatch
import boost/io/asyncstreams
import asynctools/asyncsync
import tables
import deques

import ../server
import ../sidechannel
import ../bytedump
import ../types

proc arc4random: uint32 {.importc: "arc4random".}

type

  AsyncSideChannelClient* = object
    lock: AsyncLock
    sock*: AsyncSocket
    processing: TableRef[uint32, Future[MData]]

proc newAsyncSideChannelClient*(sock: AsyncSocket): AsyncSideChannelClient =
  return AsyncSideChannelClient(
    lock: newAsyncLock(),
    sock: sock,
    processing: newTable[uint32, Future[MData]]())

proc writeRequest(sock: AsyncSocket, lock: AsyncLock, id: uint32, req: MData) {.async.} =
  await lock.acquire()
  let stream = newAsyncSocketStream(sock)
  await stream.writeLine(""&SideChannelEscapeChar)
  await stream.writeUint32(id)
  await stream.writeMData(req)
  lock.release()

proc request*(scc: AsyncSideChannelClient, req: MData): Future[MData] =
  let retFuture = newFuture[MData]("request")
  var id: uint32
  while true:
    id = arc4random()
    if id notin scc.processing:
      break

  scc.processing[id] = retFuture
  asyncCheck writeRequest(scc.sock, scc.lock, id, req)
  return retFuture

# start this with asyncCheck
proc startReader*(scc: AsyncSideChannelClient) {.async.} =
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
