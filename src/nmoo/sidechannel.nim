import strutils
import endians
import asyncnet
import asyncdispatch
import boost/io/asyncstreams

import types
import server
import bytedump

type
  SideChannelMsgHeader = object
    id: array[0..3, uint8]      ## provide an unique id so that you can recognize responses
    msgLen: array[0..3, uint8]  ## length of the payload (4 bytes, but has a max of 16k)

  SideChannelError = enum
    SCPayloadTooLong = 0

  SideChannelResponsePayload = object
    
proc processEscapeSequence*(client: Client) {.async.} =
  let stream = newAsyncSocketStream(client.sock)
  try:
    let d = await stream.readMData()
    echo d
  except:
    await stream.writeMData("invalid".md)
  
