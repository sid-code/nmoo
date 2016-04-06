# Here are all of the builtin functions that verbs can call

import strutils
import tables
import sequtils
import math
import nre
import options

import types
import objects
import verbs
import scripting
import persist
import compile
import tasks
import querying
import server

# for hashing builtins
import bcrypt

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

template extractInt(d: MData): int =
  checkType(d, dInt)
  d.intVal
template extractFloat(d: MData): float =
  checkType(d, dFloat)
  d.floatVal
template extractString(d: MData): string =
  checkType(d, dStr)
  d.strVal
template extractSymbol(d: MData): string =
  checkType(d, dSym)
  d.symVal
template extractList(d: MData): seq[MData] =
  checkType(d, dList)
  d.listVal
template extractError(d: MData): tuple[e: MError, s: string] =
  checkType(d, dErr)
  (d.errVal, d.errMsg)

template extractObject(objd: MData): MObject =
  checkType(objd, dObj)
  let obj = world.dataToObj(objd)
  if isNil(obj):
    runtimeError(E_ARGS, "invalid object " & $objd)

  obj

template checkForError(value: MData) =
  if value.isType(dErr):
    return value

template runtimeError(error: MError, message: string) =
  return error.md("line $#, col $#: $#: $#" % [$pos.line, $pos.col, bname, message]).pack

template checkType(value: MData, expected: MDataType, ifnot: MError = E_TYPE) =
  if not value.isType(expected):
    runtimeError(ifnot,
      "expected argument of type " & $expected &
      " instead got " & $value.dType)

template isWizardT: bool = isWizard(task.owner)
template owns(what: MObject): bool = task.owner.owns(what)

template checkOwn(what: MObject) =
  let obj = task.owner
  if not obj.owns(what):
    runtimeError(E_PERM, obj.toObjStr() & " doesn't own " & what.toObjStr())

template checkOwn(prop: MProperty) =
  let obj = task.owner
  if not obj.owns(prop):
    runtimeError(E_PERM, obj.toObjStr() & " doesn't own " & prop.name)

template checkOwn(verb: MVerb) =
  let obj = task.owner
  if not obj.owns(verb):
    runtimeError(E_PERM, obj.toObjStr() & " doesn't own " & verb.name)

template checkRead(what: MObject) =
  let obj = task.owner
  if not obj.canRead(what):
    runtimeError(E_PERM, obj.toObjStr() & " cannot read " & what.toObjStr())
template checkWrite(what: MObject) =
  let obj = task.owner
  if not obj.canWrite(what):
    runtimeError(E_PERM, obj.toObjStr() & " cannot write " & what.toObjStr())
template checkRead(what: MProperty) =
  let obj = task.owner
  if not obj.canRead(what):
    runtimeError(E_PERM, obj.toObjStr() & " cannot read property: " & what.name)
template checkWrite(what: MProperty) =
  let obj = task.owner
  if not obj.canWrite(what):
    runtimeError(E_PERM, obj.toObjStr() & " cannot write property: " & what.name)
template checkRead(what: MVerb) =
  let obj = task.owner
  if not obj.canRead(what):
    runtimeError(E_PERM, obj.toObjStr() & " cannot read verb: " & what.names)
template checkWrite(what: MVerb) =
  let obj = task.owner
  if not obj.canWrite(what):
    runtimeError(E_PERM, obj.toObjStr() & " cannot write verb: " & what.names)
template checkExecute(what: MVerb) =
  let obj = task.owner
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
  let msg = extractString(args[1])

  if task.owner != who and not isWizardT():
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
  if phase == 0:
    if args.len != 1:
      runtimeError(E_ARGS, "eval takes 1 argument")

    var evalStr = extractString(args[0])

    try:
      let instructions = compileCode(evalStr)
      discard world.addTask("eval", owner, caller, symtable, instructions,
                            taskType = task.taskType, callback = task.id)
      return 1.pack
    except MParseError:
      let msg = getCurrentExceptionMsg()
      runtimeError(E_PARSE, "code failed to parse: $1" % msg)
    except MCompileError:
      let msg = getCurrentExceptionMsg()
      runtimeError(E_PARSE, "compile error: $1" % msg)
  if phase == 1:
    return args[1].pack

