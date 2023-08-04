import asyncnet
import asyncdispatch
import asynchttpserver
import options
import strutils
import logging
import tables

import ../server
import ../types
import ../scripting
import ../schanlib/schan
import ../logfmt

type
  MWebServer = ref object
    host: string
    port: Port
    schost: string
    scport: Port
    srv: AsyncHttpServer
    sc: AsyncSideChannelClient

proc newMWebServer(host: string, port: Port, schost: string, scport: Port): MWebServer =
  new result
  result.host = host
  result.port = port
  result.schost = schost
  result.scport = scport
  result.srv = newAsyncHttpServer()

proc parseRaw(str: string): MData =
  var parser = newParser(str)
  return parser.parseList()

proc md(headers: HttpHeaders): MData =
  result = initTable[MData, MData]().md
  for k, v in headers:
    result.tableVal[k.md] = v.md

proc extractHttpCode(coded: MData): Option[HttpCode] =
  if coded.dtype == dInt:
    return some(HttpCode(coded.intVal))

  return none[HttpCode]()

proc extractHttpHeaders(headersd: MData): Option[HttpHeaders] =
  ## Extract headers from headersd, which should be a table of string
  ## or symbol keys and string values. Returns none if plist is
  ## malformed

  if not headersd.isType(dTable):
    return none[HttpHeaders]()

  var headersObj = newHttpHeaders()

  for named, valued in pairs(headersd.tableVal):
    if not (named.isType(dStr) or named.isType(dSym) and valued.isType(dStr)):
      return none[HttpHeaders]()

    let name = if named.isType(dStr): named.strVal else: named.symVal
    let value = valued.strVal

    headersObj[name] = value

  return some(headersObj)
   
# Request format:
# (HTTPVERB URL ((HEADER1 VALUE1) (HEADER2 VALUE2) ...) [BODY])
# Response format:
# (CODE HEADERS BODY)
proc serve(mws: MWebServer) {.async.} =

  proc cb(req: Request) {.async, gcsafe.} =
    var headers = req.headers
    headers["path"] = req.url.path
    headers["scheme"] = req.url.scheme

    let headersd = headers.md

    var path: string
    if len(req.url.query) > 0:
      path = req.url.path & "?" & req.url.query
    else:
      path = req.url.path

    info "REQUEST FOR: ", path
    var data = @[tolower($req.reqMethod).mds, path.md, headersd]
    if req.reqMethod == HttpPOST:
      data.add(req.body.md)
    let code = @["verbcall".mds, 0.ObjID.md, "handle-http-request".md, @["quote".mds, data.md].md].md

    when defined(debug): debug "Serving a request."
    let responsed = await mws.sc.request(code)
    when defined(debug): debug "Got a response."
    if responsed.istype(dErr):
      await req.respond(
        Http500,
        "Internal server error: $#".format(responsed))
      return

    elif not responsed.istype(dList):
      await req.respond(
        Http502,
        "server gave us $# ($#), expected list (CODE HEADERS BODY)".format(responsed, responsed.dtype))
      return

    let response = responsed.listVal
    if len(response) != 3:
      await req.respond(
        Http502,
        "server gave us a list of length $#, expected length 3".format(len(response)))
      return

    let returnCode = extractHttpCode(response[0])
    if not returnCode.isSome():
      await req.respond(
        Http502,
        "server gave us an invalid http code: $#".format(response[0]))
      return

    let respHeaders = extractHttpHeaders(response[1])
    if not respHeaders.isSome():
      await req.respond(
        Http502,
        "server gave us malformed http headers: $#".format(response[1]))
      return

    let bodyd = response[2]
    if not bodyd.isType(dStr):
      await req.respond(
        Http502,
        "response body was of type $#, not str".format(bodyd.dtype))
      return
    let body = bodyd.strVal

    await req.respond(returnCode.get(), body, headers=respHeaders.get())

  let sock = newAsyncSocket()
  await sock.connect(mws.schost, mws.scport)

  mws.sc = newAsyncSideChannelClient(sock)
  asyncCheck mws.sc.startReader()

  await mws.srv.serve(mws.port, cb)

when isMainModule:
  let clog = newConsoleLogger(fmtStr=MLogFmtStr)
  addHandler(clog)

  let mws = newMWebServer(
    # Host to serve from
    host="0.0.0.0",
    port=Port(8081),

    # nmoo server
    schost="0.0.0.0",
    scport=Port(4444),
  )

  info "starting server"

  waitFor mws.serve()
