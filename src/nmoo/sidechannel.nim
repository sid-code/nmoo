import strutils
import endians
import asyncnet
import asyncdispatch
import boost/io/asyncstreams

import types
import server
import bytedump

type
  ## Provide an ID in the header so that the response can be linked to
  ## it
  SideChannelMsgHeader = array[0..3, uint8]

  SideChannelResponsePayload = object
    
proc processEscapeSequence*(client: Client) {.async.} =
  let stream = newAsyncSocketStream(client.sock)
  try:
    let d = await stream.readMData()
    echo d
  except:
    await stream.writeMData("invalid".md)
  