defBuiltin "settaskperms":
  if args.len != 1:
    runtimeError(E_ARGS, "settaskperms takes 1 argument")

  let newPerms = extractObject(args[0])
  if not isWizardT() and task.owner != newPerms:
    runtimeError(E_PERM, "$# can't set task perms to $#" %
                  [task.owner.toObjStr(), newPerms.toObjStr()])

  task.owner = newPerms
  return newPerms.md.pack

# (read [player])
defBuiltin "read":
  if phase == 0:
    var who: MObject
    case args.len:
      of 0:
        who = caller
      of 1:
        who = extractObject(args[0])
      else:
        runtimeError(E_ARGS, "read takes 0 or 1 arguments")

    if not isWizardT() and who != caller:
      runtimeError(E_PERM, "you don't have permission to read from that connection")

    let client = findClient(who)
    if isNil(client):
      runtimeError(E_ARGS, who.toObjStr() & " has not been connected to!")

    task.askForInput(client)
    return 1.pack
  elif phase == 1:
    # sanity check
    if args.len != 1:
      runtimeError(E_ARGS, "read failed")

    return args[0].pack

defBuiltin "err":
  if args.len != 2:
    runtimeError(E_ARGS, "err takes 2 arguments")

  var err = args[0]
  checkType(err, dErr)

  let msg = extractString(args[1])

  err.errMsg = msg
  return err.pack

# (erristype err E_WHATEVER)
# Checks whether err has error type E_WHATEVER
defBuiltin "erristype":
  if args.len != 2:
    runtimeError(E_ARGS, "erristype takes 2 arguments")

  var (err, msg) = extractError(args[0])
  var (err2, msg2) = extractError(args[1])

  return if err == err2: 1.md.pack else: 0.md.pack

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

  let perms = extractString(info[1])
  res.perms = perms

  if info.len == 3:
    let newName = extractString(info[2])
    res.newName = newName

  res

template verbInfoFromInput(info: seq[MData]): VerbInfo =
  if info.len != 2 and info.len != 3:
    runtimeError(E_ARGS, "verb info must be a list of size 2 or 3")

  var res: VerbInfo

  let ownerd = info[0]
  let ownero = extractObject(ownerd)
  res.owner = ownero

  let perms = extractString(info[1])
  res.perms = perms

  if info.len == 3:
    let newName = extractString(info[2])
    res.newName = newName

  res

template objSpecFromData(ospd: MData): ObjSpec =
  let
    str = extractString(ospd)
    (success, spec) = strToObjSpec(str)

  if not success:
    runtimeError(E_ARGS, "invalid object spec '$1'" % str)

  spec

template prepSpecFromData(pspd: MData): PrepType =
  let
    str = extractString(pspd)
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

  if not isNil(info.newName):
    prop.name = info.newName

proc setInfo(verb: MVerb, info: VerbInfo) =
  verb.owner = info.owner
  verb.pubRead = "r" in info.perms
  verb.pubWrite = "w" in info.perms
  verb.pubExec = "x" in info.perms

  if not isNil(info.newName):
    verb.names = info.newName

proc setArgs(verb: MVerb, args: VerbArgs) =
  verb.doSpec = args.doSpec
  verb.prepSpec = args.prepSpec
  verb.ioSpec = args.ioSpec

template getPropOn(objd, propd: MData, die = true, useDefault = false,
                   default = nilD, all = false): tuple[o: MObject, p: MProperty] =
  let objd2 = objd
  let obj = extractObject(objd2)
  var res: tuple[o: MObject, p: MProperty]

  let
    propName = extractString(propd)
    (objOn, propObj) = obj.getPropAndObj(propName, all)

  if isNil(propObj):
    if useDefault:
      res = (nil, newProperty("default", default, nil))
    else:
      if die:
        runtimeError(E_PROPNF, "property $1 not found on $2" % [propName, $obj.toObjStr()])
      else:
        return nilD.pack
  else:
    res = (objOn, propObj)

  res

