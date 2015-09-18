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
  return error.md("line $#, col $#: $#" % [$pos.line, $pos.col, message]).pack

template checkType(value: MData, expected: MDataType, ifnot: MError = E_TYPE) =
  if not value.isType(expected):
    runtimeError(ifnot,
      "expected argument of type " & $expected & " instead got " & $value.dType)

template extractObject(objd: MData): MObject =
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
    let res = arg
    sendstr &= res.toEchoString()
    newArgs.add(res)
  caller.send(sendstr)
  return newArgs.md.pack

defBuiltin "notify":
  if args.len != 2:
    runtimeError(E_ARGS, "notify takes 2 arguments")

  let who = extractObject(args[0])
  let msgd = args[1]
  checkType(msgd, dStr)
  let msg = msgd.strVal

  if owner != who and not owner.isWizard:
    runtimeError(E_PERM, "$# cannot notify $#" % [$owner, $who])

  who.send(msg)
  return msg.md.pack

defBuiltin "do":
  var newArgs: seq[MData] = @[]
  for arg in args:
    let res = arg
    newArgs.add(res)

  if newArgs.len > 0:
    return newArgs[^1].pack
  else:
    return @[].md.pack

defBuiltin "eval":
  if args.len != 1:
    runtimeError(E_ARGS, "eval takes 1 argument")

  let argd = args[0]
  checkType(argd, dStr)
  var evalStr = argd.strVal

  try:
    let instructions = compileCode(evalStr)
    discard world.addTask("eval", owner, caller, symtable, instructions)
  except MParseError:
    let msg = getCurrentExceptionMsg()
    runtimeError(E_PARSE, "code failed to parse: $1" % msg)
  except MCompileError:
    let msg = getCurrentExceptionMsg()
    runtimeError(E_PARSE, "compile error: $1" % msg)

defBuiltin "err":
  if args.len != 2:
    runtimeError(E_ARGS, "err takes 2 arguments")

  var err = args[0]
  checkType(err, dErr)

  let msgd = args[1]
  checkType(msgd, dStr)
  let msg = msgd.strVal

  err.errMsg = msg
  return err.pack

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

  let ownerd = info[0]
  let ownero = extractObject(ownerd)
  res.owner = ownero

  let permsd = info[1]
  checkType(permsd, dStr)
  let perms = permsd.strVal
  res.perms = perms

  if info.len == 3:
    let newNamed = info[2]
    checkType(newNamed, dStr)
    let newName = newNamed.strVal
    res.newName = newName

  res

template verbInfoFromInput(info: seq[MData]): VerbInfo =
  if info.len != 2 and info.len != 3:
    runtimeError(E_ARGS, "verb info must be a list of size 2 or 3")

  var res: VerbInfo

  let ownerd = info[0]
  let ownero = extractObject(ownerd)
  res.owner = ownero

  let permsd = info[1]
  checkType(permsd, dStr)
  let perms = permsd.strVal
  res.perms = perms

  if info.len == 3:
    let newNamed = info[2]
    checkType(newNamed, dStr)
    let newName = newNamed.strVal
    res.newName = newName

  res

template objSpecFromData(ospd: MData): ObjSpec =
  let specd = ospd
  checkType(specd, dStr)
  let
    str = specd.strVal
    (success, spec) = strToObjSpec(str)

  if not success:
    runtimeError(E_ARGS, "invalid object spec '$1'" % str)

  spec

template prepSpecFromData(pspd: MData): PrepType =
  let specd = pspd
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

template getPropOn(objd, propd: MData, die = true,
                   all = false): tuple[o: MObject, p: MProperty] =
  let objd2 = objd
  let obj = extractObject(objd2)

  let propd2 = propd
  checkType(propd2, dStr)
  let
    propName = propd.strVal
    (objOn, propObj) = obj.getPropAndObj(propName, all)

  if propObj == nil:
    if die:
      runtimeError(E_PROPNF, "property $1 not found on $2" % [propName, $obj.toObjStr()])
    else:
      return nilD.pack

  (objOn, propObj)

