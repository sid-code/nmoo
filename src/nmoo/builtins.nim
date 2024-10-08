## This file contains definitions for most builtin functions.
##
## See `builtindef.nim` for the template that is used to define
## builtins. It essentially just adds a proc to a table whose keys are
## the names of the builtins.
##
## The builtin definitions make heavy use of templates that affect
## control flow. I'm still not sure if this was a good idea, but in
## practice builtin function definitions are short (with a few
## exceptions) so the templates might actually not affect the
## readability of the code much.
##
## The templates affect the control flow by using `return`. This
## returns from the builtin proc (not the template).
##
## IDEA: maybe prefix the templates with some obnoxious string so that
## it's obvious they affect control flow?
{.used.}

import strutils
import tables
import sequtils
import math
import nre
import options
import times
import std/sets

import types
import objects
import verbs
import scripting
import tasks
import persist
import compile
import querying
import server
import builtindef

# for hashing builtins
import bcrypt

# Provided by bcrypt, but not exported; used for the `random` builtin
# TODO: find an alternative?
proc arc4random: int32 {.importc: "arc4random".}

proc strToType(str: string): tuple[b: bool, t: MDataType] =
  case str.toLowerAscii():
    of "int": return (true, dInt)
    of "float": return (true, dFloat)
    of "str": return (true, dStr)
    of "sym": return (true, dSym)
    of "obj": return (true, dObj)
    of "list": return (true, dList)
    of "table": return (true, dTable)
    of "err": return (true, dErr)
    of "nil": return (true, dNil)
    else: return (false, dInt)

proc typeToStr(typ: MDataType): string =
  case typ:
    of dInt:   "int"
    of dFloat: "float"
    of dStr:   "str"
    of dSym:   "sym"
    of dObj:   "obj"
    of dList:  "list"
    of dTable: "table"
    of dErr:   "err"
    of dNil:   "nil"

# turns all %s to \s because %s are easier to use within the server
proc escapeRegex(pat: string): Regex =
  re(pat.replace(re"%(.)", proc (m: RegexMatch): string =
    let capt = m.captures[0]
    if capt == "%":
      return "%"
    else:
      return "\\" & capt))

# Convenience templates: these are to be called from builtins to extract
# values from their arguments but raising an error if they're not of the
# correct data type.
template extractInt(d: MData): int =
  let dV = d
  checkType(dV, dInt)
  dV.intVal

template extractFloat(d: MData): float =
  let dV = d
  var res: float
  if dV.isType(dFloat):
    res = dV.floatVal
  elif dV.isType(dInt):
    res = dV.intVal.float
  else:
    let msg = "$#: expected argument of type int or float, instead got $#"
    runtimeError(E_TYPE, msg % [bname, typeToStr(dV.dtype)])

  res

template extractString(d: MData): string =
  let dV = d
  checkType(dV, dStr)
  dV.strVal
template extractList(d: MData): seq[MData] =
  let dV = d
  checkType(dV, dList)
  dV.listVal
template extractTable(d: MData): Table[MData, MData] =
  let dV = d
  checkType(dV, dTable)
  dV.tableVal
template extractError(d: MData): tuple[e: MError, s: string] =
  let dV = d
  checkType(dV, dErr)
  (dV.errVal, dV.errMsg)

template extractObjectID(objd: MData): ObjID =
  let objdV = objd
  checkType(objdV, dObj)
  objdV.objVal

template extractObject(objd: MData): MObject =
  let objdV = objd
  checkType(objdV, dObj)
  let obj = world.dataToObj(objdV)
  if not obj.isSome():
    runtimeError(E_ARGS, "invalid object " & $objdV)

  obj.get()

# Error-checking templates:
# Builtins need to check permissions and types. If any of these
# checks fail, then a error is thrown in the program.
template checkForError(value: MData) =
  let valueV = value
  if valueV.isType(dErr) and valueV.errVal != E_NONE:
    return valueV.pack

# If option is empty, do something with the control flow (like return)
template orElse[T](opt: Option[T], body: untyped): T =
  if opt.isNone:
    body
  else:
    opt.unsafeGet

template runtimeError(error: MError, message: string) =
  return error.md(message).pack

template checkType(value: MData, expected: MDataType, ifnot: MError = E_TYPE) =
  let valueV = value
  let expectedV = expected
  if not valueV.isType(expectedV):
    runtimeError(ifnot,
      bname & ": expected argument of type " & typeToStr(expectedV) &
        " instead got " & typeToStr(valueV.dType))

template isWizardT: bool = isWizard(task.owner)
template owns(what: MObject): bool = task.owner.owns(what)

template checkOwn(what: MObject) =
  let whatV = what
  let obj = task.owner
  if not obj.owns(whatV):
    runtimeError(E_PERM, obj.toObjStr() & " doesn't own " & whatV.toObjStr())

template checkRead(what: MObject) =
  let whatV = what
  let obj = task.owner
  if not obj.canRead(whatV):
    runtimeError(E_PERM, obj.toObjStr() & " cannot read " & whatV.toObjStr())
template checkWrite(what: MObject) =
  let whatV = what
  let obj = task.owner
  if not obj.canWrite(whatV):
    runtimeError(E_PERM, obj.toObjStr() & " cannot write " & whatV.toObjStr())
template checkRead(what: MProperty) =
  let whatV = what
  let obj = task.owner
  if not obj.canRead(whatV):
    runtimeError(E_PERM, obj.toObjStr() & " cannot read property: " & whatV.name)
template checkWrite(what: MProperty) =
  let whatV = what
  let obj = task.owner
  if not obj.canWrite(whatV):
    runtimeError(E_PERM, obj.toObjStr() & " cannot write property: " & whatV.name)
template checkRead(what: MVerb) =
  let whatV = what
  let obj = task.owner
  if not obj.canRead(whatV):
    runtimeError(E_PERM, obj.toObjStr() & " cannot read verb: " & whatV.names)
template checkWrite(what: MVerb) =
  let whatV = what
  let obj = task.owner
  if not obj.canWrite(whatV):
    runtimeError(E_PERM, obj.toObjStr() & " cannot write verb: " & whatV.names)
template checkExecute(what: MVerb) =
  let whatV = what
  let obj = task.owner
  if not obj.canExecute(verb):
    runtimeError(E_PERM, obj.toObjStr() & " cannot execute verb: " & whatV.names)

# This is so that strings can be echoed without the quotes surrounding them.
proc toEchoString*(x: MData): string =
  if x.isType(dStr):
    x.strVal
  else:
    $x

## ::
##
##   (echo arg1:Any ...):List
##
## Takes any number of arguments of any type and outputs them to object on
## which the verb is being run on. Each argument is passed to the
## `toEchoString` proc before being output.
##
## ::
##
##   (let ((obj #5))
##     (echo "object " obj " is an object"))
##
##   ;;; This outputs "object #5 is an object" to self
##
## The argument list is simply returned.
##
## NOTE: This is probably not what you want to call because you want to echo to
## the player who typed the verb. If this builtin is called from a verb running
## on some object that isn't a player, nobody will see he message. (look into
## the ``notify`` builtin)
defBuiltin "echo":
  var
    newArgs: seq[MData] = @[]
    sendstr = ""
  for arg in args:
    let res = arg
    sendstr &= res.toEchoString()
    newArgs.add(res)
  self.send(sendstr)
  return newArgs.md.pack

## ::
##
##   (notify player:Obj message:Str):Str
##
## Sends a line of output ``message`` to ``player``. There are some
## restrictions, however. The programmer who's permissions this task running
## with must either own ``player`` or be a wizard. If one of these conditions
## isn't met, `E_PERM` is raised.
##
## The value returned is the string that was printed.
defBuiltin "notify":
  if args.len != 2:
    runtimeError(E_ARGS, "notify takes 2 arguments")

  let who = extractObject(args[0])
  let msg = extractString(args[1])

  if task.owner != who and not isWizardT():
    runtimeError(E_PERM, "$# cannot notify $#" % [$owner, $who])

  who.send(msg)
  return msg.md.pack

## ::
##
##   (do expr1:Any expr2:Any ...):Any
##
## This builtin evaluates each expression passed to it in order and returns the
## result of the last one evaluated. This is one way to do multiple things in a
## lambda:
##
## ::
##
##   (lambda (x)
##     (do
##      (mangle x)
##      (eat x)
##      (clean-up)))
defBuiltin "do":
  var newArgs: seq[MData] = @[]
  for arg in args:
    let res = arg
    newArgs.add(res)

  if newArgs.len > 0:
    return newArgs[^1].pack
  else:
    return @[].md.pack

## ::
##
##   (parse code:String):Any
##
## Parses ``code`` and returns the object that it was

