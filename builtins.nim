# Here are all of the builtin functions that verbs can call

import types, objects, verbs, scripting, persist, compile, tasks
import strutils, tables, sequtils

proc strToType(str: string): tuple[b: bool, t: MDataType] =
  case str.toLower():
    of "int": return (true, dInt)
    of "float": return (true, dFloat)
    of "str": return (true, dStr)
    of "sym": return (true, dSym)
    of "obj": return (true, dObj)
    of "list": return (true, dList)
    of "nil": return (true, dNil)
    else: return (false, dInt)

template checkForError(value: MData) =
  if value.isType(dErr):
    return value

template runtimeError(error: MError, message: string) =
  return error.md("line $#, col $#: $#" % [$pos.line, $pos.col, message])

template checkType(value: MData, expected: MDataType, ifnot: MError = E_ARGS)
          {.immediate.} =
  if not value.isType(expected):
    runtimeError(ifnot,
      "expected argument of type " & $expected & " instead got " & $value.dType)

template extractObject(objd: MData): MObject {.immediate.} =
  checkType(objd, dObj)
  let obj = world.dataToObj(objd)
  if obj == nil:
    runtimeError(E_ARGS, "invalid object " & $objd)

  obj

template checkOwn(obj, what: MObject) =
  if not obj.owns(what):
    runtimeError(E_PERM, obj.toObjStr() & " doesn't own " & what.toObjStr())

template checkOwn(obj: MObject, prop: MProperty) =
  if not obj.owns(prop):
    runtimeError(E_PERM, obj.toObjStr() & " doesn't own " & prop.name)

template checkOwn(obj: MObject, verb: MVerb) =
  if not obj.owns(verb):
    runtimeError(E_PERM, obj.toObjStr() & " doesn't own " & verb.name)

template checkRead(obj, what: MObject) =
  if not obj.canRead(what):
    runtimeError(E_PERM, obj.toObjStr() & " cannot read " & what.toObjStr())
template checkWrite(obj, what: MObject) =
  if not obj.canWrite(what):
    runtimeError(E_PERM, obj.toObjStr() & " cannot write " & what.toObjStr())
template checkRead(obj: MObject, what: MProperty) =
  if not obj.canRead(what):
    runtimeError(E_PERM, obj.toObjStr() & " cannot read property: " & what.name)
template checkWrite(obj: MObject, what: MProperty) =
  if not obj.canWrite(what):
    runtimeError(E_PERM, obj.toObjStr() & " cannot write property: " & what.name)
template checkRead(obj: MObject, what: MVerb) =
  if not obj.canRead(what):
    runtimeError(E_PERM, obj.toObjStr() & " cannot read verb: " & what.names)
template checkWrite(obj: MObject, what: MVerb) =
  if not obj.canWrite(what):
    runtimeError(E_PERM, obj.toObjStr() & " cannot write verb: " & what.names)
template checkExecute(obj: MObject, what: MVerb) =
  if not obj.canExecute(verb):
    runtimeError(E_PERM, obj.toObjStr() & " cannot execute verb: " & what.names)

proc genCall(fun: MData, args: seq[MData]): MData =
  var resList: seq[MData]
  if fun.isType(dSym):
    resList = @[fun]
  else:
    resList = @["call".mds, fun]

  return (resList & args).md

proc toEchoString*(x: MData): string =
  if x.isType(dStr):
    x.strVal
  else:
    x.toCodeStr()

defBuiltin "echo":
  var
    newArgs: seq[MData] = @[]
    sendstr = ""
  for arg in args:
    let res = evalD(arg)
    sendstr &= res.toEchoString()
    newArgs.add(res)
  caller.send(sendstr)
  return newArgs.md

defBuiltin "do":
  var newArgs: seq[MData] = @[]
  for arg in args:
    let res = evalD(arg)
    newArgs.add(res)

  if newArgs.len > 0:
    return newArgs[^1]
  else:
    return @[].md

defBuiltin "eval":
  if args.len != 1:
    runtimeError(E_ARGS, "eval takes one argument")

  let argd = evalD(args[0])
  checkType(argd, dStr)
  var evalStr = argd.strVal
  if evalStr[0] != '(':
    evalStr = '(' & evalStr & ')'

  try:
    let compiler = compileCode(evalStr)
    world.addTask(owner, caller, symtable, compiler.render, nil)
  except MParseError:
    let msg = getCurrentExceptionMsg()
    runtimeError(E_PARSE, "code failed to parse: $1" % msg)
  except MCompileError:
    let msg = getCurrentExceptionMsg()
    runtimeError(E_PARSE, "compile error: $1" % msg)