template getVerbOn(objd, verbdescd: MData, die = true,
                   all = false): tuple[o: MObject, v: MVerb] =

  let objd2 = objd
  let obj = extractObject(objd2)

  let verbdescd2 = verbdescd
  checkType(verbdescd2, dStr)
  let verbdesc = verbdescd2.strVal

  let (objOn, verb) = obj.getVerbAndObj(verbdesc, all)
  if verb == nil:
    if die:
      runtimeError(E_VERBNF, "verb $1 not found on $2" % [verbdesc, obj.toObjStr()])
    else:
      return nilD.pack

  (objOn, verb)

# (getprop what propname)
defBuiltin "getprop":
  if args.len != 2:
    runtimeError(E_ARGS, "getprop takes 2 arguments")

  let (obj, propObj) = getPropOn(args[0], args[1], all = true)
  discard obj

  checkRead(owner, propObj)

  return propObj.val.pack

# (setprop what propname newprop)
defBuiltin "setprop":
  if args.len != 3:
    runtimeError(E_ARGS, "setprop takes 3 arguments")

  let objd = args[0]
  let obj = extractObject(objd)

  let
    propd = args[1]
    newVal = args[2]

  checkType(propd, dStr)

  let prop = propd.strVal
  var oldProp = obj.getProp(prop, all = false)

  if oldProp == nil:
    owner.checkWrite(obj)
    discard obj.setProp(prop, newVal)
    world.persist(obj)
  else:
    owner.checkWrite(oldProp)
    oldProp.val = newVal
    world.persist(obj)

  return newVal.pack

# (delprop what propname)
defBuiltin "delprop":
  if args.len != 2:
    runtimeError(E_ARGS, "delprop takes 2 arguments")

  let (obj, prop) = getPropOn(args[0], args[1])

  if prop.inherited:
    runtimeError(E_PROPNF, "$1 does not define a property $2" % [obj.toObjStr, $args[1]])

  for moddedObj, deletedProp in obj.delPropRec(prop).items:
    discard deletedProp
    world.persist(moddedObj)

  return obj.md.pack

# (getpropinfo what propname)
# result is (owner perms)
# perms is [rwc]
defBuiltin "getpropinfo":
  if args.len != 2:
    runtimeError(E_ARGS, "getpropinfo takes 2 arguments")

  let (obj, propObj) = getPropOn(args[0], args[1])
  discard obj

  checkRead(owner, propObj)

  return extractInfo(propObj).pack


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
  let propinfod = args[2]
  checkType(propinfod, dList)
  let
    propinfo = propinfod.listVal
    info = propInfoFromInput(propinfo)

  propObj.setInfo(info)
  world.persist(obj)


  return args[0].pack

# (props obj)
# returns a list of obj's properties
defBuiltin "props":
  if args.len != 1:
    runtimeError(E_ARGS, "props takes 1 argument")

  let objd = args[0]
  let obj = extractObject(objd)

  checkRead(owner, obj)

  let res = obj.getOwnProps().map(md)

  return res.md.pack

# (verbs obj)
# returns a list of obj's verbs' names
defBuiltin "verbs":
  if args.len != 1:
    runtimeError(E_ARGS, "verbs takes 1 argument")

  let objd = args[0]
  let obj = extractObject(objd)

  checkRead(owner, obj)

  var res: seq[MData] = @[]
  for v in obj.verbs:
    res.add(v.names.md)

  return res.md.pack


# (getverbinfo obj verb-desc)
defBuiltin "getverbinfo":
  if args.len != 2:
    runtimeError(E_ARGS, "getverbinfo takes 2 arguments")

  let (obj, verb) = getVerbOn(args[0], args[1])
  discard obj
  checkRead(owner, verb)

  return extractInfo(verb).pack