defBuiltin "parse":
  if args.len != 1:
    runtimeError(E_ARGS, "parse takes 1 argument")

  let code = extractString(args[0])

  var parser = newParser(code)
  let parsed = parser.parseAtom()
  checkForError(parser.error)

  return parsed.pack

## ::
##
##   (eval form:Any):Any
##
## Treats ``form`` as actual code, evaluates it, and returns the result.
## Internally, the code is compiled and loaded into a whole new task which is
## then run. **Use sparingly**.
defBuiltin "eval":
  if phase == 0:
    if args.len != 1:
      runtimeError(E_ARGS, "eval takes 1 argument")

    let form = args[0]

    # Design choice: the compiler runs with the permissions of THE PLAYER WHO TYPED THE COMMAND.
    # This is used for executing compile-time code.
    let instructions = compileCode(form, player)
    checkForError(instructions.error)

    discard world.addTask("eval", self, player, caller, owner, symtable, instructions,
                          taskType = task.taskType, callback = some(task.id))
    task.setStatus(tsAwaitingResult)
    return 1.pack
  if phase == 1:
    return args[1].pack

## ::
##
##   (settaskperms new-perms:Obj):Obj
##
## Sets the current task's permissions to those of ``new-perms`` (which is also
## returned). The main use of this is the idiom:
##
## ::
##
##   (setttaskperms caller)
##
## To make sure that a verb is no longer running with wizard permissions and
## doesn't royally screw things up.
defBuiltin "settaskperms":
  if args.len != 1:
    runtimeError(E_ARGS, "settaskperms takes 1 argument")

  let newPerms = extractObject(args[0])
  if not isWizardT() and task.owner != newPerms:
    runtimeError(E_PERM, "$# can't set task perms to $#" %
                  [task.owner.toObjStr(), newPerms.toObjStr()])

  task.owner = newPerms
  return newPerms.md.pack

## ::
##
##   (callerperms):Obj
##
## Returns the object whose permissions the current task is running
## with.
defBuiltin "callerperms":
  if args.len != 0:
    runtimeError(E_ARGS, "callerperms takes no arguments")

  return task.owner.md.pack

## ::
##
##   (read [player:Obj]):Str
##
## Reads a line of input from ``player``'s connection (if omitted it reads
## from the player who entered the command that started this task).
##
## The programmer must own ``player`` or be a wizard or ``E_PERM`` is raised.
##
## **Use extremely sparingly**.
defBuiltin "read":
  if phase == 0:
    var who: MObject
    case args.len:
      of 0:
        who = player
      of 1:
        who = extractObject(args[0])
      else:
        runtimeError(E_ARGS, "read takes 0 or 1 arguments")

    if not isWizardT() and who != caller:
      runtimeError(E_PERM, "you don't have permission to read from that connection")

    let client = findClient(who)
    if client.isNone:
      runtimeError(E_ARGS, who.toObjStr() & " has not been connected to!")

    world.askForInput(tid, client.get)
    return 1.inputPack
  elif phase == 1:
    # sanity check
    if args.len != 1:
      runtimeError(E_ARGS, "read failed")

    return args[0].pack

## ::
##
##   (err error-type:Err message:Str)
##
## Raises an error with type ``error-type`` and message ``message``.
##
## Example of use::
##
##   (if (> count 10)
##       (err E_ARGS "too many")
##       (do-something-with count))
defBuiltin "err":
  if args.len != 2:
    runtimeError(E_ARGS, "err takes 2 arguments")

  var err = args[0]
  checkType(err, dErr)

  let msg = extractString(args[1])

  err.errMsg = msg
  err.trace = @[]
  return err.pack

## ::
##
##   (erristype err:Err err2:Err):Int
##
## Checks whether ``err`` has same error type as ``err2``. If true, it returns
## ``1``, if not ``0``. This is useful in ``try`` expressions:
##
## ::
##
##   (try (error-prone-code)
##        (if (erristype error E_PERM)     ; note: in catch block, `error` holds the error
##            (echo "Permission error")
##            (echo "Some other kind of error)))
defBuiltin "erristype":
  if args.len != 2:
    runtimeError(E_ARGS, "erristype takes 2 arguments")

  var (err, _) = extractError(args[0])
  var (err2, _) = extractError(args[1])

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
  VerbInfo = tuple[owner: ObjID, perms: string, newName: string]
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
  res.owner = extractObjectID(ownerd)

  let perms = extractString(info[1])
  res.perms = perms

  if info.len == 3:
    let newName = extractString(info[2])
    res.newName = newName

  res

template objSpecFromData(ospd: MData): ObjSpec =
  let str = extractString(ospd)
  let ospec = strToObjSpec(str)

  if not ospec.isSome():
    runtimeError(E_ARGS, "invalid object spec '$1'" % str)

  ospec.get()

template prepSpecFromData(pspd: MData): PrepType =
  let str = extractString(pspd)
  let pspec = strToPrepSpec(str)

  if not pspec.isSome():
    runtimeError(E_ARGS, "invalid preposition spec '$1'" % str)

  pspec.get()

template verbArgsFromInput(info: seq[MData]): VerbArgs =
  if info.len != 3:
    runtimeError(E_ARGS, "verb args must be a list of size 3")

  var vargs: VerbArgs
  vargs.doSpec = objSpecFromData(info[0])
  vargs.prepSpec = prepSpecFromData(info[1])
  vargs.ioSpec = objSpecFromData(info[2])

  vargs

proc setInfo(prop: MProperty, info: PropInfo) =
  prop.owner = info.owner
  prop.pubRead = "r" in info.perms
  prop.pubWrite = "w" in info.perms
  prop.ownerIsParent = "c" in info.perms

  prop.name = info.newName

proc setInfo(verb: MVerb, info: VerbInfo) =
  verb.owner = info.owner
  verb.pubRead = "r" in info.perms
  verb.pubWrite = "w" in info.perms
  verb.pubExec = "x" in info.perms

  verb.names = info.newName

proc setArgs(verb: MVerb, args: VerbArgs) =
  verb.doSpec = args.doSpec
  verb.prepSpec = args.prepSpec
  verb.ioSpec = args.ioSpec

template getPropOn(objd, propd: MData, die = true, useDefault = false,
                   default = nilD, all = false, inherited = true):
                     tuple[o: MObject, p: MProperty] =
  let objd2 = objd
  let obj = extractObject(objd2)
  var res: tuple[o: MObject, p: MProperty]

  let
    propName = extractString(propd)
    objPropO = obj.getPropAndObj(propName, all)

  if objPropO.isNone:
    if useDefault:
      res = (nil, newProperty("default", default, nil))
    else:
      if die:
        runtimeError(E_PROPNF, "property $1 not found on $2" % [propName, $obj.toObjStr()])
      else:
        return nilD.pack
  else:
    let (objOn, propObj) = objPropO.unsafeGet
    if not all and not inherited and obj.propIsInherited(propObj):
      runtimeError(E_PROPNF, "property $1 not found on $2" % [propName, $obj.toObjStr()])

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

    let resO = obj.getVerbAndObj(verbdesc, all)

    if isNone(resO):
      if die:
        runtimeError(E_VERBNF, "verb $1 not found on $2" % [verbdesc, obj.toObjStr()])
      else:
        return nilD.pack

    res = resO.unsafeGet
  elif verbdescd2.isType(dInt):
    let verbnum = verbdescd2.intVal

    if verbnum >= obj.verbs.len or verbnum < 0:
      runtimeError(E_VERBNF, "verb index $# out of range" % $verbnum)

    res = (obj, obj.verbs[verbnum])
  else:
    runtimeError(E_ARGS, "verb indices can only be strings or integers")

  res

## ::
##
##   (getprop obj:Obj prop:Str):Any
##
## Gets the property `prop` of `obj`. If the property doesn't exist,
## ``E_PROPNF`` is raised. The programmer should also have read access on the
## object. If not, ``E_PERM`` is raised.
##
## There is a shorthand for this builtin but it must be used carefully because
## it is rudimentary:
##
## ::
##
##   (echo "The value of #5.name is " #5.name)
##
## instead of:
##
## ::
##
##   (echo "The value of #5.name is " (getprop #5 "name"))
##
## In short, ``obj.prop`` expands to ``(getpop obj "prop")``, but don't expect
## it to work with verb calls: ``obj.prop:verb()`` **will not** work and neither
## will shenanigans like ``(callerperms).name``. However, these can be nested:
## ``obj.location.name`` will work.
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