defBuiltin "slet": # single let
  if args.len != 2:
    runtimeError(E_ARGS, "slet expects two arguments")

  let first = args[0]
  checkType(first, dList)
  if first.listVal.len != 2:
    runtimeError(E_ARGS, "slet's first argument is a tuple (symbol value-to-bind)")

  let newStmt = @[ "let".mds, @[first].md, args[1] ].md
  return evalD(newStmt)


defBuiltin "let":
  # First argument: list of pairs
  # Second argument: expression to evaluate with the symbol table
  if args.len != 2:
    return E_ARGS.md

  checkType(args[0], dList)

  var newSymtable = symtable

  let asmtList = args[0].listVal
  for asmt in asmtList:
    if not asmt.isType(dList):
      runtimeError(E_ARGS, "let takes a list of assignments")
    let pair = asmt.listVal
    if not pair.len == 2:
      runtimeError(E_ARGS, "each assignment in the list must be a tuple (symbol value-to-bind)")
    checkType(pair[0], dSym)

    let
      symName = pair[0].symVal
      setVal = evalD(pair[1], st = newSymtable)

    newSymtable[symName] = setVal

  return evalD(args[1], st = newSymtable)

defBuiltin "cond":
  for arg in args:
    checkType(arg, dList)
    let larg = arg.listVal
    if larg.len == 0 or larg.len > 2:
      runtimeError(E_ARGS, "each argument to cond must be of length 1 or 2")

    if larg.len == 1:
      return larg[0]
    else:
      let condVal = evalD(larg[0])
      if condVal.truthy:
        return evalD(larg[1])
      else:
        continue

  return E_BADCOND.md

proc extractInfo(prop: MProperty): MData =
  var res: seq[MData] = @[]
  res.add(prop.owner.md)

  var perms = ""
  if prop.pubRead: perms &= "r"
  if prop.pubWrite: perms &= "w"
  if prop.ownerIsParent: perms &= "c"

  res.add(perms.md)
  return res.md

proc extractInfo(verb: MVerb): MData =
  var res: seq[MData] = @[]
  res.add(verb.owner.md)

  var perms = ""
  if verb.pubRead: perms &= "r"
  if verb.pubWrite: perms &= "w"
  if verb.pubExec: perms &= "x"

  res.add(perms.md)
  res.add(verb.names.md)
  return res.md

proc extractArgs(verb: MVerb): MData =
  var res: seq[MData] = @[]
  res.add(objSpecToStr(verb.doSpec).md)
  res.add(prepSpecToStr(verb.prepSpec).md)
  res.add(objSpecToStr(verb.ioSpec).md)

  return res.md

type
  PropInfo = tuple[owner: MObject, perms: string, newName: string]
  VerbInfo = tuple[owner: MObject, perms: string, newName: string]
  VerbArgs = tuple[doSpec: ObjSpec, prepSpec: PrepType, ioSpec: ObjSpec]

template propInfoFromInput(info: seq[MData]): PropInfo =
  if info.len != 2 and info.len != 3:
    runtimeError(E_ARGS, "property info must be a list of size 2 or 3")

  var res: PropInfo

  let ownerd = evalD(info[0])
  let ownero = extractObject(ownerd)
  res.owner = ownero

  let permsd = evalD(info[1])
  checkType(permsd, dStr)
  let perms = permsd.strVal
  res.perms = perms

  if info.len == 3:
    let newNamed = evalD(info[2])
    checkType(newNamed, dStr)
    let newName = newNamed.strVal
    res.newName = newName

  res

template verbInfoFromInput(info: seq[MData]): VerbInfo =
  if info.len != 2 and info.len != 3:
    runtimeError(E_ARGS, "verb info must be a list of size 2 or 3")

  var res: VerbInfo

  let ownerd = evalD(info[0])
  let ownero = extractObject(ownerd)
  res.owner = ownero

  let permsd = evalD(info[1])
  checkType(permsd, dStr)
  let perms = permsd.strVal
  res.perms = perms

  if info.len == 3:
    let newNamed = evalD(info[2])
    checkType(newNamed, dStr)
    let newName = newNamed.strVal
    res.newName = newName

  res

template objSpecFromData(ospd: MData): ObjSpec =
  let specd = evalD(ospd)
  checkType(specd, dStr)
  let
    str = specd.strVal
    (success, spec) = strToObjSpec(str)

  if not success:
    runtimeError(E_ARGS, "invalid object spec '$1'" % str)

  spec