template getVerbOn(objd, verbdescd: MData, die = true,
                   all = false): tuple[o: MObject, v: MVerb] =

  let objd2 = objd
  let obj = extractObject(objd2)

  var res: tuple[o: MObject, v: MVerb]

  let verbdescd2 = verbdescd
  if verbdescd2.isType(dStr):
    let verbdesc = verbdescd2.strVal

    let (objOn, verb) = obj.getVerbAndObj(verbdesc, all)
    if isNil(verb):
      if die:
        runtimeError(E_VERBNF, "verb $1 not found on $2" % [verbdesc, obj.toObjStr()])
      else:
        return nilD.pack

    res = (objOn, verb)
  elif verbdescd2.isType(dInt):
    let verbnum = verbdescd2.intVal

    if verbnum >= obj.verbs.len or verbnum < 0:
      runtimeError(E_VERBNF, "verb index $# out of range" % $verbnum)

    res = (obj, obj.verbs[verbnum])
  else:
    runtimeError(E_ARGS, "verb indices can only be strings or integers")


  res

# (getprop what propname)
defBuiltin "getprop":
  var useDefault = false
  var default = nilD
  case args.len:
    of 2: discard
    of 3:
      default = args[2]
      useDefault = true
    else:
      runtimeError(E_ARGS, "getprop takes 2 arguments")

  let (obj, propObj) = getPropOn(args[0], args[1],
                                 all = true,
                                 default = default,
                                 useDefault = useDefault)
  discard obj

  checkRead(propObj)

  return propObj.val.pack

# (setprop what propname newprop)
defBuiltin "setprop":
  if args.len != 3:
    runtimeError(E_ARGS, "setprop takes 3 arguments")

  let objd = args[0]
  let obj = extractObject(objd)

  let newVal = args[2]

  let prop = extractString(args[1])
  var oldProp = obj.getProp(prop, all = false)

  if isNil(oldProp):
    checkWrite(obj)
    let newProp = obj.setProp(prop, newVal)
    newProp.owner = task.owner
    world.persist(obj)
  else:
    checkWrite(oldProp)
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

  checkRead(propObj)

  return extractInfo(propObj).pack


# (setpropinfo what propname newinfo)
# newinfo is like result from getpropinfo but can
# optionally have a third element specifying a new
# name for the property
defBuiltin "setpropinfo":
  if args.len != 3:
    runtimeError(E_ARGS, "setpropinfo takes 3 arguments")

  let (obj, propObj) = getPropOn(args[0], args[1])

  checkWrite(propObj)

  # validate the property info
  let
    propinfo = extractList(args[2])
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

  checkRead(obj)

  let res = obj.getOwnProps().map(md)

  return res.md.pack

# (verbs obj)
# returns a list of obj's verbs' names
defBuiltin "verbs":
  if args.len != 1:
    runtimeError(E_ARGS, "verbs takes 1 argument")

  let objd = args[0]
  let obj = extractObject(objd)

  checkRead(obj)

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
  checkRead(verb)

  return extractInfo(verb).pack

# (setverbinfo obj verb-desc newinfo)
defBuiltin "setverbinfo":
  if args.len != 3:
    runtimeError(E_ARGS, "setverbinfo takes 3 arguments")

  let (obj, verb) = getVerbOn(args[0], args[1])
  checkWrite(verb)

  let verbInfo = extractList(args[2])

  let info = verbInfoFromInput(verbInfo)

  verb.setInfo(info)
  world.persist(obj)
  return args[0].pack

# (getverbargs obj verb-desc)
defBuiltin "getverbargs":
  if args.len != 2:
    runtimeError(E_ARGS, "getverbargs takes 2 arguments")

  let (obj, verb) = getVerbOn(args[0], args[1])
  discard obj
  checkRead(verb)

  return extractArgs(verb).pack

