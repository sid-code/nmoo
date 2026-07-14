import strutils
import asyncdispatch
import asyncnet
import streams
import boost/io/asyncstreams
import tables

import types
import objects
import server
import tasks
import bytedump
import compile
import util/msstreams # for multisync write

proc writeResponse(s: Stream | AsyncStream, id: uint32, d: MData) {.used, multisync.} =
  await s.writeChar(SideChannelEscapeChar)
  await s.write(id)
  await s.writeMData(d)

proc processEscapeSequence*(sock: AsyncSocket, player: MObject, world: World) {.async.} =
  ## Process a side-channel escape sequence on a raw socket.
  ## Called when the client sends ``SideChannelEscapeChar`` as the first byte.
  let stream = newAsyncSocketStream(sock)
  

  var id: uint32 = 0
  try:
    id = await stream.readUint32()

    if id == 0:
      return

    if not player.isProgrammer:
      await stream.writeResponse(id, E_PERM.md)
      return

    let d = await stream.readMData()

    let instructions = compileCode(d, player)

    when defined(dumpSideChannelCode):
      for idx, instr in instructions.code:
        debug "$#: $#".format(idx, instr)

    if instructions.error != E_NONE.md:
      await stream.writeResponse(id, instructions.error)
      return

    var symtable = newSymbolTable()
    symtable = addCoreGlobals(symtable)
    symtable["self"] = player.md
    symtable["player"] = player.md
    symtable["caller"] = player.md

    let t = world.addTask("side-channel-task",
                          player, player, player, player,
                          symtable, instructions)

    let tr = world.run(t)
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

# Legacy wrapper — delegates to the standalone proc.
proc processEscapeSequence*(client: Client) {.async.} =
  await client.sock.processEscapeSequence(client.player, client.player.world)