template prepSpecFromData(pspd: MData): PrepType =
  let specd = evalD(pspd)
  checkType(specd, dStr)
  let
    str = specd.strVal
    (success, spec) = strToPrepSpec(str)

  if not success:
    runtimeError(E_ARGS, "invalid preposition spec '$1'" % str)

  spec

template verbArgsFromInput(info: seq[MData]): VerbArgs =
  if info.len != 3:
    runtimeError(E_ARGS, "verb args must be a list of size 3")

  var result: VerbArgs
  result.doSpec = objSpecFromData(info[0])
  result.prepSpec = prepSpecFromData(info[1])
  result.ioSpec = objSpecFromData(info[2])

  result

proc setInfo(prop: MProperty, info: PropInfo) =
  prop.owner = info.owner
  prop.pubRead = "r" in info.perms
  prop.pubWrite = "w" in info.perms
  prop.ownerIsParent = "c" in info.perms

  if info.newName != nil:
    prop.name = info.newName

proc setInfo(verb: MVerb, info: VerbInfo) =
  verb.owner = info.owner
  verb.pubRead = "r" in info.perms
  verb.pubWrite = "w" in info.perms
  verb.pubExec = "x" in info.perms

  if info.newName != nil:
    verb.names = info.newName

proc setArgs(verb: MVerb, args: VerbArgs) =
  verb.doSpec = args.doSpec
  verb.prepSpec = args.prepSpec
  verb.ioSpec = args.ioSpec

template getPropOn(objd, propd: MData, die = true): tuple[o: Mobject, p: MProperty] =
  let objd2 = evalD(objd)
  let obj = extractObject(objd2)

  let propd2 = evalD(propd)
  checkType(propd2, dStr)
  let
    propName = propd.strVal
    propObj = obj.getProp(propName)

  if propObj == nil:
    if die:
      runtimeError(E_PROPNF, "property $1 not found on $2" % [propName, $obj.toObjStr()])
    else:
      return nilD

  (obj, propObj)

template getVerbOn(objd, verbdescd: MData, die = true): tuple[o: MObject, v: MVerb] =
  let objd2 = evalD(objd)
  let obj = extractObject(objd2)

  let verbdescd2 = evalD(verbdescd)
  checkType(verbdescd2, dStr)
  let verbdesc = verbdescd2.strVal

  let verb = obj.getVerb(verbdesc)
  if verb == nil:
    if die:
      runtimeError(E_VERBNF, "verb $1 not found on $2" % [verbdesc, obj.toObjStr()])
    else:
      return nilD

  (obj, verb)

# (getprop what propname)
defBuiltin "getprop":
  if args.len != 2:
    runtimeError(E_ARGS, "getprop takes 2 arguments")

  let (obj, propObj) = getPropOn(args[0], args[1])
  discard obj

  checkRead(owner, propObj)

  return propObj.val

# (setprop what propname newprop)
defBuiltin "setprop":
  if args.len != 3:
    runtimeError(E_ARGS, "setprop takes 3 arguments")

  let objd = evalD(args[0])
  let obj = extractObject(objd)

  let
    propd = evalD(args[1])
    newVal = evalD(args[2])

  checkType(propd, dStr)

  let
    prop = propd.strVal
    oldProp = obj.getProp(prop)

  if oldProp == nil:
    owner.checkWrite(obj)
    for tup in obj.setPropRec(prop, newVal):
      let (moddedObj, addedProp) = tup
      # If the property didn't exist before, we want its owner to be us,
      # not the object that it belongs to.
      addedProp.owner = owner
      world.persist(moddedObj)

  else:
    var propObj = obj.getProp(prop)
    owner.checkWrite(propObj)
    propObj.val = newVal
    world.persist(obj)

  return newVal

# (delprop what propname)
# TODO: write a test for this!
defBuiltin "delprop":
  if args.len != 2:
    runtimeError(E_ARGS, "delprop takes 2 arguments")

  let (obj, prop) = getPropOn(args[0], args[1])

  if prop.inherited:
    runtimeError(E_PROPNF, "$1 does not define a property $2" % [obj.toObjStr, $args[1]])

  for moddedObj, deletedProp in obj.delPropRec(prop).items:
    discard deletedProp
    world.persist(moddedObj)

  return obj.md