# (setverbinfo obj verb-desc newinfo)
defBuiltin "setverbinfo":
  if args.len != 3:
    runtimeError(E_ARGS, "setverbinfo takes 3 arguments")

  let (obj, verb) = getVerbOn(args[0], args[1])
  checkWrite(owner, verb)

  let infod = args[2]
  checkType(infod, dList)
  let info = verbInfoFromInput(infod.listVal)

  verb.setInfo(info)
  world.persist(obj)
  return args[0].pack

# (getverbargs obj verb-desc)
defBuiltin "getverbargs":
  if args.len != 2:
    runtimeError(E_ARGS, "getverbargs takes 2 arguments")

  let (obj, verb) = getVerbOn(args[0], args[1])
  discard obj
  checkRead(owner, verb)

  return extractArgs(verb).pack

# (setverbargs obj verb-desc (objspec prepspec objspec))
defBuiltin "setverbargs":
  if args.len != 3:
    runtimeError(E_ARGS, "setverbargs takes 3 arguments")

  let (obj, verb) = getVerbOn(args[0], args[1])
  checkWrite(owner, verb)

  let argsInfod = args[2]
  checkType(argsInfod, dList)

  let argsInfo = verbArgsFromInput(argsInfod.listVal)
  verb.setArgs(argsInfo)
  world.persist(obj)

  return args[0].pack

# (addverb obj names)
defBuiltin "addverb":
  if args.len != 2:
    runtimeError(E_ARGS, "addverb takes 2 arguments")

  let objd = args[0]
  let obj = extractObject(objd)

  let namesd = args[1]
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

  return objd.pack

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

  return obj.md.pack


# (setverbcode obj verb-desc newcode)
defBuiltin "setverbcode":
  if args.len != 3:
    runtimeError(E_ARGS, "setverbcode takes 3 arguments")

  let (obj, verb) = getVerbOn(args[0], args[1])
  checkWrite(owner, verb)

  let newCode = args[2]
  checkType(newCode, dStr)

  try:
    verb.setCode(newCode.strVal)
    world.persist(obj)
    return nilD.pack
  except MParseError:
    let msg = getCurrentExceptionMsg()
    runtimeError(E_PARSE, "code failed to parse: $1" % msg)

defBuiltin "getverbcode":
  if args.len != 2:
    runtimeError(E_ARGS, "getverbcode takes 2 arguments")

  let (obj, verb) = getVerbOn(args[0], args[1])
  discard obj

  checkRead(owner, verb)

  return verb.code.md.pack

# (move what dest)
defBuiltin "move":
  if args.len < 2: # We are actually allowed more arguments in later phases
    runtimeError(E_ARGS, "move takes 2 arguments")

  let
    whatd = args[0]
    destd = args[1]

  var
    what = extractObject(whatd)
    dest = extractObject(destd)

  var phase = phase # So we can change it

  let oldLoc = what.getLocation()

  if phase == 0: # Check for acceptance
    if args.len != 2:
      runtimeError(E_ARGS, "move takes 2 arguments")

    checkOwn(owner, what)

    let whatlist = @[what.md]

    let success = dest.verbCall("accept", caller, whatlist, task.id)
    if not success: # We were not able to call the verb
      runtimeError(E_FMOVE, "$1 didn't accept $2" % [dest.toObjStr(), what.toObjStr()])

    return 1.pack

  if phase == 1: # Check for recursive move and call exitfunc
    let accepted = args[2]
    if not accepted.truthy:
      runtimeError(E_FMOVE, "$1 didn't accept $2" % [dest.toObjStr(), what.toObjStr()])

    var conductor = dest

    while conductor != nil:
      if conductor == what:
        runtimeError(E_RECMOVE, "moving $1 to $2 is recursive" % [what.toObjStr(), dest.toObjStr()])
      let loc = conductor.getLocation()
      if loc == conductor:
        break
      conductor = loc

    if oldLoc == nil:
      phase += 1
    else:
      let success = oldLoc.verbCall("exitfunc", caller, @[what.md], task.id)
      if success:
        return 2.pack
      else:
        phase += 1

  if phase == 2:
    var moveSucceeded = what.moveTo(dest)

    world.persist(what)
    world.persist(dest)
    if oldLoc != nil:
      world.persist(oldLoc)

    if not moveSucceeded:
      runtimeError(E_FMOVE, "moving $1 to $2 failed (it could already be at $2)" %
            [what.toObjStr(), dest.toObjStr()])

    # Discard because it doesn't really matter what happens now, the move is complete
    discard dest.verbCall("enterfunc", caller, @[what.md], task.id)
    return what.md.pack

