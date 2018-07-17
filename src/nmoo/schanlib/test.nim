import asyncnet
import asyncdispatch

import schan
import nmoo/server
import nmoo/types
import nmoo/bytedump
import nmoo/scripting # for parser

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
  discard await scc.request(prog)

waitFor main()
