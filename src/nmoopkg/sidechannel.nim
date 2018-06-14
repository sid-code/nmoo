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
    

# Until I find a better solution, this is how it has to be
proc toUint32(buf: array[0..3, uint8]): uint32 =
  result = buf[0]
  result = result shl 1
  result += buf[1]
  result = result shl 1
  result += buf[2]
  result = result shl 1
  result += buf[3]
  echo buf[0], buf[1], buf[2], buf[3]

proc processEscapeSequence*(client: Client) {.async.} =
  let stream = newAsyncSocketStream(client.sock)
  try:
    let d = await stream.readMData()
    echo d
  except:
    await stream.writeMData("invalid".md)
  