## ::
##
##   (setprop obj:Obj prop:Str new-val:Any):Any
##
## Companion of ``getprop``. It sets the property described by ``prop`` on
## ``obj`` to ``new-val``. If ``prop`` cannot be found on ``obj`` then
## ``E_PROPNF`` is raised. If the programmer doesn't have write access on
## ``obj`` then ``E_PERM`` is raised. The value returned is the value that was
## set.
##
## There is no cute shorthand for this builtin to avoid overcomplicating the
## syntax.
defBuiltin "setprop":
  if args.len != 3:
    runtimeError(E_ARGS, "setprop takes 3 arguments")

  let objd = args[0]
  let obj = extractObject(objd)

  let newVal = args[2]

  let propName = extractString(args[1])
  var oldProp = obj.getProp(propName, all = false)

  if isNil(oldProp):
    checkWrite(obj)
    let (newProp, error) = obj.setProp(propName, newVal)
    checkForError(error)

    newProp.owner = task.owner
    world.persist(obj)
  else:
    checkWrite(oldProp)
    # Even though we could just do oldProp.val = newVal,
    # we need to call setProp. This is because there are
    # some special properties whose types are enforced.
    let (_, error) = obj.setProp(propName, newVal)
    checkForError(error)

    if propName == "owner":
      # The following line is safe because setProp would have returned an error
      # if the property "owner" was set to a non-object
      let newOwner = newVal.extractObject()
      for prop in obj.props:
        if prop.ownerIsParent:
          prop.owner = newOwner

    world.persist(obj)

  return newVal.pack

## ::
##
##   (delprop obj:Obj prop:Str):Obj
##
## This builtin is for deleting a property from an object and all its
## descendants. If the property is not found, then ``E_PROPNF`` is raised. If
## the programmer does not have write permissions on ``obj`` then ``E_PERM`` is
## raised.  The return value is ``obj``.
defBuiltin "delprop":
  if args.len != 2:
    runtimeError(E_ARGS, "delprop takes 2 arguments")

  let (obj, prop) = getPropOn(args[0], args[1], inherited = false)

  for moddedObj, deletedProp in obj.delPropRec(prop).items:
    discard deletedProp
    world.persist(moddedObj)

  return obj.md.pack

## ::
##
##   (getpropinfo obj:Obj prop:Str):List
##
## Retrieves information about the property referred to by ``prop`` on ``obj``.
## This information is a list whose first element is the owner of the property.
## The second element is a string of characters taken from the set: ``r``, ``w`,
## and ``c``. ``r`` signifies that the property is publicly readable. ``w``
## signifies that the property is publicly writable. ``c`` signifies that the
## owner of this property in this object's descendants should be the owner of
## the child, not the owner of this object.
##
## If the property doesn't exist, then ``E_PROPNF`` is raised. If the
## programmer does not have read access to ``obj`` then ``E_PERM`` is raised.
defBuiltin "getpropinfo":
  if args.len != 2:
    runtimeError(E_ARGS, "getpropinfo takes 2 arguments")

  let (obj, propObj) = getPropOn(args[0], args[1])
  discard obj

  checkRead(propObj)

  return extractInfo(propObj).pack


## ::
##
##   (setpropinfo obj:Obj prop:Str new-info:List):Obj
##
## Sets the property ``prop`` on ``obj``'s info to ``new-info``. ``new-info``
## is specified by ``(new-owner:Obj new-perms:Str [new-name:Str])``.
## ``new-perms`` is in the same format as the part of the result of
## ``getpropinfo``.
##
## If the property does not exist, ``E_PROPNF`` is raised and if the programmer
## does not have write access to the ``obj`` then ``E_PERM`` is raised.
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

## ::
##
##   (props obj:Obj):List
##
## Returns a list of properties defined directly on ``obj``. If the programmer
## does not have read access to ``obj``, ``E_PERM`` is raised.
defBuiltin "props":
  if args.len != 1:
    runtimeError(E_ARGS, "props takes 1 argument")

  let objd = args[0]
  let obj = extractObject(objd)

  checkRead(obj)

  let res = obj.getOwnProps().map(md)

  return res.md.pack

## ::
##
##   (verbs obj:Obj):List
##
## Returns a list of verbs defined directly on ``obj``. If the programmer does
## not have read access to ``obj``, ``E_PERM`` is raised.
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


## ::
##
##   (getverbinfo obj:Obj verb:Str):List
##   (getverbinfo obj:Obj verb-index:Int):List
##
## See the documentation of ``getpropinfo`` for the format of the list
## returned.  The only difference is that instead of ``c`` in the permissions
## there is ``x`` which signifies if the verb is publicly executable.
##
## If ``verb`` is not found on ``obj``, then ``E_VERBNF`` is raised. If the
## programmer does not have read permissions on the object and the verb then
## ``E_PERM`` is raised.
defBuiltin "getverbinfo":
  if args.len != 2:
    runtimeError(E_ARGS, "getverbinfo takes 2 arguments")

  let (obj, verb) = getVerbOn(args[0], args[1])
  discard obj
  checkRead(verb)

  return extractInfo(verb).pack

## ::
##
##   (setverbinfo obj:Obj verb:Str new-info:List):Obj
##   (setverbinfo obj:Obj verb-index:Int new-info:List):Obj
##
## This is the companion verb to ``getverbinfo``. The ``new-info`` list
## is of the same format as the return value of ``getverbinfo`` but can
## contain one extra element at the end that specifies a new list of names
## for the verb in a string.
##
## The return value is the ``obj``.
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

## ::
##
##   (getverbargs obj:Obj verb:Str):List
##   (getverbargs obj:Obj verb-index:Int):List
##
## This builtin returns the arguments that the verb is supposed to operate on.
## It will be in the list of the form:
##
## ::
##
##   (direct-object preposition indirect-object)
##
## If ``verb`` does not exist on ``obj`` then ``E_VERBNF`` is raised. If the
## programmer does not have read permissions on ``verb`` then ``E_PERM`` is
## raised.
defBuiltin "getverbargs":
  if args.len != 2:
    runtimeError(E_ARGS, "getverbargs takes 2 arguments")

  let (obj, verb) = getVerbOn(args[0], args[1])
  discard obj
  checkRead(verb)

  return extractArgs(verb).pack

## ::
##
##   (setverbargs obj:Obj verb:Str new-args:List):Obj
##   (setverbargs obj:Obj verb-index:Int new-args:List):Obj
##
## This is the companion verb to ``getverbargs``. ``setverbinfo`` is to
## ``getverbinfo`` as this verb is to ``getverbargs``. The signature above
## should be enough to infer how to use it. Write access is required or
## ``E_PERM`` is raised.
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

## ::
##
##   (addverb obj:Obj new-verb-names:Str):Obj
##
## Adds a verb to ``obj`` with names specified by ``new-verb-names``. The new
## verb's owner will be the programmer of this verb. If the programmer does not
## have write permissions on ``obj``, ``E_PERM`` is raised. The return value of
## this verb is the object that gained a new verb.
defBuiltin "addverb":
  if args.len != 2:
    runtimeError(E_ARGS, "addverb takes 2 arguments")

  let objd = args[0]
  let obj = extractObject(objd)

  checkWrite(obj)

  let names = extractString(args[1])

  var verb = newVerb(
    names = names,
    owner = owner.id,
  )

  checkForError(verb.setCode("", owner))

  discard obj.addVerb(verb)
  world.persist(obj)

  return objd.pack

## ::
##
##   (delverb obj:Obj verb:Str):Obj
##   (delverb obj:Obj verb-index:Int):Obj
##
## Deletes the verb with name ``verb`` or index ``verb-index`` off ``obj`` and
## all of its descendants. If the string ``verb`` does not point to any verb on
## ``obj`` then ``E_VERBNF`` is raised. If the programmer doesn't have write
## access to the ``obj`` then ``E_PERM`` is raised.
##
## The return value is the ``obj``.
defBuiltin "delverb":
  if args.len != 2:
    runtimeError(E_ARGS, "delverb takes 2 arguments")

  let (obj, verb) = getVerbOn(args[0], args[1])

  checkWrite(obj)

  if isNil(verb) or verb.inherited:
    runtimeError(E_VERBNF, "$1 does not define a verb $2" % [obj.toObjStr, $args[1]])

  discard obj.delVerb(verb)
  world.persist(obj)

  return obj.md.pack


defBuiltin "loadverb":
  if args.len != 2:
    runtimeError(E_ARGS, "loadverb takes 2 arguments (object and verb name)")

  let (obj, verb) = getVerbOn(args[0], args[1])
  checkWrite(verb)

  let resultd = readVerbCode(world, obj, verb, player)
  checkForError(resultd)
  world.persist(obj)
  return verb.names.md.pack