# (getpropinfo what propname)
# result is (owner perms)
# perms is [rwc]
defBuiltin "getpropinfo":
  if args.len != 2:
    runtimeError(E_ARGS, "getpropinfo takes 2 arguments")

  let (obj, propObj) = getPropOn(args[0], args[1])
  discard obj

  checkRead(owner, propObj)

  return extractInfo(propObj)


# (setpropinfo what propname newinfo)
# newinfo is like result from getpropinfo but can
# optionally have a third element specifying a new
# name for the property
defBuiltin "setpropinfo":
  if args.len != 3:
    runtimeError(E_ARGS, "setpropinfo takes 3 arguments")

  let (obj, propObj) = getPropOn(args[0], args[1])

  checkWrite(owner, propObj)

  # validate the property info
  let propinfod = evalD(args[2])
  checkType(propinfod, dList)
  let
    propinfo = propinfod.listVal
    info = propInfoFromInput(propinfo)

  propObj.setInfo(info)
  world.persist(obj)


  return args[0]

# (props obj)
# returns a list of obj's properties
defBuiltin "props":
  if args.len != 1:
    runtimeError(E_ARGS, "props takes 1 argument")

  let objd = evalD(args[0])
  let obj = extractObject(objd)

  checkRead(owner, obj)

  var res: seq[MData] = @[]
  for p in obj.props:
    res.add(p.name.md)

  return res.md

# (verbs obj)
# returns a list of obj's verbs' names
defBuiltin "verbs":
  if args.len != 1:
    runtimeError(E_ARGS, "verbs takes 1 argument")

  let objd = evalD(args[0])
  let obj = extractObject(objd)

  checkRead(owner, obj)

  var res: seq[MData] = @[]
  for v in obj.allVerbs():
    res.add(v.names.md)

  return res.md


# (getverbinfo obj verb-desc)
defBuiltin "getverbinfo":
  if args.len != 2:
    runtimeError(E_ARGS, "getverbinfo takes 2 arguments")

  let (obj, verb) = getVerbOn(args[0], args[1])
  discard obj
  checkRead(owner, verb)

  return extractInfo(verb)

# (setverbinfo obj verb-desc newinfo)
defBuiltin "setverbinfo":
  if args.len != 3:
    runtimeError(E_ARGS, "setverbinfo takes 3 arguments")

  let (obj, verb) = getVerbOn(args[0], args[1])
  checkWrite(owner, verb)

  let infod = evalD(args[2])
  checkType(infod, dList)
  let info = verbInfoFromInput(infod.listVal)

  verb.setInfo(info)
  world.persist(obj)
  return args[0]

# (getverbargs obj verb-desc)
defBuiltin "getverbargs":
  if args.len != 2:
    runtimeError(E_ARGS, "getverbargs takes 2 arguments")

  let (obj, verb) = getVerbOn(args[0], args[1])
  discard obj
  checkRead(owner, verb)

  return extractArgs(verb)

# (setverbargs obj verb-desc (objspec prepspec objspec))
defBuiltin "setverbargs":
  if args.len != 3:
    runtimeError(E_ARGS, "setverbargs takes 3 arguments")

  let (obj, verb) = getVerbOn(args[0], args[1])
  checkWrite(owner, verb)

  let argsInfod = evalD(args[2])
  checkType(argsInfod, dList)

  let argsInfo = verbArgsFromInput(argsInfod.listVal)
  verb.setArgs(argsInfo)
  world.persist(obj)

  return args[0]

# (addverb obj names)
defBuiltin "addverb":
  if args.len != 2:
    runtimeError(E_ARGS, "addverb takes 2 arguments")

  let objd = evalD(args[0])
  let obj = extractObject(objd)

  let namesd = evalD(args[1])
  checkType(namesd, dStr)
  let names = namesd.strVal

  var verb = newVerb(
    names = names,
    owner = caller,
  )

  verb.setCode("")

  discard obj.addVerb(verb)
  world.persist(obj)

  # The following is commented out because verbs are now checked
  # recursively and no longer need to be added recursively.

  # for tup in obj.addVerbRec(verb):
  #   let (moddedObj, addedVerb) = tup
  #   discard addedVerb
  #   world.persist(moddedObj)

  return objd

# (delverb obj verb)
defBuiltin "delverb":
  if args.len != 2:
    runtimeError(E_ARGS, "delverb takes 2 arguments")

  let (obj, verb) = getVerbOn(args[0], args[1])

  if verb == nil or verb.inherited:
    runtimeError(E_VERBNF, "$1 does not define a verb $2" % [obj.toObjStr, $args[1]])

  discard obj.delVerb(verb)
  world.persist(obj)

  # See "addverb" for why the following is commented out

  # for tup in obj.delVerbRec(verb):
  #   let (moddedObj, deletedVerb) = tup
  #   discard deletedVerb
  #   world.persist(moddedObj)

  return obj.md


