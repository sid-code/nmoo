# EXPERIMENTAL
#
# Auxiliary verb editing server (http)


import os
import strutils
import sequtils
import strtabs
import logging
import json
import asynchttpserver
import asyncdispatch

import types
import objects
import verbs
import tasks
import server

const assetsDir = "assets"

var editserver = newAsyncHttpServer()
var editservObj: MObject = nil

proc getMIMEType(filename: string): string =
  if filename.endsWith(".js"):
    return "text/javascript"
  elif filename.endsWith(".css"):
    return "text/css"
  elif filename.endsWith(".html"):
    return "text/html"
  elif filename.endsWith(".ico"):
    return "image/x-icon"
  else:
    return "text/plain"

proc checkRequirements(world: World): MData =
  let vobj = world.verbObj

  let editservObjd = vobj.getPropVal("editserv")
  if not editservObjd.istype(dObj):
    return E_PROPNF.md("#0.editserv does not exist or isn't an object.")

  editservObj = world.byId(editservObjd.objVal)

  let checkTokenVerb = editservObj.getVerb("check-access-token")
  if isNil(checkTokenVerb):
    return E_VERBNF.md("#0.editserv is missing the required 'check-access-token' verb.")

  return editServObjd

proc checkAccessToken(world: World, token: string): MData =
  if isNil(editservObj):
    return E_TYPE.md("Unable to find edit server object.")

  let ctTask = editservObj.verbcall("check-access-token", world.verbObj, world.verbObj, @[token.md])
  if isNil(ctTask):
    return E_INTERNAL.md("Unable to call #" & $editservObj.getID() & ":check-access-token.")

  let tr = ctTask.run()
  case tr.typ:
    of trFinish:
      let res = tr.res
      if not res.isType(dObj):
        return E_PERM.md("Invalid access token.")

      return res
    of trSuspend:
      return E_INTERNAL.md("check-access-token task suspended itself.")
    of trError:
      return E_INTERNAL.md("check-access-token task resulted in an error:\n" & $tr.err)
    of trTooLong:
      return E_INTERNAL.md("check-access-token task took too long.")

proc genObjectJSON(obj, requester: MObject): string =
  let objJSON = newJObject()
  let verbsJSON = newJObject()
  for idx, verb in obj.verbs:
    let verbJSON = newJObject()
    verbJSON["names"] = newJString(verb.names)
    if requester.canRead(verb):
      verbJSON["code"] = newJString(verb.code)

    verbsJSON[$idx] = verbJSON

  # this should be fine because every object is guaranteed to have SOME name
  objJSON["name"] = newJString(obj.getPropVal("name").strVal)
  objJSON["verbs"] = verbsJSON

  return $objJSON

proc processQuery(queryStr: string): StringTableRef =
  var params = newStringTable(modeCaseInsensitive)
  let parts = queryStr.split("&").mapIt(it.split("="))

  for part in parts:
    if part.len != 2:
      return nil

    params[part[0]] = part[1]

  return params

proc internalError(req: Request, respText: string) {.async.} =
  await req.respond(Http500, respText)

proc badRequest(req: Request, respText: string) {.async.} =
  await req.respond(Http400, respText)

proc accessDenied(req: Request, respText: string) {.async.} =
  await req.respond(Http403, respText)

proc codeError(req: Request, respText: string) {.async.} =
  await req.respond(Http400, respText)

# either (true, <object being accessed>, <person authenticated>)
# or (false, nil, nil)
proc authenticateObjectAccess(req: Request, world: World): Future[tuple[success: bool, who, obj: MObject]] {.async.} =
  result.success = false

  let params = processQuery(req.url.query)

  if isNil(params):
    await badRequest(req, "malformed query")
    return

  if not params.hasKey("token"):
    await badRequest(req, "missing access token")
    return

  if not params.hasKey("objid"):
    return

  if not params.hasKey("objid"):
    await badRequest(req, "missing object id")
    return

  let token = params["token"]
  let objidstr = params["objid"]
  var objid: int
  var badobjid = false

  try:
    objid = parseUInt(objidstr).int
  except ValueError:
    # This has to be done, can't await from within the except clause
    badobjid = true

  # see previous comment
  if badobjid:
    await badRequest(req, "invalid object id #" & objidstr)
    return

  let checkResult = checkAccessToken(world, token)
  if checkResult.isType(dErr):
    if checkResult.errVal == E_PERM:
      await req.respond(Http403, "access denied, invalid token")
    else:
      await req.respond(Http400, $checkResult)
    return

  let who = world.byID(checkResult.objVal)
  if isNil(who):
    await internalError(req, "check-access-token returned a bad object (" & $checkResult & ")")
    return

  let obj = world.byID(objid.ObjID)
  if obj.isNil:
    await badRequest(req, "could not find object with id #" & objidstr)
    return

  result.success = true
  result.who = who
  result.obj = obj