## ::
##
##   (setverbcode obj:Obj verb:Str new-code:Str):Obj
##   (setverbcode obj:Obj verb-index:Int new-code:Str):Obj
##
## This builtin is used to set the source code of a verb. The verb should be
## unambiguously referred to by ``verb`` or ``verb-index`` on ``obj`` to avoid
## any issues. The programmer of this task must have write permissions on
## the verb or ``E_PERM`` is rasied.
##
## If the verb fails to parse, ``E_PARSE`` is raised with the appropriate
## message.
##
## If the verb fails to compile, ``E_COMPILE`` is raised with the appropriate
## message.
defBuiltin "setverbcode":
  if args.len != 3:
    runtimeError(E_ARGS, "setverbcode takes 3 arguments")

  let (obj, verb) = getVerbOn(args[0], args[1])
  checkWrite(verb)

  let newCode = extractString(args[2])

  let err = verb.setCode(newCode, world.byId(verb.owner).get)
  checkForError(err)
  world.persist(obj)
  return nilD.pack

## ::
##
##   (getverbcode obj:Obj verb:Str):Str
##   (getverbcode obj:Obj verb-index:Int):Str
##
## Retrieves the code for the verb ``verb`` on ``obj`` (or the verb pointed to
## by ``verb-index``). If the programmer does not have read permissions on the
## verb, ``E_PERM`` is raised.`
defBuiltin "getverbcode":
  if args.len != 2:
    runtimeError(E_ARGS, "getverbcode takes 2 arguments")

  let (obj, verb) = getVerbOn(args[0], args[1])
  discard obj

  checkRead(verb)

  return verb.code.md.pack

# EXPERIMENTAL
defBuiltin "getverbbytecode":
  if args.len != 2:
    runtimeError(E_ARGS, "getverbcode takes 2 arguments")

  let (obj, verb) = getVerbOn(args[0], args[1])
  discard obj

  checkRead(verb)

  var res: seq[MData] = @[]
  for i in verb.compiled.code:
    res.add( @[($i.itype)[2..^1].mds, i.operand, i.pos.line.md, i.pos.col.md].md )

  return res.md.pack

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

    var res: Option[TaskID]
    verbCall(res, dest, "accept", player, caller, @[what.md], callback = some(tid))
    if res.isNone: # We were not able to call the verb
      runtimeError(E_FMOVE, "$1 didn't accept $2" % [dest.toObjStr(), what.toObjStr()])

    task.setStatus(tsAwaitingResult)
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
      var res: Option[TaskID]
      verbCall(res, dest, "exitfunc", player, caller, @[what.md], callback = some(tid))
      if res.isNone:
        # This means the verb didn't exist, but that's not an issue.
        phase += 1
      else:
        task.setStatus(tsAwaitingResult)
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

    var res: Option[TaskID]
    verbCall(res, dest, "enterfunc", player, caller, @[what.md], callback = some(tid))
    if res.isNone:
      phase += 1
    else:
      task.setStatus(tsAwaitingResult)
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

  var res: Option[TaskID]
  verbCall(res, newObj, "initialize", player, caller, @[])

  newObj.owner = newOwner
  # TODO: some way to keep track of an object's owner objects

  world.persist(newObj)
  world.persist(parent)

  return newObj.md.pack

# (playerflag obj [new-val])
# If new-val is not specified, this builtin returns obj's
# player bit (1 if it's a player, 0 if not.) If it is specified,
# obj's player's bit is set to it if task's owner is a wizard
defBuiltin "playerflag":
  case args.len:
    of 1:
      let obj = extractObject(args[0])
      return obj.isPlayer.int.md.pack
    of 2:
      let obj = extractObject(args[0])
      if not isWizardT():
        runtimeError(E_PERM, "only wizards can set the player flag")
      let newVal = extractInt(args[1])
      if newVal != 0 and newVal != 1:
        runtimeError(E_ARGS, "player flag can only be set to 0 or 1")
      obj.isPlayer = newVal == 1
      return obj.md.pack
    else:
      runtimeError(E_ARGS, "playerflag takes 1 or 2 arguments")

## ::
##
##   (level obj:Obj):Int
##
## Returns ``obj``'s permission level.
##
## ::
##
##    0   wizard
##    1   programmer
##    2   builder
##    3   regular
defBuiltin "level":
  if args.len != 1:
    runtimeError(E_ARGS, "level takes 1 argument")

  let obj = extractObject(args[0])
  return obj.level.md.pack

## ::
##
##   (setlevel obj:Obj new-level:Int):Int
##
## Sets ``obj``'s level to ``new-level``. If the level is not within ``0..3``
## then ``E_ARGS`` is raised. If the programmer isn't a wizard then ``E_PERM``
## is raised.
##
## Examples::
##
##   (setlevel #59 3) ; => 3
##   (setlevel #59 5) ; => E_ARGS
##   (setlevel #59 3) ; => E_PERM (if the programmer wasn't a wizard)
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

    let contents = obj.getContents()
    for contained in contents:
      # This is actually how LambdaMOO does it: no call to the move
      # builtin instead a raw exitfunc call. I find this somewhat
      # dubious but actually making a builtin call is difficult because
      # of the phase mechanism.
      discard contained.moveTo(nowhere)
      var res: Option[TaskID]
      verbCall(res, obj, "exitfunc", player, caller, @[contained.md])
      world.persist(contained)

    var res: Option[TaskID]
    verbCall(res, obj, "recycle", player, caller, @[], callback = some(tid))
    if res.isNone:
      # We don't actually care if the verb "recycle" exists
      phase = 1
    else:
      task.setStatus(tsAwaitingResult)
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

defBuiltin "maxobj":
  if args.len != 0:
    runtimeError(E_ARGS, "maxobj takes no arguments")

  return (world.getObjects()[].len - 1).md.pack

## ::
##
##   (renumber obj:Obj):Obj
##
## Assigns a new object number to ``obj``. Updates all mentions of ``obj`` in
## the parent/child hierarchy and location/contents hierarchy but nowhere else.
## The new number will be the lowest available object number that isn't equal
## to ``obj``'s number.
##
## This should **not** be used unless you know what you're doing.
##
## For the following examples, Imagine ``#10`` has a child ``#12`` and an
## object ``#11`` in its contents. Naturally, ``#11`` has ``location`` set to
## ``#10`` and ``#12``'s parent is ``#10``.
##
## Examples::
##
##   (renumber #10)  ; => #13  (#0 - #9 are already taken)
##   (getprop #10 "contents") ; => E_ARGS  (#10 doesn't exist anymore!)
##   (getprop #13 "contents") ; => (#12)
##   (getprop #12 "location") ; => (#13)
##   (parent #11) ; => #13
##
defBuiltin "renumber":
  runtimeError(E_BUILTIN, "renumber not implemented yet!")

  # if args.len != 1:
  #   runtimeError(E_ARGS, "renumber takes 1 argument")

  # if not isWizardT():
  #   runtimeError(E_PERM, "only wizards can renumber objects")

  # let obj = extractObject(args[0])
  # let worldObjects = world.getObjects
  # var newNumber = worldObjects[].len

  # for idx, wobj in worldObjects[]:
  #   if isNil(wobj):
  #     newNumber = idx

  # let currentNumber = obj.getID().int
  # world.dbDelete(obj)

  # obj.id = ObjID(newNumber)


## ::
##
##   (parent obj:Obj):Obj
##
## Returns the parent object of ``obj``.
##
## Examples::
##
##   (parent #5) ; => #1
##
defBuiltin "parent":
  if args.len != 1:
    runtimeError(E_ARGS, "parent takes 1 argument")

  let obj = extractObject(args[0])
  return obj.parent.md.pack

## ::
##
##   (children obj:Obj):List
##
## Returns a list of ``obj``'s children. Only immediate children are returned,
## not children of these children.
##
## Examples::
##
##   (children #1) ; => (#2 #4 #8 #10 #45 #90)  (arbitrary example)
defBuiltin "children":
  if args.len != 1:
    runtimeError(E_ARGS, "children takes 1 argument")

  let obj = extractObject(args[0])
  return obj.children.map(md).md.pack

defBuiltin "setparent":
  if args.len != 2:
    runtimeError(E_ARGS, "setparent takes 2 arguments")

  var obj = extractObject(args[0])
  let oldParent = obj.parent

  let newParent = extractObject(args[1])
  if not newParent.fertile and not isWizardT():
    runtimeError(E_PERM, "cannot create child of infertile parent")

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

# (query player str)
# Queries for `str` from `player`'s perspective
# It just wraps the query proc in querying.nim
defBuiltin "query":
  if args.len != 2:
    runtimeError(E_ARGS, "query takes 2 arguments")

  let who = extractObject(args[0])
  let str = extractString(args[1])

  if not (isWizardT() or owns(who) or who == player):
    runtimeError(E_PERM, "cannot query from perspective of " & player.toObjStr())

  return who.query(str).map(md).md.pack

