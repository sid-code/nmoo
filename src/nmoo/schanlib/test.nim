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

  echo await scc.request(parse(""" "hi" """))
  echo await scc.request(parse(""" (let ((x 5)) (+ x 1)) """))
  echo await scc.request(parse(""" (cat "Should be 5: " (call-cc (lambda (x) (x 5)))) """))
  echo await scc.request(parse(""" (define-syntax lol (lambda (code) `(do (echo "running code!") ,(get code 1)))) (lol 4) """))


waitFor main()