# (setverbargs obj verb-desc (objspec prepspec objspec))
defBuiltin "setverbargs":
  if args.len != 3:
    runtimeError(E_ARGS, "setverbargs takes 3 arguments")

  let (obj, verb) = getVerbOn(args[0], args[1])
  checkWrite(verb)

  let verbArgs = extractList(args[2])

  let argsInfo = verbArgsFromInput(verbArgs)
  verb.setArgs(argsInfo)
  world.persist(obj)

  return args[0].pack

# (addverb obj names)
defBuiltin "addverb":
  if args.len != 2:
    runtimeError(E_ARGS, "addverb takes 2 arguments")

  let objd = args[0]
  let obj = extractObject(objd)

  let names = extractString(args[1])

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

  if isNil(verb) or verb.inherited:
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
  checkWrite(verb)

  let newCode = extractString(args[2])

  try:
    verb.setCode(newCode)
    world.persist(obj)
    return nilD.pack
  except MParseError:
    let msg = getCurrentExceptionMsg()
    runtimeError(E_PARSE, "code failed to parse: $1" % msg)
  except MCompileError:
    let msg = getCurrentExceptionMsg()
    runtimeError(E_COMPILE, msg)

defBuiltin "getverbcode":
  if args.len != 2:
    runtimeError(E_ARGS, "getverbcode takes 2 arguments")

  let (obj, verb) = getVerbOn(args[0], args[1])
  discard obj

  checkRead(verb)

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

    checkOwn(what)

    let failure = isNil(dest.verbCall("accept", caller, @[what.md], callback = task.id))
    if failure: # We were not able to call the verb
      runtimeError(E_FMOVE, "$1 didn't accept $2" % [dest.toObjStr(), what.toObjStr()])

    return 1.pack

  if phase == 1: # Check for recursive move and call exitfunc
    let accepted = args[2]
    if not accepted.truthy:
      runtimeError(E_FMOVE, "$1 didn't accept $2" % [dest.toObjStr(), what.toObjStr()])

    var conductor = dest

    while not isNil(conductor):
      if conductor == what:
        runtimeError(E_RECMOVE, "moving $1 to $2 is recursive" % [what.toObjStr(), dest.toObjStr()])
      let loc = conductor.getLocation()
      if loc == conductor:
        break
      conductor = loc

    if isNil(oldLoc):
      phase += 1
    else:
      let failure = isNil(oldLoc.verbCall("exitfunc", caller, @[what.md], callback = task.id))
      if failure:
        # This means the verb didn't exist, but that's not an issue.
        phase += 1
      else:
        return 2.pack

  if phase == 2:
    var moveSucceeded = what.moveTo(dest)

    world.persist(what)
    world.persist(dest)
    if not isNil(oldLoc):
      world.persist(oldLoc)

    if not moveSucceeded:
      runtimeError(E_FMOVE, "moving $1 to $2 failed (it could already be at $2)" %
            [what.toObjStr(), dest.toObjStr()])

    let failure = isNil(dest.verbCall("enterfunc", caller, @[what.md], callback = task.id))
    if failure:
      phase += 1
    else:
      return 3.pack

  if phase == 3:
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

    if newOwner != owner and not isWizardT():
      runtimeError(E_PERM, "non-wizards can only set themselves as the owner of objects")
  else:
    newOwner = owner

  if not parent.fertile and (owns(parent) or isWizardT()):
    runtimeError(E_PERM, "$1 is not fertile" % [parent.toObjStr()])

  # TODO: Quotas

  let newObj = parent.createChild()
  world.add(newObj)
  newObj.setPropR("name", "child of $1 ($2)" % [$parent.md, $newObj.md])

  discard newObj.verbCall("initialize", owner, @[])

  newObj.owner = newOwner
  # TODO: some way to keep track of an object's owner objects

  world.persist(newObj)
  world.persist(parent)

  return newObj.md.pack

