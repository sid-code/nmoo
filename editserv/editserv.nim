import asyncdispatch, asynchttpserver
import strutils

import types, objects, verbs, scripting

const
  cmSource = "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.7.0/codemirror.min.js"
  cmCSS = "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.7.0/codemirror.css"
  cmScheme = "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.7.0/mode/scheme/scheme.min.js"
  cmVim = "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.7.0/keymap/vim.min.js"
  cmClient = staticRead("editserv/client.js")
  templ = """
<html>
  <body>
    <form onsubmit="this."
  </body>
  <script src="$#"></script>
  <script src="$#"></script>
  <script src="$#"></script>
  <script>$#</script>
  <link rel="stylesheet" href="$#" />
</html>
""".format(cmSource, cmScheme, cmVim, cmClient, cmCSS)

type
  EditServer = ref object
    editor: MObject
    server: AsyncHttpServer

proc safeSetCode(verb: MVerb, newCode: string): tuple[success: bool, msg: string] =
  try:
    verb.setCode(newCode)
    return (true, "Success! This page will now self-destruct.")
  except MParseError:
    return (false, "Parse error: " & getCurrentExceptionMsg())
  except MCompileError:
    return (false, "Compile error: " & getCurrentExceptionMsg())

proc newEditServer*(editor: MObject): EditServer =
  EditServer(editor: editor, server: newAsyncHttpServer())

proc serve*(es: EditServer, port: Port, address = ""): Future[void] {.async.} =

  let editor = es.editor
  let server = es.server
  let world = editor.world

  proc cb(req: Request) {.async.} =
    let opts = req.url.path.substr(1).split("/")
    if opts.len != 2:
      await req.respond(Http404, "Not found.")
    else:
      if opts[0] == "e":
        let id = opts[1]
        let propName = "edit-" & id
        let verbToEditd = editor.getPropVal(propName)
        if verbToEditd.isType(dList):
          let verbToEdit = verbToEditd.listVal
          let objOn = verbToEdit[0]
          if objOn.isType(dObj):
            let obj = world.dataToObj(objOn)
            if isNil(obj):
              await req.respond(Http500, "Object didn't exist.")
            else:
              let vnamed = verbToEdit[1]
              if isType(vnamed, dStr):
                let vname = vnamed.strVal
                let verb = obj.getVerb(vname)
                if isNil(verb):
                  await req.respond(Http500, "Verb not found.")
                else:
                  if req.reqMethod == "get":
                    let data = templ.replace("<<<CODE>>>", escape(verb.code))
                    await req.respond(Http200, data)
                  elif req.reqMethod == "post":
                    let newCode = req.body
                    let (success, msg) = verb.safeSetCode(newCode)
                    if success:
                      await req.respond(Http200, msg)
                      discard editor.delProp(editor.getProp(propName))
                    else:
                      await req.respond(Http500, msg)
              else:
                await req.respond(Http500, "Didn't get a string.")
          else:
            await req.respond(Http500, "Didn't get an object.")
        else:
          await req.respond(Http404, "ID not found.")
      else:
        await req.respond(Http404, "Not found.")

  await server.serve(Port(8080), cb, address)