# (create parent new-owner)
# creates a child of the object given
# owner is set to executor of code
#   (in the case of verbs, the owner of the verb)
#
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
  newObj.setPropR("name", "child of $1 ($2)" % [$parent.md, $newObj.md])

  discard newObj.verbCall("initialize", owner, @[])

  newObj.owner = newOwner
  # TODO: some way to keep track of an object's owner objects

  world.persist(newObj)

  return newObj.md.pack

# (recycle obj)
#
# Destroys obj
defBuiltin "recycle":
  var phase = phase

  let nowhered = world.getGlobal("nowhere")
  let nowhere = extractObject(nowhered)

  if phase == 0:
    if args.len != 1:
      runtimeError(E_ARGS, "recycle takes 1 argument")

    let obj = extractObject(args[0])
    checkOwn(owner, obj)

    let (has, contents) = obj.getContents()
    if has:
      for contained in contents:
        # This is actually how LambdaMOO does it: no call to the move
        # builtin instead a raw exitfunc call. I find this somewhat
        # dubious but actually making a builtin call is difficult because
        # of the phase mechanism.
        discard contained.moveTo(nowhere)
        discard obj.verbCall("exitfunc", owner, @[contained.md])
        world.persist(contained)

    if not obj.verbCall("recycle", owner, @[], task.id):
      # We don't actually care if the verb "recycle" exists
      phase = 1
    else:
      return 1.pack

  if phase == 1:
    let obj = extractObject(args[0])
    let parent = obj.parent

    # If the object parents itself, all of its children will be left
    # without a parent so they now have to parent themselves too.
    if parent == obj:
      while obj.children.len > 0:
        let child = obj.children[0]
        child.changeParent(child)
        world.persist(child)
    else:
      while obj.children.len > 0:
        let child = obj.children[0]
        child.changeParent(parent)
        world.persist(child)

    # Destroy the object
    discard obj.moveTo(nowhere)
    discard nowhere.removeFromContents(obj)
    world.delete(obj)
    world.persist()

    return 1.md.pack

defBuiltin "parent":
  if args.len != 1:
    runtimeError(E_ARGS, "parent takes 1 argument")

  let obj = extractObject(args[0])
  return obj.parent.md.pack

defBuiltin "children":
  if args.len != 1:
    runtimeError(E_ARGS, "children takes 1 argument")

  let obj = extractObject(args[0])
  return obj.children.map(proc (x: MObject): MData = x.md).md.pack

defBuiltin "setparent":
  if args.len != 2:
    runtimeError(E_ARGS, "setparent takes 2 arguments")

  var obj = extractObject(args[0])
  let newParent = extractObject(args[1])

  var conductor = newParent

  # An object can parent itself but cannot parent a different object that
  # parents it. This is because having #0 parent of #0 and #1 parent of #1
  # is useful. This is an important decision that can go awry later though.
  #
  # Note that the original LambdaMOO doesn't allow for recursive parenting
  # at all.
  while conductor != conductor.parent:
    conductor = conductor.parent
    if conductor == obj:
      runtimeError(E_RECMOVE, "parenting cannot create cycles of length greater than 1!")

  obj.changeParent(newParent)
  world.persist(obj)

  return newParent.md.pack

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
    return 1.md.pack
  else:
    return 0.md.pack

