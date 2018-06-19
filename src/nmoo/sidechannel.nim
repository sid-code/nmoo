import strutils
import endians
import asyncnet
import asyncdispatch
import streams
import boost/io/asyncstreams
import tables

import types
import server
import tasks
import bytedump
import objects
import compile
import util/msstreams # for multisync write

proc writeResponse(s: Stream | AsyncStream, id: uint32, d: MData) {.multisync.} =
  await s.writeChar(SideChannelEscapeChar)
  await s.write(id)
  await s.writeMData(d)

proc processEscapeSequence*(client: Client) {.async.} =
  let stream = newAsyncSocketStream(client.sock)
  var id: uint32 = 0
  try:
    id = await stream.readUint32()

    if id == 0:
      return

    let d = await stream.readMData()

    let instructions = compileCode(d, client.player)
    if instructions.error != E_NONE.md:
      await stream.writeResponse(id, instructions.error)
      return

    var symtable = newSymbolTable()
    symtable = addCoreGlobals(symtable)
    symtable["self"] = client.player.md
    symtable["player"] = client.player.md
    symtable["owner"] = client.player.md
    symtable["caller"] = client.player.md

    let t = client.player.world.addTask("side-channel-task",
                                        client.player, client.player, client.player, client.player,
                                        symtable, instructions)

    let tr = t.run()
    if tr.typ == trFinish:
      await stream.writeResponse(id, tr.res)
    else:
      case tr.typ:
        of trFinish: discard
        of trSuspend:
          await stream.writeResponse(id, E_SIDECHAN.md("side-channel task was suspended"))
        of trError:
          await stream.writeResponse(id, tr.err)
        of trTooLong:
          await stream.writeResponse(id, E_SIDECHAN.md("side-channel task took too long"))
  except:
    if id != 0:
      await stream.writeResponse(id, getCurrentExceptionMsg().md)
  
