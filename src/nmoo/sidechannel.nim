import strutils
import endians
import asyncnet
import asyncdispatch
import boost/io/asyncstreams
import tables

import types
import server
import tasks
import bytedump
import objects
import compile

type
  ## Provide an ID in the header so that the response can be linked to
  ## it
  SideChannelMsgHeader = array[0..3, uint8]

  SideChannelResponsePayload = object
    
proc processEscapeSequence*(client: Client) {.async.} =
  let stream = newAsyncSocketStream(client.sock)
  var id: uint32 = 0
  try:
    id = await stream.readUint32()
    let d = await stream.readMData()

    let instructions = compileCode(d, client.player)
    if instructions.error != E_NONE.md:
      await stream.writeUint32(id)
      await stream.writeMData(instructions.error)

    var symtable = newSymbolTable()
    symtable = addCoreGlobals(symtable)
    symtable["self"] = client.player.md
    symtable["player"] = client.player.md
    symtable["owner"] = client.player.md
    symtable["caller"] = client.player.md

    let t = client.player.world.addTask("side-channel-task",
                                        client.player, client.player, client.player, client.player,
                                        symtable, instructions)

    if isNil(t):
      await stream.writeUint32(id)
      await stream.writeMData(E_SIDECHAN.md("failed to add task for some reason"))
      return

    let tr = t.run
    if tr.typ == trFinish:
      await stream.writeUint32(id)
      await stream.writeMData(tr.res)
    else:
      await stream.writeUint32(id)
      case tr.typ:
        of trFinish: discard
        of trSuspend:
          await stream.writeMData(E_SIDECHAN.md("side-channel task was suspended"))
        of trError:
          await stream.writeMData(tr.err)
        of trTooLong:
          await stream.writeMData(E_SIDECHAN.md("side-channel task took too long"))
  except:
    if id != 0:
      await stream.writeUint32(id)
      await stream.writeMData("invalid".mds)
  