# (call lambda-or-builtin args)
# forces evaluation (is this a good way to do it?)
defBuiltin "call":
  if args.len < 1:
    runtimeError(E_ARGS, "call takes one or more argument (lambda then arguments)")

  let execd = args[0]
  if execd.isType(dSym):
    let stmt = (@[execd] & args[1 .. ^1]).md

    return stmt.pack
  elif execd.isType(dList):
    var lambl = execd.listVal
    if lambl.len != 3:
      runtimeError(E_ARGS, "call: invalid lambda")

    lambl = lambl & args[1 .. ^1]

    return lambl.md.pack
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
    of 4:
      discard
    else:
      runtimeError(E_ARGS, "verbcall takes 2 or 3 arguments")

  let obj = extractObject(args[0])
  let (holder, verb) = getVerbOn(args[0], args[1], all = true)
  discard holder

  if phase == 0:
    if args.len > 3:
      runtimeError(E_ARGS, "verbcall takes 2 or 3 arguments")

    let cargsd = args[2]
    checkType(cargsd, dList)
    let cargs = cargsd.listVal

    owner.checkExecute(verb)

    task.suspend()
    obj.verbCallRaw(verb, caller, cargs, symtable = symtable, callback = task.id)
    return 1.pack
  if phase == 1:
    let verbResult = args[^1]

    return verbResult.pack
    # TODO: increment current task's quotas by the amount of ticks innerTask used

type
  BinFloatOp = proc(x: float, y: float): float
  BinIntOp = proc(x: int, y: int): int

template extractFloat(into: var float, num: MData) =
  if num.isType(dInt):
    into = num.intVal.float
  elif num.isType(dFloat):
    into = num.floatVal
  else:
    runtimeError(E_ARGS, "invalid number " & $num)

template defArithmeticOperator(name: string, op: BinFloatOp, logical = false,
                               strictlyBinary = false) =
  defBuiltin name:
    if strictlyBinary:
      if args.len != 2:
        runtimeError(E_ARGS, "$1 takes 2 arguments" % name)
    else:
      if args.len < 2:
        runtimeError(E_ARGS, "$1 takes 2 or more arguments" % name)

    var rhs, lhs: float
    template combine(lhsd: MData, rhsd: MData): MData =

      lhs.extractFloat(lhsd)
      rhs.extractFloat(rhsd)

      if lhsd.isType(dInt) and rhsd.isType(dInt):
        op(lhs, rhs).int.md
      else:
        op(lhs, rhs).md

    var acc: MData

    if logical:
      acc = args[0].truthy.int.md
      for next in args[1..^1]:
        acc = combine(acc, next.truthy.int.md)
    else:
      acc = args[0]
      for next in args[1..^1]:
        acc = combine(acc, next)

    return acc.pack

defArithmeticOperator("+", `+`)
defArithmeticOperator("-", `-`)
defArithmeticOperator("*", `*`)
defArithmeticOperator("/", `/`)

proc wrappedAnd(a, b: float): float = (a.int and b.int).float
proc wrappedOr(a, b: float): float = (a.int or b.int).float
proc wrappedXor(a, b: float): float = (a.int xor b.int).float

defArithmeticOperator("&", wrappedAnd)
defArithmeticOperator("|", wrappedOr)
defArithmeticOperator("^", wrappedXor)
defArithmeticOperator("and", wrappedAnd, logical = true)
defArithmeticOperator("or",  wrappedOr, logical = true)
defArithmeticOperator("xor", wrappedXor, logical = true)

proc wrappedLT(a, b: float): float = (a < b).float
proc wrappedLTE(a, b: float): float = (a <= b).float
proc wrappedGT(a, b: float): float = (a > b).float
proc wrappedGTE(a, b: float): float = (a >= b).float

defArithmeticOperator("<", wrappedLT)
defArithmeticOperator("<=", wrappedLTE)
defArithmeticOperator(">", wrappedGT)
defArithmeticOperator(">=", wrappedGTE)

# (= a b)
defBuiltin "=":
  if args.len != 2:
    runtimeError(E_ARGS, "= takes 2 arguments")

  let a = args[0]
  let b = args[1]

  if a == b:
    return 1.md.pack
  else:
    return 0.md.pack