# (level obj)
# returns obj's level
# 0 = wizard
# 1 = programmer
# 2 = builder
# 3 = regular
defBuiltin "level":
  if args.len != 1:
    runtimeError(E_ARGS, "level takes 1 argument")

  let obj = extractObject(args[0])
  return obj.level.md.pack

# (setlevel obj new-level)
# sets obj's level to new-level
# the programmer must be a wizard
defBuiltin "setlevel":
  if args.len != 2:
    runtimeError(E_ARGS, "setlevel takes 2 arguments")

  let obj = extractObject(args[0])
  let newLevel = extractInt(args[1])

  if not isWizardT():
    runtimeError(E_PERM, "only wizards can set level")

  if newLevel > 3 or newLevel < 0:
    runtimeError(E_ARGS, "level must be 0..3")

  obj.level = newLevel
  return newLevel.md.pack

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
    checkOwn(obj)

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

    if isNil(obj.verbCall("recycle", owner, @[], callback = task.id)):
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

    let childIndex = parent.children.find(obj)
    if childIndex > -1:
      system.delete(parent.children, childIndex)

    # Destroy the object
    discard obj.moveTo(nowhere)
    discard nowhere.removeFromContents(obj)
    world.dbDelete(obj)
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
  let oldParent = obj.parent

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
  world.persist(oldParent)
  world.persist(obj)
  world.persist(newParent)

  return newParent.md.pack

# (query str)
# Wrapper for the query proc in querying.nim
defBuiltin "query":
  if args.len != 1:
    runtimeError(E_ARGS, "query takes 1 argument")

  let str = extractString(args[0])

  return caller.query(str).map(md).md.pack

# (istype thingy typedesc)
# typedesc is a string:
#   int, float, str, sym, obj, list, err
defBuiltin "istype":
  if args.len != 2:
    runtimeError(E_ARGS, "istype takes 2 arguments")

  let
    what = args[0]
    typev = extractString(args[1])

  let (valid, typedVal) = strToType(typev)
  if not valid:
    runtimeError(E_ARGS, "'$1' is not a valid data type" % typev)

  if what.isType(typedVal):
    return 1.md.pack
  else:
    return 0.md.pack

# (valid obj)
# checks if an object is valid, e.g. it exists
defBuiltin "valid":
  if args.len != 1:
    runtimeError(E_ARGS, "valid takes one argument")

  let objd = args[0]
  checkType(objd, dObj)
  let obj = world.dataToObj(objd)
  if isNil(obj):
    return 0.md.pack
  else:
    return 1.md.pack


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

    let cargs = extractList(args[2])

    checkExecute(verb)

    task.setStatus(tsAwaitingResult)
    let verbTask = obj.verbCallRaw(verb, caller, cargs, symtable = symtable, taskType = task.taskType, callback = task.id)
    if isNil(verbTask):
      runtimeError(E_VERBNF, "verb $#:$# has not been compiled (perhaps it failed earlier?)" %
                                [obj.toObjStr(), verb.names])
    return 1.pack

  if phase == 1:
    let verbResult = args[^1]

    return verbResult.pack
    # TODO: increment current task's quotas by the amount of ticks innerTask used

type
  BinFloatOp = proc(x: float, y: float): float
  BinIntOp = proc(x: int, y: int): int

template extractFloatInto(into: var float, num: MData) =
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

      lhs.extractFloatInto(lhsd)
      rhs.extractFloatInto(rhsd)

      if lhsd.isType(dInt) and rhsd.isType(dInt):
        op(lhs, rhs).int.md
      else:
        op(lhs, rhs).md

    var acc: MData

    if logical:
      acc = args[0].truthy.int.md
      for next in args[1 .. ^1]:
        acc = combine(acc, next.truthy.int.md)
    else:
      acc = args[0]
      for next in args[1 .. ^1]:
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

defBuiltin "not":
  if args.len != 1:
    runtimeError(E_ARGS, "not takes 1 argument")

  let what = args[0]
  return (not what.truthy).int.md.pack

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