## ::
##
##   (istype x:Any typedesc:Str):Int
##
## Checks if ``x`` is of the type represented by the string ``typedesc``.
## Possible values of ``typedesc`` are::
##
##   int        integer
##   float      floating point number
##   str        string
##   sym        symbol
##   obj        object
##   list       list of anything
##   err        error
##   nil        the value 'nil'
##
## If an invalid type is given, then ``E_ARGS`` is raised.  If ``x`` is indeed
## of the type described by ``typedesc`` then ``1`` is returned. If not, ``0``
## is.
##
## Examples::
##
##   (istype "hello world" "str") ; => 1
##   (istype 5 "int")             ; => 1
##   (istype #100 "str")          ; => 0
##   (istype nil "nil")           ; => 1
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

## ::
##
##   (valid obj:Obj):Int
##
## Check if ``obj`` is valid, meaning it actually refers to an object in the
## database. If so, ``1`` is returned. If not, ``0`` is.
##
## Examples::
##
##   (valid #0) ; => 1
##   (valid #49293) ; => 0  (assuming there isn't a #49293, of course)
defBuiltin "valid":
  if args.len != 1:
    runtimeError(E_ARGS, "valid takes one argument")

  let objd = args[0]
  checkType(objd, dObj)
  let objO = world.dataToObj(objd)
  if objO.isSome():
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

  if phase == 0:
    if args.len > 3:
      runtimeError(E_ARGS, "verbcall takes 2 or 3 arguments")

    let cargs = extractList(args[2])

    checkExecute(verb)

    var verbTask: Option[TaskID]
    verbCallRaw(
      verbTask,
      obj,
      verb = verb,
      player = player,
      caller = self,
      cargs,
      symtable = symtable,
      holder = holder,
      taskType = task.taskType,
      callback = some(tid)
    )

    if verbTask.isNone:
      runtimeError(E_VERBNF, "verb $#:$# has not been compiled (perhaps it failed earlier?)" %
                                [obj.toObjStr(), verb.names])
    task.setStatus(tsAwaitingResult)
    return 1.pack

  if phase == 1:
    let verbResult = args[^1]

    return verbResult.pack
    # TODO: increment current task's quotas by the amount of ticks innerTask used

type
  BinFloatOp = proc(x: float, y: float): float
  ShortCircuitType = enum scNone, scOr, scAnd

template extractFloatInto(into: var float, num: MData) =
  if num.isType(dInt):
    into = num.intVal.float
  elif num.isType(dFloat):
    into = num.floatVal
  else:
    runtimeError(E_ARGS, "invalid number " & $num)

template defArithmeticOperator(name: string, op: BinFloatOp, logical = false,
                               strictlyBinary = false, shortCircuit = scNone) =
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
        if shortCircuit == scOr and acc.truthy:
          break
        if shortCircuit == scAnd and not acc.truthy:
          break

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
defArithmeticOperator("%", `mod`)

proc wrappedAnd(a, b: float): float = (a.int and b.int).float
proc wrappedOr(a, b: float): float = (a.int or b.int).float
proc wrappedXor(a, b: float): float = (a.int xor b.int).float

defArithmeticOperator("&", wrappedAnd)
defArithmeticOperator("|", wrappedOr)
defArithmeticOperator("^", wrappedXor)
defArithmeticOperator("and", wrappedAnd, logical = true, shortCircuit = scAnd)
defArithmeticOperator("or",  wrappedOr, logical = true, shortCircuit = scOr)
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

## ::
##
##   (= x:Any y:Any):Int
##
## Checks if ``x`` is the "same thing" as ``y``. This involves looking through
## lists and comparing their elements too. If ``x`` is indeed equal to ``y``
## then ``1`` is returned. If not, ``0`` is returned.
##
## Examples::
##
##   (= 1 1)                         ; => 1
##   (= (1 2 3) (1 2 3))             ; => 1
##   (= (1 2 3) (1 2 3 4 5))         ; => 0
##   (= (1 2 (1 2 3)) (1 2 (1 2 3))) ; => 1
##   (= "hello world" "hello world") ; => 1
##   (= #100 #100)                   ; => 1
defBuiltin "=":
  if args.len != 2:
    runtimeError(E_ARGS, "= takes 2 arguments")

  let a = args[0]
  let b = args[1]

  if a == b:
    return 1.md.pack
  else:
    return 0.md.pack

## ::
##
##   (nil? x:Any):Int
##
## Checks of ``x`` is ``nil``. If so, ``1`` is returned. If not, ``0`` is
## returned.
##
## Examples::
##
##  (nil? 66) ; => 0
##  (nil? nil) ; => 1
defBuiltin "nil?":
  if args.len != 1:
    runtimeError(E_ARGS, "nil? takes 1 argument")

  return args[0].isType(dNil).int.md.pack

## ::
##
##   (symbol s:Str):Sym
##
## Returns a symbol with the name ``s``.
##
## Examples::
##
##   (symbol "hi") ; => 'hi
##   (symbol 5)    ; => E_TYPE
##   (symbol ())   ; => E_TYPE
defBuiltin "symbol":
  if args.len != 1:
    runtimeError(E_ARGS, "symbol takes 1 argument")
  let what = extractString(args[0])
  return what.mds.pack

## ::
##
##   ($ x:Any):Str
##
## Returns a string representation of ``x``.
##
## Examples::
##
##   ($ 123)     ; => "123"
##   ($ 123.456) ; => "123.456"
##   ($ "abc")   ; => "abc"
##   ($ 'abc)    ; => "abc"
##   ($ #5)      ; => "#5"
##   ($ (1 2 3)) ; => "(1 2 3)"
##   ($ nil)     ; => "nil"
defBuiltin "$":
  if args.len != 1:
    runtimeError(E_ARGS, "$ takes 1 argument")

  let what = args[0]
  if what.isType(dStr):
    return what.pack
  else:
    return ($what).md.pack

## ::
##
##   ($o obj:Obj):Str
##
## Generates a string representation of ``obj``. It'll probably be of the form
## ``"OBJECT-NAME (#OBJECT-NUMBER)"``.
defBuiltin "$o":
  if args.len != 1:
    runtimeError(E_ARGS, "$o takes 1 argument")

  let what = extractObject(args[0])
  return what.toObjStr().md.pack

## ::
##
##   (object val:Int|Str):Obj
##
## Tries to convert ``val`` into a value of type ``object``.
##
## Examples::
##
##   (object 5)     ; => #5
##   (object "5")   ; => #5
##   (object "#5")  ; => #5
##   (object "foo") ; will result in E_ARGS
##   (object (1 2)) ; will result in E_TYPE
defBuiltin "object":
  if args.len != 1:
    runtimeError(E_ARGS, "object takes 1 argument")

  let val = args[0]
  if val.dtype == dInt:
    return val.intVal.ObjID.md.pack
  elif val.dtype == dStr:
    var str = val.strVal
    if str.len > 0 and str[0] == '#':
      str = str[1..^1]

    try:
      return parseInt(str).ObjID.md.pack
    except:
      runtimeError(E_ARGS, bname & ": invalid object number: " & str)
  else:
    runtimeError(E_TYPE, bname & ": expected dInt or dStr, got " & $val.dtype)

## ::
##
##   (parseint x:Str|Obj|Int):Int
##
## Attempts to convert ``x`` to an integer value. ``x`` can be
## anything that resembles a number, so a str, object, or of course
## int. If any other type is passed, ``E_TYPE`` will be raised. If
## there is no suitable integer representation, ``E_ARGS`` is raised.
##
## Examples::
##
##   (parseint 5)     ; => 5
##   (parseint #5)    ; => 5
##   (parseint "-5")  ; => -5
##   (parseint "5.5") ; => E_ARGS
##   (parseint "abc") ; => E_ARGS
defBuiltin "parseint":
  if args.len != 1:
    runtimeError(E_ARGS, "parseint takes 1 argument")

  let arg = args[0]
  if arg.isType(dInt):
    return arg.pack
  elif arg.isType(dObj):
    return arg.objVal.int.md.pack
  elif arg.isType(dStr):
    try:
      return parseInt(arg.strVal).md.pack
    except:
      runtimeError(E_ARGS, "failed to convert string to number $#".format(arg))
  else:
    runtimeError(E_TYPE, "parseint takes a int, obj, or str")

## ::
##
##   (list v:Any...):List
## 
## Constructs a list with ``v``s provided. ``(list)`` is an empty list.
defBuiltin "list":
  return args.md.pack