defBuiltin "nil?":
  if args.len != 1:
    runtimeError(E_ARGS, "nil? takes 1 argument")

  return args[0].isType(dNil).int.md.pack

# tostring function
# ($ obj) returns "#6", for example
defBuiltin "$":
  if args.len != 1:
    runtimeError(E_ARGS, "$ takes 1 argument")

  let what = args[0]
  if what.isType(dStr):
    return what.pack
  else:
    return what.toCodeStr().md.pack

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
      let arg = argd
      total &= arg.toEchoString()
    return total.md.pack
  elif typ == dList:
    var total: seq[MData] = @[]
    for argd in args:
      let arg = argd
      checkType(arg, dList)
      total.add(arg.listVal)
    return total.md.pack
  else:
    runtimeError(E_ARGS, "cat only concatenates strings or lists")

# (head list)
defBuiltin "head":
  if args.len != 1:
    runtimeError(E_ARGS, "head takes 1 argument")

  let listd = args[0]

  if listd.isType(dList):
    let list = listd.listVal
    if list.len == 0:
      return @[].md.pack

    return list[0].pack
  elif listd.isType(dStr):
    let str = listd.strVal
    if str.len == 0:
      return "".md.pack

    return str[0 .. 0].md.pack
  else:
    runtimeError(E_ARGS, "head takes either a string or a list")


# (tail list)
defBuiltin "tail":
  if args.len != 1:
    runtimeError(E_ARGS, "tail takes 1 argument")

  let listd = args[0]
  if listd.isType(dList):
    let list = listd.listVal
    if list.len == 0:
      return @[].md.pack

    return list[1 .. ^1].md.pack
  elif listd.isType(dStr):
    let str = listd.strVal
    if str.len == 0:
      return "".md.pack

    return str[1 .. ^1].md.pack
  else:
    runtimeError(E_ARGS, "tail takes either a string or a list")

# (len list)
defBuiltin "len":
  if args.len != 1:
    runtimeError(E_ARGS, "len takes 1 argument")

  let listd = args[0]
  if listd.isType(dList):
    let list = listd.listVal

    return list.len.md.pack
  elif listd.isType(dStr):
    let str = listd.strVal

    return str.len.md.pack
  else:
    runtimeError(E_ARGS, "len takes either a string or a list")

# (substr string start end)
defBuiltin "substr":
  if args.len != 3:
    runtimeError(E_ARGS, "substr takes 3 arguments")

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
    return str[start .. endv].md.pack
  else:
    return str[start .. ^ -endv].md.pack

# (index string substr [ignore-case])
# returns index of substr in string, or -1
defBuiltin "index":
  var args = args
  case args.len:
    of 2: args.add(0.md)
    of 3: discard
    else: runtimeError(E_ARGS, "index takes 2 or 3 arguments")

  let haystackd = args[0]
  checkType(haystackd, dStr)
  var haystack = haystackd.strVal

  let needled = args[1]
  checkType(needled, dStr)
  var needle = needled.strVal

  let ignoreCase = args[2]
  if ignoreCase.truthy:
    haystack = haystack.toLower()
    needle = needle.toLower()

  return haystack.find(needle).md.pack


# (insert list index new-el)
defBuiltin "insert":
  if args.len != 3:
    runtimeError(E_ARGS, "insert takes 3 arguments")

  let listd = args[0]
  checkType(listd, dList)

  let indexd = args[1]
  checkType(indexd, dInt)

  let el = args[2]

  var
    list = listd.listVal
    index = indexd.intVal

  try:
    list.insert(el, index)
  except IndexError:
    runtimeError(E_BOUNDS, "index $1 is out of bounds" % [$index])

  return list.md.pack

# (delete list index)
defBuiltin "delete":
  if args.len != 2:
    runtimeError(E_ARGS, "delete takes 2 arguments")

  let listd = args[0]
  checkType(listd, dList)

  let indexd = args[1]
  checkType(indexd, dInt)

  var
    list = listd.listVal
    index = indexd.intVal

  try:
    system.delete(list, index)
  except IndexError:
    runtimeError(E_BOUNDS, "index $1 is out of bounds" % [$index])

  return list.md.pack