# (setverbcode obj verb-desc newcode)
defBuiltin "setverbcode":
  if args.len != 3:
    runtimeError(E_ARGS, "setverbcode takes 3 arguments")

  let (obj, verb) = getVerbOn(args[0], args[1])
  checkWrite(owner, verb)

  let newCode = evalD(args[2])
  checkType(newCode, dStr)

  try:
    verb.setCode(newCode.strVal)
    world.persist(obj)
    return nilD
  except MParseError:
    let msg = getCurrentExceptionMsg()
    runtimeError(E_PARSE, "code failed to parse: $1" % msg)

defBuiltin "getverbcode":
  if args.len != 2:
    runtimeError(E_ARGS, "getverbcode takes 2 arguments")

  let (obj, verb) = getVerbOn(args[0], args[1])
  checkRead(owner, verb)

  return verb.code.md

# (move what dest)
defBuiltin "move":
  if args.len != 2:
    runtimeError(E_ARGS, "move takes 2 arguments")

  let
    whatd = evalD(args[0])
    destd = evalD(args[1])

  var
    what = extractObject(whatd)
    dest = extractObject(destd)

  checkOwn(owner, what)

  let whatlist = @[what.md]

  task.suspend()

  proc callback(innerTask: Task, acc: MData) =
    task.resume()
    if not acc.truthy:
      caller.send($E_NACC.md("moving $1 to $2 refused" % [what.toObjStr(), dest.toObjStr()]))

    # check for recursive move
    var conductor = dest

    while conductor != nil:
      if conductor == what:
        caller.send($E_RECMOVE.md("moving $1 to $2 is recursive" % [what.toObjStr(), dest.toObjStr()]))
      let loc = conductor.getLocation()
      if loc == conductor:
        break
      conductor = loc

    var moveSucceeded = what.moveTo(dest)

    if not moveSucceeded:
      caller.send($E_FMOVE.md("moving $1 to $2 failed (it could already be at $2)" %
            [what.toObjStr(), dest.toObjStr()]))

    let oldLoc = what.getLocation()

    proc persistOldLoc(task: Task, res: MData) = world.persist(oldLoc)
    proc persistDestAndWhat(task: Task, res: MData) =
      world.persist(dest)
      world.persist(what)

    if oldLoc != nil:
      if not oldLoc.verbCall("exitfunc", caller, whatlist, persistOldLoc):
        # If there was no verb, we still need to call the callback
        persistOldLoc(task, 1.md)

    if not dest.verbCall("enterfunc", caller, whatlist, persistDestAndWhat):
      # If there was no verb, we still need to call the callback
      persistDestAndWhat(task, 1.md)

  if not dest.verbCall("accept", caller, whatlist, callback):
    # If there was no verb, we still need to call the callback
    callback(task, 1.md)
  return what.md

# (create parent new-owner)
# creates a child of the object given
# owner is set to executor of code
#   (in the case of verbs, the owner of the verb)
#
# # TODO: write a test for this
defBuiltin "create":
  let alen = args.len
  if alen != 1 and alen != 2:
    runtimeError(E_ARGS, "create takes 1 or 2 arguments")

  let parent = extractObject(args[0])

  var newOwner: MObject
  if alen == 2:
    newOwner = extractObject(args[1])

    if newOwner != owner and not owner.isWizard():
      runtimeError(E_PERM, "non-wizards can only set themselves as the owner of objects")
  else:
    newOwner = owner

  if not parent.fertile and (owner.owns(parent) or owner.isWizard()):
    runtimeError(E_PERM, "$1 is not fertile" % [parent.toObjStr()])

  # TODO: Quotas

  let newObj = parent.createChild()
  world.add(newObj)
  newObj.setPropR("name", "child of $1" % [$parent.md])

  discard newObj.verbCall("initialize", owner, @[])

  newObj.owner = newOwner
  # TODO: some way to keep track of an object's owner objects

  world.persist(newObj)

  return newObj.md