## ::
##
##   (table pairs:List...):Table
##
## Constructs a table. ``pairs`` is expected to be a plist (this means
## that every argument to ``table`` must be a list of length 2),
## otherwise ``E_ARGS`` is thrown. The table is initialized with the
## pairs stored in ``pairs``.
##
## Example::
##
##   (table) ; creates an empty table
##   (table '(a 5) '(b 10) '(c 30)) ; maps a to 5, b to 10, c to 30
defBuiltin "table":
  var tab = initTable[MData, MData]()
  for argd in args:
    if not argd.isType(dList):
      runtimeError(E_ARGS, "arguments to table must be pairs")
    let pair = argd.listVal
    if len(pair) != 2:
      runtimeError(E_ARGS, "arguments to table must be pairs")
    tab[pair[0]] = pair[1]

  return tab.md.pack

## ::
##
##   (cat str:Str...):Str
##   (cat list:List...):List
##   (cat table:Table...):Table
##
## Concatenates strings or lists or tables together. All arguments must be of the same
## type and either strings or lists.
##
## Examples::
##
##   (cat "hello " "world") ; => "hello world"
##   (cat "hello" " " "world") ; => "hello world"
##   (cat (1 2 3) (5 6 7) (1 2 3)) ; => (1 2 3 5 6 7 1 2 3)
##   (cat "abcdef" (1 2 3)) ; => E_ARGS
##
##   ;; Note: If you want to concatenate all the strings in a list together you need to do:
##   (call cat list-of-strings)
##   ;; The same goes for lists.
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
  if typ == dTable:
    var total = initTable[MData, MData]()
    for argd in args:
      for key, val in pairs(extractTable(argd)):
        total[key] = val
    return total.md.pack
  else:
    var total = ""
    for argd in args:
      let arg = argd
      total &= arg.toEchoString()
    return total.md.pack

## ::
##
##   (head list:List):List
##
## Returns the first element of a list. If the list is empty then ``nil`` is
## returned.
##
## Examples::
##
##   (head (1 2 3 4)) ; => 1
##   (head ()) ; => nil
defBuiltin "head":
  if args.len != 1:
    runtimeError(E_ARGS, "head takes 1 argument")

  let list = extractList(args[0])
  if list.len == 0:
    return nilD.pack

  return list[0].pack


## ::
##
##   (tail list:List):List
##
## Returns all but the first elements of a list. If the list is empty then
## the empty list is returned.
##
## Examples::
##
##   (tail (1 2 3 4)) ; => (2 3 4)
##   (tail ()) ; => ()
defBuiltin "tail":
  if args.len != 1:
    runtimeError(E_ARGS, "tail takes 1 argument")

  let list = extractList(args[0])
  if list.len == 0:
    return @[].md.pack

  return list[1 .. ^1].md.pack

## ::
##
##   (len list-or-str:List|Str|Table):Int
##
## Returns the length of the argument. If it's a string, it returns
## the number of characters in the string. If it's a list, it returns
## the number of elements in the list. If it's a table, it returns the
## number of pairs in it.
##
## Examples::
##
##   (len "hello world") ; => 11
##   (len (1 2 3)) ; => 3
##   (len ()) ; => 0
defBuiltin "len":
  if args.len != 1:
    runtimeError(E_ARGS, "len takes 1 argument")

  let listd = args[0]
  if listd.isType(dList):
    return listd.listVal.len.md.pack
  elif listd.isType(dStr):
    return listd.strVal.len.md.pack
  elif listd.isType(dTable):
    return listd.tableVal.len.md.pack
  else:
    runtimeError(E_ARGS, "len takes either a string or a list or a map")

## ::
##
##   (substr str:Str start:Int end:Int):Str
##
## Returns the substring of ``str`` from start position ``start`` until end
## position ``end``. If ``end`` is negative, it is counted backwards from the
## end of the string. If ``start`` is negative, ``E_ARGS`` is raised. If
## ``start`` and ``end`` don't point to a valid substring (for example, if
## ``start`` is ``6`` and ``end`` is ``3``) then the empty string is returned.
##
## Examples::
##
##   (substr "01234567" 2 5) ; => "2345"
##   (substr "01234567" 0 -1) ; => "01234567"
##   (substr "01234567" 2 -2) ; => "23456"
##   (substr "01234567" -1 2) ; => E_ARGS
##   (substr "01234567" 30 50) ; => "" (note, no error)
defBuiltin "substr":
  if args.len != 3:
    runtimeError(E_ARGS, "substr takes 3 arguments")

  let str = extractString(args[0])
  let strlen = str.len
  let start = extractInt(args[1])
  var endv = extractInt(args[2]) # end is a reserved word

  if start < 0:
    runtimeError(E_ARGS, "start index must be greater than 0")

  if start >= strlen:
    runtimeError(E_ARGS, "start index greater than length of string")

  if endv >= strlen:
    endv = strlen - 1

  if endv >= 0:
    return str[start .. endv].md.pack
  else:
    return str[start .. ^ -endv].md.pack

## ::
##
##   (splice str:Str start:Int end:Int replacement:Str = ""):Str
##
## Analogue to JavaScript's splice
defBuiltin "splice":
  if args.len != 4:
    runtimeError(E_ARGS, "splice takes 4 arguments")

  var str = extractString(args[0])
  let start = extractInt(args[1])
  let endv = extractInt(args[2]) # end is a reserved word
  let replacement = extractString(args[3])

  if start < 0:
    runtimeError(E_ARGS, "start index must be greater than 0")

  if start >= str.len:
    runtimeError(E_ARGS, "start index greater than length of string")

  if endv >= 0:
    str[start .. endv] = replacement
  else:
    str[start .. ^ -endv] = replacement

  return str.md.pack

## ::
##
##   (index str:String substr:Str [ignore-case:Int = 0]):Int
##
## Returns the first index at which ``substr`` appears in ``str``. If
## ``ignore-case`` is ``1`` then case will be ignored. If ``subsr`` is
## not found then ``-1`` is returned.
##
## Examples::
##
##   (index "hello world" "llo") ; => 2
##   (index "HELLO WORLD" "llo") ; => -1
##   (index "HELLO WORLD" "llo" 1) ; => 2
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
    haystack = haystack.toLowerAscii()
    needle = needle.toLowerAscii()

  return haystack.find(needle).md.pack

## ::
##
##   (match str:Str pat:Str):List
##
## Matches `pat` on `str` and if successful, returns a list of the strings that
## were matched by capturing groups. If unsuccessful, returns nil. Note that the
## match is anchored to the start and end of the string.
##
## Regex is more or less PCRE but use ``%`` instead of ``\``.
##
## Case insensitivity and other options are found in the documentation of
## ``nre``, Nim's regex library:
##
##   https://github.com/nim-lang/Nim/blob/master/lib/impure/nre.nim#L87
##
## Examples::
##
##   (match "abc[def]ghi" ".*?%[(.*?)%].*?") ; => ("def")
##   (match "HELLO WORLD" "(?i)(hello world)")
##      ;; => ("hello world")
##      ;; (?i) in this case means case insensitive
##      ;; see the link above for more of these neat things
##   (match "blah blah" "blah")
##      ;; => nil
##      ;; valiant effort, but the the regex must match the whole string
##   (match "hello world" ".+")
##      ;; => ()
##      ;; There are no capturing groups but the regex matches so an empty list
##      ;; is returned.
defBuiltin "match":
  if args.len != 2:
    runtimeError(E_ARGS, "match takes 2 arguments")

  try:
    let str = extractString(args[0])
    let pat = extractString(args[1])
    let regex = escapeRegex(pat)

    let matches = str.match(regex)
    if matches.isSome:
      var captureList: seq[MData]
      for capture in matches.get().captures().items():
        when capture is Option[string]:
          if capture.isSome():
            captureList.add(capture.get().md)
          else:
            captureList.add(nilD)
        elif capture is string:
          captureList.add(capture.md)
        else:
          echo "ERROR: `capture` is of wrong type"
          quit(1)

      return captureList.md.pack
    else:
      return nilD.pack
  except SyntaxError:
    let msg = getCurrentException().msg
    runtimeError(E_ARGS, "regex error: " & msg)

## ::
##
##   (find str:Str pat:Str start-index:Int = 0 end-index:Int = -1):List
defBuiltin "find":
  let alen = args.len
  if alen < 2 or alen > 4:
    runtimeError(E_ARGS, "find takes 2..4 arguments")

  var startIndex = 0
  var endIndex = -1

  if alen > 2:
    startIndex = extractInt(args[2])

  if alen > 3:
    endIndex = extractInt(args[3])

  try:
    let str = extractString(args[0])
    let pat = extractString(args[1])
    let regex = escapeRegex(pat)

    if endIndex < 0:
      endIndex = str.len + endIndex
      if endIndex < 0:
        runtimeError(E_ARGS, "end index out of bounds")

    let matchopt = str.find(regex, startIndex, endIndex)
    if matchopt.isSome:
      let match = matchopt.get()
      let matchBounds = match.matchBounds
      var captureList: seq[MData]
      for capture in match.captures().items():
        when capture is Option[string]:
          if capture.isSome():
            captureList.add(capture.get().md)
          else:
            captureList.add(nilD)
        elif capture is string:
          captureList.add(capture.md)
        else:
          echo "ERROR: `capture` is of wrong type"
          quit(1)

      var resultList = @[matchBounds.a.md, matchBounds.b.md, captureList.md]
      return resultList.md.pack
    else:
      return nilD.pack

  except SyntaxError:
    let msg = getCurrentException().msg
    runtimeError(E_ARGS, "regex error: " & msg)

