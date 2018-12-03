import asyncnet
import asyncdispatch

import schan
import ../server
import ../types
import ../bytedump
import ../scripting # for parser

proc parse(str: string): MData =
  var parser = newParser(str)
  return parser.parseFull()

proc main {.async.} =
  let sock = newAsyncSocket()
  await sock.connect("0.0.0.0", Port(4444))

  let scc = newAsyncSideChannelClient(sock)

  # This is so that we can receive responses
  asyncCheck scc.startReader()

  let prog = parse(stdin.readAll())
  echo $(await scc.request(prog))

waitFor main()