# (recycle obj)
#
# Destroys obj
defBuiltin "recycle":
  if args.len != 1:
    runtimeError(E_ARGS, "recycle takes 1 argument")

  let obj = extractObject(args[0])
  checkOwn(owner, obj)

  let children = obj.children
  let parent = obj.parent
  for child in children:
    child.changeParent(parent)

  let nowhered = world.getGlobal("$nowhere")
  let nowhere = extractObject(nowhered)

  let (has, contents) = obj.getContents()
  if has:
    for contained in contents:
      let moveResult = builtinCall("move", @[contained.md, nowhered])
      checkForError(moveResult) # One of the rare times we need to check for errors

  proc callback(innerTask: Task = task, top: MData = nilD) =
    # Destroy the object
    discard obj.moveTo(nowhere)
    discard nowhere.removeFromContents(obj)
    world.delete(obj)
    world.persist()

  if not obj.verbCall("recycle", owner, @[], callback):
    callback()

defBuiltin "parent":
  if args.len != 1:
    runtimeError(E_ARGS, "parent takes 1 argument")

  let obj = extractObject(args[0])
  return obj.parent.md

defBuiltin "children":
  if args.len != 1:
    runtimeError(E_ARGS, "children takes 1 argument")

  let obj = extractObject(args[0])
  return obj.children.map(proc (x: MObject): MData = x.md).md

defBuiltin "setparent":
  if args.len != 2:
    runtimeError(E_ARGS, "setparent takes 2 arguments")

  var obj = extractObject(args[0])
  let newParent = extractObject(args[1])

  var conductor = newParent

  # TODO: explain this condition
  while conductor != conductor.parent:
    conductor = conductor.parent
    if conductor == obj:
      runtimeError(E_RECMOVE, "parenting cannot create cycles of length greater than 1!")

  obj.parent = newParent
  world.persist(obj)

  return newParent.md

# (try (what) (except) (finally))
defBuiltin "try":
  let alen = args.len
  if not (alen == 2 or alen == 3):
    runtimeError(E_ARGS, "try takes 2 or 3 arguments")

  let tryClause = evalD(args[0])

  # here we do manual error handling
  if tryClause.isType(dErr):
    var newSymtable = symtable
    newSymtable["error"] = tryClause.errMsg.md
    let exceptClause = evalD(args[1], st = newSymtable)
    return exceptClause

  if alen == 3:
    let finallyClause = evalD(args[2])
    return finallyClause

# (lambda (var) (expr-in-var))
defBuiltin "lambda":
  let alen = args.len
  if alen < 2:
    runtimeError(E_ARGS, "lambda takes 2 or more arguments")

  if alen == 2:
    return (@["lambda".mds] & args).md

  var newSymtable = symtable
  let boundld = args[0]
  checkType(boundld, dList)

  let
    boundl = boundld.listVal
    numBound = boundl.len

  if alen != 2 + numBound:
    runtimeError(E_ARGS, "lambda taking $1 arguments given $2 instead" %
            [$numBound, $(alen - 2)])

  let lambdaArgs = args[2 .. ^1]
  for idx, symd in boundl:
    checkType(symd, dSym)
    let sym = symd.symVal
    newSymtable[sym] = lambdaArgs[idx]

  let expression = args[1]
  return evalD(expression, st = newSymtable)

# (istype thingy typedesc)
# typedesc is a string:
#   int, float, str, sym, obj, list, err
defBuiltin "istype":
  if args.len != 2:
    runtimeError(E_ARGS, "istype takes 2 arguments")

  let
    what = args[0]
    typed = args[1]
  checkType(typed, dStr)

  let (valid, typedVal) = strToType(typed.strVal)
  if not valid:
    runtimeError(E_ARGS, "'$1' is not a valid data type" % typed.strVal)

  if what.isType(typedVal):
    return 1.md
  else:
    return 0.md

# (call lambda-or-builtin args)
# forces evaluation (is this a good way to do it?)
defBuiltin "call":
  if args.len < 1:
    runtimeError(E_ARGS, "call takes one or more argument (lambda then arguments)")

  let execd = args[0]
  if execd.isType(dSym):
    let stmt = (@[execd] & args[1 .. ^1]).md

    return evalD(stmt)
  elif execd.isType(dList):
    var lambl = execd.listVal
    if lambl.len != 3:
      runtimeError(E_ARGS, "call: invalid lambda")

    lambl = lambl & args[1 .. ^1]

    return evalD(lambl.md)
  else:
    runtimeError(E_ARGS, "call's first argument must be a builtin symbol or a lambda")