# (set list index replacement)
# TODO: eliminate code duplication between this, insert, and delete
#  (is this even possible)
defBuiltin "set":
  if args.len != 3:
    runtimeError(E_ARGS, "set takes 3 arguments")

  let listd = args[0]
  checkType(listd, dList)

  let indexd = args[1]
  checkType(indexd, dInt)

  let el = args[2]

  var
    list = listd.listVal
    index = indexd.intVal

  try:
    if index < 0:
      list[^ -index] = el
    else:
      list[index] = el
  except IndexError:
    runtimeError(E_BOUNDS, "index $1 is out of bounds" % [$index])

  return list.md.pack

defBuiltin "get":
  if args.len != 2:
    runtimeError(E_ARGS, "get takes 2 arguments")

  let listd = args[0]
  checkType(listd, dList)

  let indexd = args[1]
  checkType(indexd, dInt)

  var
    list = listd.listVal
    index = indexd.intVal

  try:
    if index < 0:
      return list[^ -index].pack
    else:
      return list[index].pack
  except:
    runtimeError(E_BOUNDS, "index $1 is out of bounds" % [$index])

# (push list new-el)
# adds to end
defBuiltin "push":
  if args.len != 2:
    runtimeError(E_ARGS, "push takes 2 arguments")

  let listd = args[0]
  checkType(listd, dList)

  let el = args[1]

  var list = listd.listVal

  list.add(el)
  return list.md.pack

# (unshift list el)
# adds to beginning
defBuiltin "unshift":
  if args.len != 2:
    runtimeError(E_ARGS, "insert takes 2 arguments")

  let listd = args[0]
  checkType(listd, dList)

  let el = args[1]

  var list = listd.listVal

  list.insert(el, 0)
  return list.md.pack

# (setadd list el)
# Adds el to list only if it's already not contained
defBuiltin "setadd":
  if args.len != 2:
    runtimeError(E_ARGS, "setadd takes 2 arguments")

  let listd = args[0]
  checkType(listd, dList)

  let el = args[1]

  var list = listd.listVal
  if el notin list:
    list.add(el)

  return list.md.pack

# (setremove list el)
# Removes el from list
defBuiltin "setremove":
  if args.len != 2:
    runtimeError(E_ARGS, "setremove takes 2 arguments")

  let listd = args[0]
  checkType(listd, dList)

  let el = args[1]

  var list = listd.listVal
  for idx, val in list:
    if el == val:
      list.delete(idx)
      break

  return list.md.pack

# (in list el)
# returns index of el in list, or -1
defBuiltin "in":
  if args.len != 2:
    runtimeError(E_ARGS, "in takes 2 arguments")

  let listd = args[0]
  checkType(listd, dList)

  let el = args[1]

  let list = listd.listVal
  return list.find(el).md.pack

# (pass arg1 arg2 ...)
# calls the parent verb
defBuiltin "pass":
  if phase == 0:
    var args = args
    if args.len == 0:
      let oldArgsd = symtable["args"]
      if oldArgsd.isType(dList):
        args = oldArgsd.listVal

    let holderd = symtable["holder"]
    if not holderd.isType(dObj):
      return nilD.pack
    let holder = extractObject(holderd)
    let parent = holder.parent

    let selfd = symtable["self"]
    if not selfd.isType(dObj):
      return nilD.pack
    let self = extractObject(selfd)

    if parent == nil or parent == holder:
      return nilD.pack

    let verbd = symtable["verb"]
    if not verbd.isType(dStr):
      return nilD.pack
    let verbName = verbd.strVal

    let verb = parent.getVerb(verbName)

    if verb == nil:
      runtimeError(E_VERBNF, "Pass failed, verb is not inherited.")

    self.verbCallRaw(verb, owner, args,
                       symtable = symtable, holder = parent, callback = task.id)

    return 1.pack

  if phase == 1:
    let verbResult = args[^1]
    return verbResult.pack