# Object tostring function
# ($o obj) returns toObjStr(#6)
defBuiltin "$o":
  if args.len != 1:
    runtimeError(E_ARGS, "$o takes 1 argument")

  let what = extractObject(args[0])
  return what.toObjStr().md.pack

# (cat str1 str2 ...)
# (cat list1 list2 ...)
# concats any number of strings or lists in a list
# use (call cat (str-list/list-list)) to call it with a list
defBuiltin "cat":
  if args.len < 1:
    runtimeError(E_ARGS, "cat needs at least one string")

  let typ = args[0].dtype
  if typ == dList:
    var total: seq[MData] = @[]
    for argd in args:
      let arg = extractList(argd)
      total.add(arg)
    return total.md.pack
  else:
    var total = ""
    for argd in args:
      let arg = argd
      total &= arg.toEchoString()
    return total.md.pack

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

  let str = extractString(args[0])
  let start = extractInt(args[1])
  let endv = extractInt(args[2]) # end is a reserved word

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

  var haystack = extractString(args[0])
  var needle = extractString(args[1])
  let ignoreCase = args[2]
  if ignoreCase.truthy:
    haystack = haystack.toLower()
    needle = needle.toLower()

  return haystack.find(needle).md.pack

# (match str pat)
# pat is regex
# if match successful: returns list of capturing groups
# else: returns nil
defBuiltin "match":
  if args.len != 2:
    runtimeError(E_ARGS, "match takes 2 arguments")

  try:
    let pat = extractString(args[1])
    let regex = re(pat.replace(re"%(.)", proc (m: RegexMatch): string =
      let capt = m.captures[0]
      if capt == "%":
        return "%"
      else:
        return "\\" & capt))
    let str = extractString(args[0])
    let matches = str.match(regex)
    if matches.isSome:
      let captures = nre.toSeq(matches.get().captures())
      return captures.map(md).md.pack
    else:
      return nilD.pack
  except SyntaxError:
    let msg = getCurrentException().msg
    runtimeError(E_ARGS, "regex error: " & msg)

# (repeat str times)
# (repeat "hello" 3) => "hellohellohello"
defBuiltin "repeat":
  if args.len != 2:
    runtimeError(E_ARGS, "repeat takes 2 arguments")

  let str = extractString(args[0])
  let times = extractInt(args[1])

  if times < 1:
    runtimeError(E_ARGS, "can't repeat a string less than one time")

  return str.repeat(times).md.pack

# (strsub str from to)
# replaces all occurrences of "from" in str to "to"
# (strsub "hello" "l" "n") => "henno"
defBuiltin "strsub":
  if args.len != 3:
    runtimeError(E_ARGS, "strsub takes 3 arguments")

  let str = extractString(args[0])
  let fromv = extractString(args[1])
  let to = extractString(args[2])

  return str.replace(fromv, to).md.pack

# (fit string length filler=" " trail="")
# If (len string) is less than length, then filler is added until it isn't
# otherwise, string is cut short and trail is added, such that it doesn't exceed length

defBuiltin "fit":
  var
    filler = " "
    trail = ""

  if args.len notin 2..4:
    runtimeError(E_ARGS, "fit takes 2 to 4 arguments")

  var str = extractString(args[0])
  let length = extractInt(args[1])

  if args.len >= 3:
    filler = extractString(args[2])

  if args.len >= 4:
    trail = extractString(args[3])

  if trail.len > str.len:
    trail = ""

  let strlen = str.len
  let traillen = trail.len

  if strlen == length:
    return str.md.pack
  elif strlen < length:
    while str.len <= length:
      str &= filler

    return str[0..length-1].md.pack
  elif strlen > length:
    let allowed = length - traillen
    return (str[0..allowed-1] & trail).md.pack

defBuiltin "split":
  var sep = " "
  case args.len:
    of 1: discard
    of 2:
      sep = extractString(args[1])
    else:
      runtimeError(E_ARGS, "split takes 2 arguments")

  let str = extractString(args[0])

  return str.split(sep).map(md).md.pack

