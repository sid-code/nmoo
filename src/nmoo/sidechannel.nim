import strutils
import endians
import asyncnet
import asyncdispatch
import streams
import boost/io/asyncstreams
import tables
import logging

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

# This function is called when the client sends
# ``SideChannelEscapeChar`` as the first byte of a message.
proc processEscapeSequence*(client: Client) {.async.} =
  let stream = newAsyncSocketStream(client.sock)

  # Set ID to 0 so that if anything happens, we can check the ID
  # against 0 to see if it was actually set. Of course, this means
  # that the client should never provide a zero ID. If the ID is zero,
  # then the whole request is ignored.
  var id: uint32 = 0
  try:
    # This ID will be sent back along with the result
    id = await stream.readUint32()

    # We do not allow the client-provided ID to be zero
    if id == 0:
      return

    let d = await stream.readMData()

    # compile the code!
    let instructions = compileCode(d, client.player)

    when defined(dumpSideChannelCode):
      for idx, instr in instructions.code:
        debug "$#: $#".format(idx, instr)

    if instructions.error != E_NONE.md:
      await stream.writeResponse(id, instructions.error)
      return

    # TODO: Stop writing this code over and over
    # There needs to be a standard symtable that new tasks use.
    var symtable = newSymbolTable()
    symtable = addCoreGlobals(symtable)
    symtable["self"] = client.player.md
    symtable["player"] = client.player.md
    symtable["caller"] = client.player.md

    let t = client.player.world.addTask("side-channel-task",
                                        client.player, client.player, client.player, client.player,
                                        symtable, instructions)

    let tr = client.player.world.run(client.player.world.getTaskByID(t))
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
    # If id == 0 then it's likely that it wasn't initialized.
    if id != 0:
      await stream.writeResponse(id, getCurrentExceptionMsg().md)
  