# (verbcall obj verb-desc (arg0 arg1 arg2 ...))
defBuiltin "verbcall":
  var args = args
  case args.len
    of 2:
      args.add(@[].md)
    of 3:
      discard
    else:
      runtimeError(E_ARGS, "verbcall takes 2 or 3 arguments")

  # the die = false prevents it from returning an error if the verb is not found.
  # If the verb is not found, this builtin returns nilD.
  let (obj, verb) = getVerbOn(args[0], args[1])

  let cargsd = evalD(args[2])
  checkType(cargsd, dList)
  let cargs = cargsd.listVal

  owner.checkExecute(verb)

  task.suspend()
  obj.verbCallRaw(verb, caller, cargs, proc(innerTask: Task, top: MData) =
    # throw away that nil (return of this proc)
    discard task.spop()
    task.spush(top)
    # TODO: increment current task's quotas by the amount of ticks innerTask used
    task.resume())
  return nilD

# (map func list)
defBuiltin "map":
  if args.len != 2:
    runtimeError(E_ARGS, "map takes 2 arguments")

  let
    lamb = evalD(args[0])
    listd = evalD(args[1])

  checkType(listd, dList)
  let list = listd.listVal
  var newList: seq[MData] = @[]

  for el in list:
    var singleResult: MData = evalD(genCall(lamb, @[el]))
    newList.add(singleResult)

  return newList.md

#(reduce start list func)
defBuiltin "reduce":
  let alen = args.len
  if alen != 2 and alen != 3:
    runtimeError(E_ARGS, "reduce takes 2 or 3 arguments")

  let
    lamb = args[0]
    listd = evalD(if alen == 2: args[1] else: args[2])

  checkType(listd, dList)
  var list = listD.listVal
  if list.len == 0:
    return nilD

  var start: MData
  if alen == 2:
    start = evalD(list[0])
    list = list[1 .. ^1]
  elif alen == 3:
    start = evalD(args[1])


  var res: MData = start
  for el in list:
    res = evalD(genCall(lamb, @[res, el]))

  return res

type
  BinFloatOp = proc(x: float, y: float): float
  BinIntOp = proc(x: int, y: int): int

template defArithmeticOperator(name: string, op: BinFloatOp) {.immediate.} =
  defBuiltin name:
    if args.len != 2:
      runtimeError(E_ARGS, "$1 takes 2 arguments" % name)

    var lhsd = evalD(args[0])
    var rhsd = evalD(args[1])

    var
      lhs: float
      rhs: float

    if lhsd.isType(dInt):
      lhs = lhsd.intVal.float
    elif lhsd.isType(dFloat):
      lhs = lhsd.floatVal
    else:
      runtimeError(E_ARGS, "invalid number " & $lhsd)
    if rhsd.isType(dInt):
      rhs = rhsd.intVal.float
    elif rhsd.isType(dFloat):
      rhs = rhsd.floatVal
    else:
      runtimeError(E_ARGS, "invalid number " & $rhsd)

    if lhsd.isType(dInt) and rhsd.isType(dInt):
      return op(lhs, rhs).int.md
    else:
      return op(lhs, rhs).md

defArithmeticOperator("+", `+`)
defArithmeticOperator("-", `-`)
defArithmeticOperator("*", `*`)
defArithmeticOperator("/", `/`)

# (= a b)
defBuiltin "=":
  if args.len != 2:
    runtimeError(E_ARGS, "= takes 2 arguments")

  let a = evalD(args[0])
  let b = evalD(args[1])

  if a == b:
    return 1.md
  else:
    return 0.md

# tostring function
# ($ obj) returns "#6", for example
defBuiltin "$":
  if args.len != 1:
    runtimeError(E_ARGS, "$ takes 1 argument")

  return args[0].toCodeStr().md

# (cat str1 str2 ...)
# (cat list1 list2 ...)
# concats any number of strings or lists in a list
# use (call cat (str-list/list-list)) to call it with a list
defBuiltin "cat":
  if args.len < 1:
    runtimeError(E_ARGS, "cat needs at least one string")

  let typ = args[0].dtype
  if typ == dStr:
    var total = ""
    for argd in args:
      let arg = evalD(argd)
      total &= arg.toEchoString()
    return total.md
  elif typ == dList:
    var total: seq[MData] = @[]
    for argd in args:
      let arg = evalD(argd)
      checkType(arg, dList)
      total.add(arg.listVal)
    return total.md
  else:
    runtimeError(E_ARGS, "cat only concatenates strings or lists")

# (head list)
defBuiltin "head":
  if args.len != 1:
    runtimeError(E_ARGS, "head takes 1 argument")

  let listd = evalD(args[0])

  if listd.isType(dList):
    let list = listd.listVal
    if list.len == 0:
      return @[].md

    return list[0]
  elif listd.isType(dStr):
    let str = listd.strVal
    if str.len == 0:
      return "".md

    return str[0 .. 0].md
  else:
    runtimeError(E_ARGS, "head takes either a string or a list")