# (downcase str)
# Makes every character in str lowercase
defBuiltin "downcase":
  if args.len != 1:
    runtimeError(E_ARGS, "downcase takes 1 arguments")

  let str = extractString(args[0])

  return str.toLower().md.pack

# (ord char)
# returns the ascii code of char or the char at index of string
defBuiltin "ord":
  if args.len != 1:
    runtimeError(E_ARGS, "ord takes 1 argument")

  let str = extractString(args[0])
  if str.len == 0:
    runtimeError(E_ARGS, "ord given an empty string")

  let ch = str[0]
  return ch.ord.md.pack

# (chr int)
# returns the ascii character of int % 256
# TODO: restrict this to printable (and some more?) characters
defBuiltin "chr":
  if args.len != 1:
    runtimeError(E_ARGS, "chr takes 1 argument")

  let num = extractInt(args[0])
  return ($num.chr).md.pack

# (insert list index new-el)
defBuiltin "insert":
  if args.len != 3:
    runtimeError(E_ARGS, "insert takes 3 arguments")

  var list = extractList(args[0])
  let index = extractInt(args[1])
  let el = args[2]

  let length = list.len

  if index in 0..length:
    list.insert(el, index)
  else:
    runtimeError(E_BOUNDS, "index $1 is out of bounds" % [$index])

  return list.md.pack

# (delete list index)
defBuiltin "delete":
  if args.len != 2:
    runtimeError(E_ARGS, "delete takes 2 arguments")

  var list = extractList(args[0])
  let index = extractInt(args[1])

  let length = list.len

  if index in -length..length-1:
    system.delete(list, index)
  else:
    runtimeError(E_BOUNDS, "index $1 is out of bounds" % [$index])

  return list.md.pack

# (set list index replacement)
# TODO: eliminate code duplication between this, insert, and delete
#  (is this even possible)
defBuiltin "set":
  if args.len != 3:
    runtimeError(E_ARGS, "set takes 3 arguments")

  var list = extractList(args[0])
  let index = extractInt(args[1])
  let el = args[2]

  let length = list.len

  if index in -length..length-1:
    if index < 0:
      list[^ -index] = el
    else:
      list[index] = el
  else:
    runtimeError(E_BOUNDS, "index $1 is out of bounds" % [$index])

  return list.md.pack

defBuiltin "get":
  var useDefault = false
  var default = nilD
  case args.len:
    of 2: discard
    of 3:
      default = args[2]
      useDefault = true
    else:
      runtimeError(E_ARGS, "get takes 2 or 3 arguments")

  let list = extractList(args[0])
  let index = extractInt(args[1])
  let length = list.len

  if index in -length..length-1:
    if index < 0:
      return list[^ -index].pack
    else:
      return list[index].pack
  else:
    if useDefault:
      return default.pack
    else:
      runtimeError(E_BOUNDS, "index $1 is out of bounds" % [$index])

# (slice list start [end])
# takes list and returns a new list of its elements from indices start to end
# if end < 0, then end is (+ (len list) end)
# (basically, -x means (x - 1) elements from the end)
#
# end defaults to -1
defBuiltin "slice":
  var args = args
  if args.len == 2:
    args.add((-1).md)

  if args.len != 3:
    runtimeError(E_ARGS, "slice takes 2 or 3 arguments")

  let list = extractList(args[0])
  let start = extractInt(args[1])
  let endv = extractInt(args[2])

  let length = list.len

  if start in 0..length - 1:
    if endv in 0..length - 1:
      return list[start..endv].md.pack
    elif endv in -length..(-1):
      return list[start..^ -endv].md.pack
    else:
      runtimeError(E_BOUNDS, "end index $1 is out of bounds." % [$endv])
  elif start == length:
    return @[].md.pack
  else:
    runtimeError(E_BOUNDS, "start index $1 is out of bounds." % [$start])