## ::
##
##   (gsub str:Str pat:Str replacement:Str):str
defBuiltin "gsub":
  if args.len != 3:
    runtimeError(E_ARGS, "gsub takes 3 arguments")

  try:
    let str = extractString(args[0])
    let pat = extractString(args[1])
    let regex = escapeRegex(pat)
    let replacement = extractString(args[2])

    return nre.replace(str, regex, replacement).md.pack
  except SyntaxError:
    let msg = getCurrentException().msg
    runtimeError(E_ARGS, "regex error: " & msg)

## ::
##
##   (repeat str:Str times:Int)
##
## Returns a string consisting of ``str`` repeated ``times`` times.
##
## Example::
##
##   (repeat "hello" 4) ; => "hellohellohellohello"
##
defBuiltin "repeat":
  if args.len != 2:
    runtimeError(E_ARGS, "repeat takes 2 arguments")

  let str = extractString(args[0])
  let times = extractInt(args[1])

  if times < 1:
    runtimeError(E_ARGS, "can't repeat a string less than one time")

  return str.repeat(times).md.pack

## ::
##
##   (strsub str:Str from:Str to:Str):Str
##
## Replaces all instances of ``from`` in ``str`` with ``to`` and returns the
## result.
##
## Example::
##
##   (strsub "seventeen adventures" "ven" "poop")
##      ;; => "sepoopteen adpooptures"
defBuiltin "strsub":
  if args.len != 3:
    runtimeError(E_ARGS, "strsub takes 3 arguments")

  let str = extractString(args[0])
  let fromv = extractString(args[1])
  let to = extractString(args[2])

  return str.replace(fromv, to).md.pack

proc reverse(str: var string) =
  let length = str.len
  if length < 2: return
  for i in 0..length div 2 - 1:
    swap(str[i], str[length - i - 1])

## ::
##
##   (fit str:Str length:Int filler:Str=" " trail:Str="")
##
## Fits the string ``str`` to be ``length`` characters by repeatedly adding
## ``filler`` (and truncating when necessary) until length ``length`` is
## reached. If ``str`` is already greater than ``length``, then it is cut down
## appropriately and ``trail`` is appended. If ``trail`` is too long, then it is
## truncated too.
##
## If ``length`` is positive then padding is applied to the right. If negative,
## then it's absolute value will be taken but padding will be applied to the
## left.
##
## Examples:
##
## ::
##
##   (fit "hello world" 6)          ; => "hello "
##   (fit "hello world" 15 "#")     ; => "hello world####"
##   (fit "hello world" 6 "" "...") ; => "hel..."
##   (fit "hello world" -15 ">")    ; => ">>>>hello world"
##
defBuiltin "fit":
  if args.len notin 2..4:
    runtimeError(E_ARGS, "fit takes 2 to 4 arguments")

  var filler = " "
  var trail = ""
  var res: string

  var str = extractString(args[0])
  var length = extractInt(args[1])
  var leftPad = false

  if length < 0:
    length = -length
    leftPad = true

  if args.len >= 3:
    filler = extractString(args[2])

  if filler.len == 0:
    filler = " "

  if args.len >= 4:
    trail = extractString(args[3])

  if trail.len > str.len:
    trail = ""

  let strlen = str.len
  let traillen = trail.len

  if leftPad:
    str.reverse
    filler.reverse
    trail.reverse

  if strlen == length:
    res = str
  elif strlen < length:
    while str.len <= length:
      str &= filler
    res = str[0..length - 1]

  elif strlen > length:
    let allowed = length - traillen
    if allowed <= 0:
      res = trail[0..length-1]
    else:
      res = str[0..allowed-1] & trail

  if leftPad:
    res.reverse

  return res.md.pack

defBuiltin "split":
  var sep = " "
  case args.len:
    of 1: discard
    of 2:
      sep = extractString(args[1])
    else:
      runtimeError(E_ARGS, "split takes 2 arguments")

  let str = extractString(args[0])
  if sep.len == 0:
    var chars: seq[MData]
    newSeq(chars, 0)
    for c in str:
      chars.add(($c).md)
    return chars.md.pack
  else:
    return str.split(sep).map(md).md.pack

# (downcase str)
# Makes every character in str lowercase
defBuiltin "downcase":
  if args.len != 1:
    runtimeError(E_ARGS, "downcase takes 1 arguments")

  let str = extractString(args[0])

  return str.toLowerAscii().md.pack

# (upcase str)
# Makes every character in str uppercase
defBuiltin "upcase":
  if args.len != 1:
    runtimeError(E_ARGS, "upcase takes 1 arguments")

  let str = extractString(args[0])

  return str.toUpperAscii().md.pack

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
      return list[start .. endv].md.pack
    elif endv in -length..(-1):
      return list[start ..^ -endv].md.pack
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

## ::
##
##   (setdiffsym list1:List list2:List):List
##
## Takes the difference of `list1` and `list2`. The result contains
## all elements of `list1` that are not contained in `list2`.
##
## Note: this does not preserve the order of elements in `list1`!
##
## Examples::
##
##   (setdiff '(1 2 3 4 5) '(2 3)) ; => '(1 4 5)
##   (setdiff '(2 3) '(1 2 3 4 5)) ; => '(1 4 5)
##
defBuiltin "setdiff":
  if args.len != 2:
    runtimeError(E_ARGS, "setdiffsym takes 3 arguments")

  checkType(args[0], dList)
  checkType(args[1], dList)

  let set1 = args[0].listVal.toHashSet
  let set2 = args[1].listVal.toHashSet

  return difference(set1, set2).items.toSeq.md.pack

## ::
##
##   (setdiffsym list1:List list2:List):List
##
## Takes the symmetric difference of `list1` and `list2`. The result
## contains all elements that show up either in `list1` or `list2`, but
## not both.
##
## Note: this does not preserve the order of elements in `list1` or
## `list2`!
##
## Examples::
##
##   (setdiff '(1 2 3 4 5) '(2 3)) ; => '(1 4 5)
##   (setdiff '(2 3) '(1 2 3 4 5)) ; => '(1 4 5)
##
defBuiltin "setdiffsym":
  if args.len != 2:
    runtimeError(E_ARGS, "setdiffsym takes 3 arguments")

  checkType(args[0], dList)
  checkType(args[1], dList)

  let set1 = args[0].listVal.toHashSet
  let set2 = args[1].listVal.toHashSet

  return symmetricDifference(set1, set2).items.toSeq.md.pack

# (tget table key default)
# Looks up `key` in `table` and returns the associated value.  If the
# key is not found, and `default` is provided, `default` is returned.
# Otherwise, throws `E_BOUNDS`.
defBuiltin "tget":
  if args.len != 2 and args.len != 3:
    runtimeError(E_ARGS, "tget takes 2 or 3 arguments")

  checkType(args[0], dTable)

  template t: Table[MData, MData] = args[0].tableVal
  if args[1] in t:
    return t[args[1]].pack
  else:
    if args.len == 3:
      return args[2].pack
    else:
      runtimeError(E_BOUNDS, "table does not contain key $#".format(args[1]))

defBuiltin "tset":
  if args.len != 3:
    runtimeError(E_ARGS, "tset takes 3 argumments")

  # This makes a copy!
  var newTable = extractTable(args[0])
  newTable[args[1]] = args[2]

  return newTable.md.pack

defBuiltin "tdelete":
  if args.len != 2:
    runtimeError(E_ARGS, "tdelete takes 2 arguments")

  var newTable = extractTable(args[0])
  newTable.del(args[1])

  return newTable.md.pack

defBuiltin "tpairs":
  if args.len != 1:
    runtimeError(E_ARGS, "tpairs takes 1 argument")
  var resultL: seq[MData] = @[]
  for key, val in pairs(extractTable(args[0])):
    resultL.add( @[key, val].md )

  return resultL.md.pack

# (in list el)
# returns index of el in list, or -1
defBuiltin "in":
  if args.len != 2:
    runtimeError(E_ARGS, "in takes 2 arguments")

  let list = extractList(args[0])
  let el = args[1]

  return list.find(el).md.pack