# (tail list)
defBuiltin "tail":
  if args.len != 1:
    runtimeError(E_ARGS, "tail takes 1 argument")

  let listd = evalD(args[0])
  if listd.isType(dList):
    let list = listd.listVal
    if list.len == 0:
      return @[].md

    return list[1 .. ^1].md
  elif listd.isType(dStr):
    let str = listd.strVal
    if str.len == 0:
      return "".md

    return str[1 .. ^1].md
  else:
    runtimeError(E_ARGS, "tail takes either a string or a list")

# (len list)
defBuiltin "len":
  if args.len != 1:
    runtimeError(E_ARGS, "len takes 1 argument")

  let listd = evalD(args[0])
  if listd.isType(dList):
    let list = listd.listVal

    return list.len.md
  elif listd.isType(dStr):
    let str = listd.strVal

    return str.len.md
  else:
    runtimeError(E_ARGS, "len takes either a string or a list")

# (substr string start end)
defBuiltin "substr":
  if args.len != 3:
    runtimeError(E_ARGS, "substr takes 3 argument")

  let strd = args[0]
  checkType(strd, dStr)
  let str = strd.strVal

  let startd = args[1]
  checkType(startd, dInt)
  let start = startd.intVal

  let endd = args[2]
  checkType(endd, dInt)
  let endv = endd.intVal # end is a reserved word

  if start < 0:
    runtimeError(E_ARGS, "start index must be greater than 0")

  if endv >= 0:
    return str[start .. endv].md
  else:
    return str[start .. ^ -endv].md



# (insert list index new-el)
defBuiltin "insert":
  if args.len != 3:
    runtimeError(E_ARGS, "insert takes 3 arguments")

  let listd = evalD(args[0])
  checkType(listd, dList)

  let indexd = evalD(args[1])
  checkType(indexd, dInt)

  let el = evalD(args[2])

  var
    list = listd.listVal
    index = indexd.intVal

  try:
    list.insert(el, index)
  except IndexError:
    runtimeError(E_BOUNDS, "index $1 is out of bounds" % [$index])

  return list.md

# (delete list index)
defBuiltin "delete":
  if args.len != 2:
    runtimeError(E_ARGS, "delete takes 2 arguments")

  let listd = evalD(args[0])
  checkType(listd, dList)

  let indexd = evalD(args[1])
  checkType(indexd, dInt)

  var
    list = listd.listVal
    index = indexd.intVal

  try:
    system.delete(list, index)
  except IndexError:
    runtimeError(E_BOUNDS, "index $1 is out of bounds" % [$index])

  return list.md

# (set list index replacement)
# TODO: eliminate code duplication between this, insert, and delete
#  (is this even possible)
defBuiltin "set":
  if args.len != 3:
    runtimeError(E_ARGS, "set takes 3 arguments")

  let listd = evalD(args[0])
  checkType(listd, dList)

  let indexd = evalD(args[1])
  checkType(indexd, dInt)

  let el = evalD(args[2])

  var
    list = listd.listVal
    index = indexd.intVal

  try:
    list[index] = el
  except IndexError:
    runtimeError(E_BOUNDS, "index $1 is out of bounds" % [$index])

  return list.md

defBuiltin "get":
  if args.len != 2:
    runtimeError(E_ARGS, "get takes 2 arguments")

  let listd = evalD(args[0])
  checkType(listd, dList)

  let indexd = evalD(args[1])
  checkType(indexd, dInt)

  var
    list = listd.listVal
    index = indexd.intVal

  try:
    return list[index]
  except:
    runtimeError(E_BOUNDS, "index $1 is out of bounds" % [$index])

# (push list new-el)
# adds to end
defBuiltin "push":
  if args.len != 2:
    runtimeError(E_ARGS, "push takes 2 arguments")

  let listd = evalD(args[0])
  checkType(listd, dList)

  let el = evalD(args[1])

  var list = listd.listVal

  list.add(el)
  return list.md

# (unshift list el)
# adds to beginning
defBuiltin "unshift":
  if args.len != 2:
    runtimeError(E_ARGS, "insert takes 2 arguments")

  let listd = evalD(args[0])
  checkType(listd, dList)

  let el = evalD(args[1])

  var list = listd.listVal

  list.insert(el, 0)
  return list.md