# (push list new-el)
# adds to end
defBuiltin "push":
  if args.len != 2:
    runtimeError(E_ARGS, "push takes 2 arguments")

  var list = extractList(args[0])
  let el = args[1]

  list.add(el)
  return list.md.pack

# (unshift list el)
# adds to beginning
defBuiltin "unshift":
  if args.len != 2:
    runtimeError(E_ARGS, "insert takes 2 arguments")

  var list = extractList(args[0])
  let el = args[1]

  list.insert(el, 0)
  return list.md.pack

# (setadd list el)
# Adds el to list only if it's already not contained
defBuiltin "setadd":
  if args.len != 2:
    runtimeError(E_ARGS, "setadd takes 2 arguments")

  var list = extractList(args[0])
  let el = args[1]

  if el notin list:
    list.add(el)

  return list.md.pack

# (setremove list el)
# Removes el from list
defBuiltin "setremove":
  if args.len != 2:
    runtimeError(E_ARGS, "setremove takes 2 arguments")

  var list = extractList(args[0])
  let el = args[1]

  for idx, val in list:
    if el == val:
      system.delete(list, idx)
      break

  return list.md.pack

# (in list el)
# returns index of el in list, or -1
defBuiltin "in":
  if args.len != 2:
    runtimeError(E_ARGS, "in takes 2 arguments")

  let list = extractList(args[0])
  let el = args[1]

  return list.find(el).md.pack

# (range start end)
# returns '(start start+1 start+2 ... end-1 end)
# removes end - start + 1 ticks from the current task's ticks left
defBuiltin "range":
  if args.len != 2:
    runtimeError(E_ARGS, "range takes 2 arguments")

  let start = extractInt(args[0])
  let endv = extractInt(args[1])

  let numberOfTicks = endv - start + 1
  task.tickCount += numberOfTicks

  return toSeq(start..endv).map(md).md.pack

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

    if isNil(parent) or parent == holder:
      return nilD.pack

    let verbd = symtable["verb"]
    if not verbd.isType(dStr):
      return nilD.pack
    let verbName = verbd.strVal

    let verb = parent.getVerb(verbName)

    if isNil(verb):
      runtimeError(E_VERBNF, "Pass failed, verb is not inherited.")

    discard self.verbCallRaw(verb, owner, args,
                       symtable = symtable, holder = parent, callback = task.id)

    return 1.pack

  if phase == 1:
    let verbResult = args[^1]
    return verbResult.pack

# (gensalt [rounds])
# generates a random salt to use
# If rounds is not provided, then #0.default-salt-rounds is used
# If that's not there, then 5 is used
# The cap is set to 10 in the interest of the lag hashing passwords with big salts
# creates
defBuiltin "gensalt":
  var rounds: int
  case args.len:
    of 0:
      let prop = world.getGlobal("default-salt-rounds")
      rounds = if not prop.isType(dInt): 5 else: prop.intVal
    of 1:
      rounds = extractInt(args[0])
    else:
      runtimeError(E_ARGS, "gensalt takes 0 or 1 arguments")

  if rounds > 10 or rounds < 1:
    runtimeError(E_ARGS, "number of salt rounds needs to be 1..10")

  return genSalt(rounds.int8).md.pack

# (phash password salt)
# hashes the password with the salt using bcrypt
defBuiltin "phash":
  if args.len != 2:
    runtimeError(E_ARGS, "phash takes 2 arguments")

  let pass = extractString(args[0])
  let salt = extractString(args[1])

  return hash(pass, salt).md.pack

randomize()

# (random [min] max)
# generates a random number from min..max-1
defBuiltin "random":
  var args = args
  var nmin, nmax: int

  case args.len:
    of 1:
      nmin = 0
      nmax = extractInt(args[0])
    of 2:
      nmin = extractInt(args[0])
      nmax = extractInt(args[1])
    else:
      runtimeError(E_ARGS, "random takes 2 arguments")

  return (random(nmax - nmin) + nmin).md.pack