## ::
##
##   (range start:Int end:Int):List
##
## returns ``(start start+1 start+2 ... end-1 end)``
##
## This operation can be expensive, and as such removes end - start + 1 ticks
## from the current task's tick quota.
##
## **NOTE**: The future of this builtin is uncertain because it can easily eat up
## a lot of memory.
defBuiltin "range":
  if args.len != 2:
    runtimeError(E_ARGS, "range takes 2 arguments")

  let start = extractInt(args[0])
  let endv = extractInt(args[1])

  let numberOfTicks = endv - start + 1
  task.tickCount += numberOfTicks

  var res: seq[MData]
  newSeq(res, 0)
  for i in start..endv:
    res.add(i.md)

  return res.md.pack

# (pass arg1 arg2 ...)
# calls the parent verb
defBuiltin "pass":
  if phase == 0:
    var args = args
    if args.len == 0:
      let oldArgsd = symtable["args"]
      if oldArgsd.isType(dList):
        args = oldArgsd.listVal

    let parent = self.parent

    if isNil(parent) or parent == self:
      return nilD.pack

    let verbd = symtable["verb"]
    if not verbd.isType(dStr):
      return nilD.pack
    let verbName = verbd.strVal

    let (obj, verb) = parent.getVerbAndObj(verbName).orElse:
      runtimeError(E_VERBNF, "Pass failed, verb is not inherited.")

    var res: Option[TaskID]
    verbCallRaw(
      res,
      self,
      verb,
      player, caller,
      args, symtable = symtable, holder = obj,
      callback = some(tid)
    )

    task.setStatus(tsAwaitingResult)
    return 1.pack

  if phase == 1:
    let verbResult = args[^1]
    return verbResult.pack

## ::
##
##    (time):Int
##
## Returns the current time in milliseconds since 1970-01-01 UTC.
##
## This will not be supported on non-64 bit platforms.
defBuiltin "time":
  when sizeof(int) < 8:
    runtimeError(E_INTERNAL, "time not supported on non-64 bit platforms")

  if args.len != 0:
    runtimeError(E_ARGS, "time takes no parameters")
  let curTime = getTime()
  let seconds = toUnix(curTime)
  let nanos = nanosecond(curTime)
  return (seconds * 1000 + nanos div 1000000).int.md.pack

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

## ::
##
##   (random max:Int):Int
##   (random min:Int max:Int):Int
##
## Generates a random integer between ``min`` and ``max - 1``, inclusive. If
## only ``max`` is provided, ``min`` is assumed to be ``0``.
##
## Examples::
##
##   (random 10) ; => 4  (chosen by fair dice roll; guaranteed to be random)
##   (random 10 20) ; => 13
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

  let randomNum = abs(arc4random()).float
  # Scale the number down using floating point arithmetic
  let nrange = (nmax - nmin).float
  let highint32 = high(int32).float
  let scaled = (randomNum / highint32 * nrange).int

  return (scaled + nmin).md.pack

# Task operations

## ::
##
##   (suspend [number-of-seconds:Int = Infinity]):Any
##
## Suspends the current task for ``number-of-seconds`` (optional, defaults to
## infinity) seconds. If a number of seconds was given, this builtin finishes
## execution when the timer is up and returns nil OR some other task calls
## ``(resume THIS-TASK'S-ID [value = nil])`` in which case it will return
## ``value`` as specified by the resumer. This second condition also applies when
## the task is indefinitely suspended.
defBuiltin "suspend":
  if phase == 0:
    var until = fromUnix(0)
    case args.len:
      of 0: discard
      of 1:
        let ms = (extractFloat(args[0]) * 1000).int
        if ms < 0:
          runtimeError(E_ARGS, "cannot suspend for a negative amount of seconds")
        until = getTime()
        until += ms.milliseconds
      else:
        runtimeError(E_ARGS, "suspend takes 0 or 1 arguments")
    task.suspendedUntil = until
    task.setStatus(tsSuspended)
    return 1.pack
  if phase == 1:
    task.tickCount = 0
    return args[^1].pack

## ::
##
##   (resume task-id:Int [value:Any = nil]):Any
##
## Resumes the task with id `task-id` and sets the return value of the suspend
## call that suspended it in the first place to ``value`` (optional, defaulting
## to ``nil``)
##
## If no task with id ``task-id`` exists or it does exist but isn't suspended,
## ``E_ARGS`` is raised. If the programmer isn't a wizard and isn't the owner
## of the task, then ``E_PERM`` is raised.
##
## TODO: figure out what 'owner of a task' really means. (Is it the programmer?
## The player who started it? Someone else?)
defBuiltin "resume":
  let alen = args.len
  if alen notin 1..2:
    runtimeError(E_ARGS, "resume takes 1 or 2 arguments")
  let taskID = TaskID(extractInt(args[0]))
  let value = if alen == 2: args[1] else: nilD
  let otask = world.getTaskByID(taskID).orElse:
    runtimeError(E_ARGS, "attempt to resume nonexistent task")

  if otask.status notin {tsSuspended, tsAwaitingInput}:
    runtimeError(E_ARGS, "attempt to resume non-suspended task")
  if not isWizardT() and task.owner != otask.owner:
    runtimeError(E_PERM, "you must be either a wizard or the owner of a task to suspend it")

  otask.resume(value)

  return value.pack

## ::
##
##   (taskid):Int
##
## Returns the currently running task's ID that can be used in other builtins
## that require a task ID.
##
## Examples::
##
##   (taskid) ; => 19245  (arbitrary example)
defBuiltin "taskid":
  if args.len != 0:
    runtimeError(E_ARGS, "taskid takes no arguments")

  return tid.int.md.pack

## ::
##
##   (queued-tasks):List
##
## Returns information about tasks that are waiting to run in the form of a
## list of lists. Each list represents a task owned by the owner of this task
## (or if a wizard, all tasks)
##
## Format: ``(task-id start-time programmer verb-loc verb-name line self)``
##
##   :``task-id``: The ID of the task
##   :``start-time``: The time the task started
##   :``programmer``: The programmer of that task
##   :``verb-loc``: The object where the verb the task is running from is found
##   :``verb-name``: The name of the verb the task is running
##   :``line``: The line number the task is waiting to execute
##   :``self``: The value of the task's ``self`` variable
defBuiltin "queued-tasks":
  if args.len != 0:
    runtimeError(E_ARGS, "queued-tasks takes no argumnts")

  var res: seq[MData] = @[]
  for otid, otask in world.tasks.pairs:
    if isWizardT() or task.owner == otask.owner:
      if otask.status notin {tsSuspended, tsAwaitingInput}:
        continue
      let taskID = otid.int.md
      let startTime = otask.suspendedUntil.toUnix.int.md
      let programmer = otask.owner.md
      let verbLoc = otask.globals["holder"]
      let verbName = otask.globals["verb"]
      let line = otask.code[task.pc].pos.line.md
      let self = otask.globals["self"]

      res.add(@[taskID, startTime, programmer, verbLoc, verbName, line, self].md)

  return res.md.pack

## ::
##
##   (kill-task task-id:Int):Int
##
## Kills the task with id `task-id`. The programmer needs to be the programmer
## of that task (or a wizard) or ``E_PERM`` is thrown. The task needs to be
## suspended or awaiting input or ``E_ARGS`` is thrown. Also, if the task
## simply does not exist then ``E_ARGS`` is thrown as well.
defBuiltin "kill-task":
  if args.len != 1:
    runtimeError(E_ARGS, "kill-task takes 1 argument")
  let taskID = TaskID(extractInt(args[0]))
  let otask = world.getTaskByID(taskID).orElse:
    runtimeError(E_ARGS, "attempt to kill nonexistent task")

  if otask.status notin {tsSuspended, tsAwaitingInput}:
    runtimeError(E_ARGS, "attempt to resume non-suspended task")
  if not isWizardT() and task.owner != otask.owner:
    runtimeError(E_PERM, "you must be either a wizard or the owner of a task to kill it")

  otask.spush(nilD)
  otask.finish()

  return taskID.int.md.pack

when defined(nimTypeNames):
  defBuiltin "dumpinsts":
    dumpNumberOfInstances();

when defined(includeWizardUtils):
  defBuiltin "file-contents":
    if not isWizardT:
      runtimeError(E_PERM, "you must be a wizard to call file-contents")

    if args.len != 1:
      runtimeError(E_ARGS, "file-contents takes 1 argument")

    let fname = extractString(args[0])

    try:
      return readFile(fname).md.pack
    except IOError:
      runtimeError(E_INTERNAL,
                   "file-contents: $#".format(getCurrentExceptionMsg()))