proc authenticateVerbAccess(req: Request, world: World): Future[tuple[success: bool, who: MObject, verb: MVerb]] {.async.} =
  result.success = false

  let params = processQuery(req.url.query)

  let (success, who, obj) = await authenticateObjectAccess(req, world)
  if not success:
    return

  result.who = who

  if not params.hasKey("verbid"):
    await badRequest(req, "missing verb id")
    return

  let verbidstr = params["verbid"]
  var verbid: int
  var badverbid = false
  try:
    verbid = parseUInt(verbidstr).int
  except ValueError:
    badverbid = true

  if badverbid or verbid >= obj.verbs.len:
    await badRequest(req, "invalid verb id " & verbidstr)
    return

  let verb = obj.verbs[verbid]

  result.success = true
  result.verb = verb


proc handleObjdataQuery(req: Request, world: World) {.async.} =
  let (success, who, obj) = await authenticateObjectAccess(req, world)
  if not success:
    return

  if not who.canRead(obj):
    await accessDenied(req, "you are not authorized to read #" & $obj.getID())
    return

  let headers = newHttpHeaders({"Content-Type": "application/json"})
  await req.respond(Http200, genObjectJSON(obj, requester = who), headers)

proc handleCodeUpdate(req: Request, world: World) {.async.} =
  let (success, who, verb) = await authenticateVerbAccess(req, world)
  if not success:
    return

  if not who.canWrite(verb):
    await accessDenied(req, "you are not authorized to write that verb")
    return

  let newCode = req.body
  let oldCode = verb.code

  var err = false
  var msg: string = nil

  try:
    verb.setCode(newCode)
  except MParseError:
    msg = "Parse error: " & getCurrentExceptionMsg()
    err = true
  except MCompileError:
    msg = getCurrentExceptionMsg()
    err = true

  if err:
    error msg
    await codeError(req, msg)
    return

  # TODO: highly temporary, just for safety purposes
  echo "OLD CODE FOR ", verb.names
  echo oldCode

proc sendStaticFile(req: Request, file: string) {.async.} =
  let realFile = assetsDir / file
  if existsFile(realFile):
    await req.respond(Http200, readFile(realFile), newHttpHeaders({"Content-Type": getMimeType(file)}))
  else:
    await req.respond(Http404, "not found", newHttpHeaders({"Content-Type": "text/plain"}))

proc startEditServer*(world: World, p: Port) {.async.} =
  let check = checkRequirements(world)
  if check.isType(dErr):
    error "Unable to start edit server due to error:"
    error check
    return

  proc cb(req: Request) {.async.} =
    var parts = req.url.path.split("/")[1..^1]
    if parts[^1] == "":
      discard parts.pop()

    if req.reqmethod == HttpGet:
      discard
      if parts.len == 0:
        await sendStaticFile(req, "index.html")
      else:
        let service = parts[0]
        if service == "objdata":
          await handleObjdataQuery(req, world)
        else:
          await sendStaticFile(req, service)
    elif req.reqMethod == HttpPost:
      if parts.len == 1:
        let service = parts[0]
        if service == "codeupdate":
          await handleCodeUpdate(req, world)
        else:
          await req.respond(Http404, "oh no")
      else:
        await req.respond(Http404, "oh no")
    else:
      await req.respond(Http404, "oh no")

  info "Starting edit server (http):  port=", p.int
  await editserver.serve(p, cb)

