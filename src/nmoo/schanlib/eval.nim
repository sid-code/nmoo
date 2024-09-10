import asyncnet
import asyncdispatch
import std/strutils
import std/parseopt

import schan
import ../server
import ../types
import ../bytedump
import ../scripting # for parser

proc parse(str: string): MData =
  var parser = newParser(str)
  return parser.parseFull()

proc parseCliArgs(): tuple[address: string, port: uint16] =
  var
    addressSet = false
    portSet = false

    
  proc checkPort(port: int): uint16 =
    if port < int(low(uint16)) or port > int(high(uint16)):
      quit("invalid --port value: $#.\nIt must be between $# and $#." %
            [$port, $low(uint16), $high(uint16)])
    return uint16(port)

  for kind, key, val in parseopt.getopt():
    case kind:
      of cmdEnd: break
      of cmdShortOption, cmdLongOption:
        if key == "address":
          result.address = val
          addressSet = true
        elif key == "port":
          result.port = checkPort(val.parseInt)
          portSet = true
        else:
          quit("Invalid option: " & key)
      of cmdArgument:
        quit("Unexpected argument: " & key)

  if not addressSet:
    quit("missing --address parameter")
  if not portSet:
    quit("missing --port parameter")

proc main {.async.} =
  let (address, port) = parseCliArgs()

  let sock = newAsyncSocket()
  await sock.connect(address, Port(port))

  let scc = newAsyncSideChannelClient(sock)

  # This is so that we can receive responses
  asyncCheck scc.startReader()

  let prog = parse(stdin.readAll())
  let result = await scc.request(prog)
  if result.isType dStr:
    echo result.strVal
  else:
    echo $result

when isMainModule:
  waitFor main()
