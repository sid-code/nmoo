import types, objects, verbs, scripting, strutils, tables, sequtils

template defBuiltin(name: string, body: stmt) {.immediate.} =
  var bproc: BuiltinProc = proc (args: var seq[MData], world: var World,
                                 caller, owner: MObject, symtable: SymbolTable): MData =
    # to provide a simpler call to eval (note the optional args)
    proc evalD(e: MData, w: var World = world, c: MObject = caller,
               o: MObject = owner, st: SymbolTable = symtable): MData =
      eval(e, w, c, o, st)

    body

  scripting.builtins[name] = bproc

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

template checkForError(value: MData) {.immediate.} =
  if value.isType(dErr):
    return value

template checkType(value: MData, expected: MDataType, ifnot: MError = E_ARGS)
          {.immediate.} =
  if not value.isType(expected):
    return ifnot.md("expected argument of type " & $expected & " instead got " & $value.dType)

template extractObject(objd: MData): MObject {.immediate.} =
  checkType(objd, dObj)
  let obj = world.dataToObj(objd)
  if obj == nil:
    return E_ARGS.md("invalid object " & $objd)

  obj

template checkOwn(obj, what: MObject) =
  if not obj.owns(what):
    return E_PERM.md(obj.toObjStr() & " doesn't own " & what.toObjStr())

template checkOwn(obj: MObject, prop: MProperty) =
  if not obj.owns(prop):
    return E_PERM.md(obj.toObjStr() & " doesn't own " & prop.name)

template checkOwn(obj: MObject, verb: MVerb) =
  if not obj.owns(verb):
    return E_PERM.md(obj.toObjStr() & " doesn't own " & verb.name)

template checkRead(obj, what: MObject) =
  if not obj.canRead(what):
    return E_PERM.md(obj.toObjStr() & " cannot read " & what.toObjStr())
template checkWrite(obj, what: MObject) =
  if not obj.canWrite(what):
    return E_PERM.md(obj.toObjStr() & " cannot write " & what.toObjStr())
template checkRead(obj: MObject, what: MProperty) =
  if not obj.canRead(what):
    return E_PERM.md(obj.toObjStr() & " cannot read property: " & what.name)
template checkWrite(obj: MObject, what: MProperty) =
  if not obj.canWrite(what):
    return E_PERM.md(obj.toObjStr() & " cannot write property: " & what.name)
template checkRead(obj: MObject, what: MVerb) =
  if not obj.canRead(what):
    return E_PERM.md(obj.toObjStr() & " cannot read verb: " & what.names)
template checkWrite(obj: MObject, what: MVerb) =
  if not obj.canWrite(what):
    return E_PERM.md(obj.toObjStr() & " cannot write verb: " & what.names)

proc genCall(fun: MData, args: seq[MData]): MData =
  var resList: seq[MData]
  if fun.isType(dSym):
    resList = @[fun]
  else:
    resList = @["call".mds, fun]

  return (resList & args).md

defBuiltin "echo":
  var
    newArgs: seq[MData] = @[]
    sendstr = ""
  for arg in args:
    let res = evalD(arg)
    checkForError(res)
    sendstr &= res.toEchoString()
    newArgs.add(res)
  caller.send(sendstr)
  return newArgs.md

defBuiltin "do":
  var newArgs: seq[MData] = @[]
  for arg in args:
    let res = evalD(arg)
    checkForError(res)
    newArgs.add(res)

  return newArgs.md

defBuiltin "eval":
  if args.len != 1:
    return E_ARGS.md("eval takes one argument")

  let argd = evalD(args[0])
  checkForError(argd)
  checkType(argd, dStr)
  var evalStr = argd.strVal
  if evalStr[0] != '(':
    evalStr = '(' & evalStr & ')'

  var parser = newParser(evalStr)
  try:
    let parsed = parser.parseList()
    return evalD(parsed, o = caller)
  except MParseError:
    let msg = getCurrentExceptionMsg()
    return E_PARSE.md("code failed to parse: $1" % msg)

defBuiltin "slet": # single let
  if args.len != 2:
    return E_ARGS.md("slet expects two arguments")

  let first = args[0]
  checkType(first, dList)
  if first.listVal.len != 2:
    return E_ARGS.md("slet's first argument is a tuple (symbol value-to-bind)")

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
      return E_ARGS.md("let takes a list of assignments")
    let pair = asmt.listVal
    if not pair.len == 2:
      return E_ARGS.md("each assignment in the list must be a tuple (symbol value-to-bind)")
    checkType(pair[0], dSym)

    let
      symName = pair[0].symVal
      setVal = evalD(pair[1], st = newSymtable)

    checkForError(setVal)
    newSymtable[symName] = setVal

  return evalD(args[1], st = newSymtable)

defBuiltin "cond":
  for arg in args:
    checkType(arg, dList)
    let larg = arg.listVal
    if larg.len == 0 or larg.len > 2:
      return E_ARGS.md("each argument to cond must be of length 1 or 2")

    if larg.len == 1:
      return larg[0]
    else:
      let condVal = evalD(larg[0])
      checkForError(condVal)
      if condVal.truthy:
        return larg[1]
      else:
        continue

  return E_BADCOND.md

proc objSpecToStr(osp: ObjSpec): string =
  ($osp).toLower[1 .. -1]

proc strToObjSpec(osps: string): tuple[success: bool, result: ObjSpec] =
  let realSpec = "o" & osps[0].toUpper & osps[1 .. -1]
  try:
    return (true, parseEnum[ObjSpec](realSpec))
  except:
    return (false, oNone)

proc prepSpecToStr(psp: PrepType): string =
  var images: seq[string] = @[]
  for prep in Prepositions:
    let (ptype, image) = prep
    if ptype == psp:
      images.add(image)

  return images.join("/")

proc strToPrepSpec(psps: string): tuple[success: bool, result: PrepType] =
  let pspsLower = psps.toLower()
  if pspsLower == "none":
    return (true, pNone)

  for prep in Prepositions:
    let (ptype, image) = prep
    if image == pspsLower:
      return (true, ptype)

  return (false, pNone)

proc extractInfo(prop: MProperty): MData =
  var result: seq[MData] = @[]
  result.add(prop.owner.md)

  var perms = ""
  if prop.pubRead: perms &= "r"
  if prop.pubWrite: perms &= "w"
  if prop.ownerIsParent: perms &= "c"

  result.add(perms.md)
  return result.md

proc extractInfo(verb: MVerb): MData =
  var result: seq[MData] = @[]
  result.add(verb.owner.md)

  var perms = ""
  if verb.pubRead: perms &= "r"
  if verb.pubWrite: perms &= "w"
  if verb.pubExec: perms &= "x"

  result.add(perms.md)
  result.add(verb.names.md)
  return result.md

proc extractArgs(verb: MVerb): MData =
  var result: seq[MData] = @[]
  result.add(objSpecToStr(verb.doSpec).md)
  result.add(prepSpecToStr(verb.prepSpec).md)
  result.add(objSpecToStr(verb.ioSpec).md)

  return result.md

type
  PropInfo = tuple[owner: MObject, perms: string, newName: string]
  VerbInfo = tuple[owner: MObject, perms: string, newName: string]
  VerbArgs = tuple[doSpec: ObjSpec, prepSpec: PrepType, ioSpec: ObjSpec]

template propInfoFromInput(info: seq[MData]): PropInfo =
  if info.len != 2 and info.len != 3:
    return E_ARGS.md("property info must be a list of size 2 or 3")

  var result: PropInfo

  let ownerd = evalD(info[0])
  checkForError(ownerd)
  let ownero = extractObject(ownerd)
  result.owner = ownero

  let permsd = evalD(info[1])
  checkForError(permsd)
  checkType(permsd, dStr)
  let perms = permsd.strVal
  result.perms = perms

  if info.len == 3:
    let newNamed = evalD(info[2])
    checkForError(newNamed)
    checkType(newNamed, dStr)
    let newName = newNamed.strVal
    result.newName = newName

  result

template verbInfoFromInput(info: seq[MData]): VerbInfo =
  if info.len != 2 and info.len != 3:
    return E_ARGS.md("verb info must be a list of size 2 or 3")

  var result: VerbInfo

  let ownerd = evalD(info[0])
  checkForError(ownerd)
  let ownero = extractObject(ownerd)
  result.owner = ownero

  let permsd = evalD(info[1])
  checkForError(permsd)
  checkType(permsd, dStr)
  let perms = permsd.strVal
  result.perms = perms

  if info.len == 3:
    let newNamed = evalD(info[2])
    checkForError(newNamed)
    checkType(newNamed, dStr)
    let newName = newNamed.strVal
    result.newName = newName

  result

template objSpecFromData(ospd: MData): ObjSpec =
  let specd = evalD(ospd)
  checkForError(specd)
  checkType(specd, dStr)
  let
    str = specd.strVal
    (success, spec) = strToObjSpec(str)

  if not success:
    return E_ARGS.md("invalid object spec '$1'" % str)

  spec

template prepSpecFromData(pspd: MData): PrepType =
  let specd = evalD(pspd)
  checkForError(specd)
  checkType(specd, dStr)
  let
    str = specd.strVal
    (success, spec) = strToPrepSpec(str)

  if not success:
    return E_ARGS.md("invalid preposition spec '$1'" % str)

  spec

template verbArgsFromInput(info: seq[MData]): VerbArgs =
  if info.len != 3:
    return E_ARGS.md("verb args must be a list of size 3")

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

template getPropOn(objd, propd: MData): MProperty =
  let objd2 = evalD(objd)
  checkForError(objd2)
  let obj = extractObject(objd2)

  let propd2 = evalD(propd)
  checkForError(propd)
  checkType(propd2, dStr)
  let
    propName = propd.strVal
    propObj = obj.getProp(propName)

  if propObj == nil:
    return E_PROPNF.md("property $1 not found on $2" % [propName, $obj.toObjStr()])

  propObj

template getVerbOn(objd, verbdescd: MData): MVerb =
  let objd2 = evalD(objd)
  checkForError(objd2)
  let obj = extractObject(objd2)

  let verbdescd2 = evalD(verbdescd)
  checkForError(verbdescd2)
  checkType(verbdescd2, dStr)
  let verbdesc = verbdescd2.strVal

  let verb = obj.getVerb(verbdesc)
  if verb == nil:
    return E_VERBNF.md("verb $1 not found on $2" % [verbdesc, obj.toObjStr()])

  verb

# (getprop what propname)
defBuiltin "getprop":
  if not args.len == 2:
    return E_ARGS.md("getprop takes exactly 2 arguments")

  let propObj = getPropOn(args[0], args[1])

  checkRead(owner, propObj)

  return propObj.val

# (setprop what propname newprop)
defBuiltin "setprop":
  if not args.len == 3:
    return E_ARGS.md("setprop takes exactly 3 arguments")

  let objd = evalD(args[0])
  checkForError(objd)
  let obj = extractObject(objd)

  let
    propd = evalD(args[1])
    newVal = args[2]

  checkForError(propd)
  checkType(propd, dStr)
  let
    prop = propd.strVal
    oldProp = obj.getProp(prop)

  if oldProp == nil:
    owner.checkWrite(obj)
    var propObj = obj.setProp(prop, newVal)

    # If the property didn't exist before, we want its owner to be us,
    # not the object that it belongs to.
    propObj.owner = owner
  else:
    var propObj = obj.getProp(prop)
    owner.checkWrite(propObj)
    propObj.val = newVal

  return newVal

# (getpropinfo what propname)
# result is (owner perms)
# perms is [rwc]
defBuiltin "getpropinfo":
  if not args.len == 2:
    return E_ARGS.md("getpropinfo takes exactly 2 arguments")

  let propObj = getPropOn(args[0], args[1])

  checkRead(owner, propObj)

  return extractInfo(propObj)


# (setpropinfo what propname newinfo)
# newinfo is like result from getpropinfo but can
# optionally have a third element specifying a new
# name for the property
defBuiltin "setpropinfo":
  if not args.len == 3:
    return E_ARGS.md("setpropinfo takes exactly 3 arguments")

  let propObj = getPropOn(args[0], args[1])

  checkWrite(owner, propObj)

  # validate the property info
  let propinfod = evalD(args[2])
  checkForError(propinfod)
  checkType(propinfod, dList)
  let
    propinfo = propinfod.listVal
    info = propInfoFromInput(propinfo)

  propObj.setInfo(info)

  return args[0]

# (props obj)
# returns a list of obj's properties
defBuiltin "props":
  if args.len != 1:
    return E_ARGS.md("props takes 1 argument")

  let objd = evalD(args[0])
  checkForError(objd)
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
    return E_ARGS.md("verbs takes 1 argument")

  let objd = evalD(args[0])
  checkForError(objd)
  let obj = extractObject(objd)

  checkRead(owner, obj)

  var res: seq[MData] = @[]
  for v in obj.verbs:
    res.add(v.names.md)

  return res.md


# (getverbinfo obj verb-desc)
defBuiltin "getverbinfo":
  if args.len != 2:
    return E_ARGS.md("getverbinfo takes 2 arguments")

  let verb = getVerbOn(args[0], args[1])
  checkRead(owner, verb)

  return extractInfo(verb)

# (setverbinfo obj verb-desc newinfo)
defBuiltin "setverbinfo":
  if args.len != 3:
    return E_ARGS.md("setverbinfo takes 3 arguments")

  let verb = getVerbOn(args[0], args[1])
  checkWrite(owner, verb)

  let infod = evalD(args[2])
  checkForError(infod)
  checkType(infod, dList)
  let info = verbInfoFromInput(infod.listVal)

  verb.setInfo(info)
  return args[0]

# (getverbargs obj verb-desc)
defBuiltin "getverbargs":
  if args.len != 2:
    return E_ARGS.md("getverbargs takes 2 arguments")

  let verb = getVerbOn(args[0], args[1])
  checkRead(owner, verb)

  return extractArgs(verb)

# (setverbargs obj verb-desc (objspec prepspec objspec))
defBuiltin "setverbargs":
  if args.len != 3:
    return E_ARGS.md("setverbargs takes 3 arguments")

  let verb = getVerbOn(args[0], args[1])
  checkWrite(owner, verb)

  let argsInfod = evalD(args[2])
  checkForError(argsInfod)
  checkType(argsInfod, dList)

  let argsInfo = verbArgsFromInput(argsInfod.listVal)
  verb.setArgs(argsInfo)

  return args[0]

# (addverb obj info args)
defBuiltin "addverb":
  if args.len != 3:
    return E_ARGS.md("addverb takes 3 arguments")

  let objd = evalD(args[0])
  checkForError(objd)
  let obj = extractObject(objd)

  let infod = evalD(args[1])
  checkForError(infod)
  checkType(infod, dList)
  let info = verbInfoFromInput(infod.listVal)

  let argsd = evalD(args[2])
  checkForError(argsd)
  checkType(argsd, dList)
  let args = verbArgsFromInput(argsd.listVal)

  var verb = newVerb(
    names = "unnamed verb",
    owner = nil
  )
  verb.setInfo(info)
  verb.setArgs(args)

  obj.verbs.add(verb)

  return objd

# (move what dest)
defBuiltin "move":
  if args.len != 2:
    return E_ARGS.md("move takes exactly 2 arguments")

  let
    whatd = evalD(args[0])
    destd = evalD(args[1])

  checkForError(whatd)
  checkForError(destd)

  var
    what = extractObject(whatd)
    dest = extractObject(destd)

  checkOwn(owner, what)

  let whatlist = @[what.md]

  let acc = dest.verbCall("accept", caller, whatlist)

  if not acc.truthy:
    return E_NACC.md("moving $1 to $2 refused" % [what.toObjStr(), dest.toObjStr()])

  # check for recursive move
  var conductor = dest

  while conductor != nil:
    if conductor == what:
      return E_RECMOVE.md("moving $1 to $2 is recursive" % [what.toObjStr(), dest.toObjStr()])
    conductor = conductor.getLocation()

  var moveSucceeded = what.moveTo(dest)

  if not moveSucceeded:
    return E_FMOVE.md("moving $1 to $2 failed (it could already be at $2)" %
          [what.toObjStr(), dest.toObjStr()])

  let oldLoc = what.getLocation()
  if oldLoc != nil:
    discard oldLoc.verbCall("exitfunc", caller, whatlist)

  discard dest.verbCall("enterfunc", caller, whatlist)
  return what.md


# (try (what) (except) (finally))
defBuiltin "try":
  let alen = args.len
  if not (alen == 2 or alen == 3):
    return E_ARGS.md("try takes 2 or 3 arguments")

  let tryClause = evalD(args[0])

  # here we do manual error handling
  if tryClause.isType(dErr):
    var newSymtable = symtable
    newSymtable["error"] = tryClause.errMsg.md
    let exceptClause = evalD(args[1], st = newSymtable)
    checkForError(exceptClause)
    return exceptClause

  if alen == 3:
    let finallyClause = evalD(args[2])
    checkForError(finallyClause)
    return finallyClause

# (lambda (var) (expr-in-var))
defBuiltin "lambda":
  let alen = args.len
  if alen < 2:
    return E_ARGS.md("lambda takes 2 or more arguments")

  if alen == 2:
    return (@["lambda".mds] & args).md

  var newSymtable = symtable
  let boundld = args[0]
  checkType(boundld, dList)

  let
    boundl = boundld.listVal
    numBound = boundl.len

  if alen != 2 + numBound:
    return E_ARGS.md("lambda taking $1 arguments given $2 instead" %
            [$numBound, $(alen - 2)])

  let lambdaArgs = args[2 .. -1]
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
    return E_ARGS.md("istype takes 2 arguments")

  let
    what = args[0]
    typed = args[1]
  checkType(typed, dStr)

  let (valid, typedVal) = strToType(typed.strVal)
  if not valid:
    return E_ARGS.md("'$1' is not a valid data type" % typed.strVal)

  if what.isType(typedVal):
    return 1.md
  else:
    return 0.md

# (call lambda-or-builtin args)
# forces evaluation (is this a good way to do it?)
defBuiltin "call":
  if args.len < 1:
    return E_ARGS.md("call takes one or more argument (lambda then arguments)")

  let execd = args[0]
  if execd.isType(dSym):
    let stmt = (@[execd] & args[1 .. -1]).md

    return evalD(stmt)
  elif execd.isType(dList):
    var lambl = execd.listVal
    if lambl.len != 3:
      return E_ARGS.md("call: invalid lambda")

    lambl = lambl & args[1 .. -1]

    return evalD(lambl.md)
  else:
    return E_ARGS.md("call's first argument must be a builtin symbol or a lambda")

# (map list func)
# this builtin lets (call) validate the "function" passed
defBuiltin "map":
  if args.len != 2:
    return E_ARGS.md("map takes 2 arguments")

  let
    lamb = args[0]
    listd = args[1]

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
    return E_ARGS.md("reduce takes 2 or 3 arguments")

  let
    lamb = args[0]
    listd = evalD(if alen == 2: args[1] else: args[2])

  checkForError(listd)
  checkType(listd, dList)
  var list = listD.listVal
  if list.len == 0:
    return nilD

  var start: MData
  if alen == 2:
    start = evalD(list[0])
    list = list[1 .. -1]
  elif alen == 3:
    start = evalD(args[1])

  checkForError(start)

  var res: MData = start
  for el in list:
    res = evalD(genCall(lamb, @[res, el]))

  return res

template defArithmeticOperator(name: string, op: proc(x: float, y: float): float) {.immediate.} =
  defBuiltin name:
    if args.len != 2:
      return E_ARGS.md("$1 takes 2 arguments" % name)

    var lhsd = evalD(args[0])
    checkForError(lhsd)
    var rhsd = evalD(args[1])
    checkForError(rhsd)

    var
      lhs: float
      rhs: float

    if lhsd.isType(dInt):
      lhs = lhsd.intVal.float
    elif lhsd.isType(dFloat):
      lhs = lhsd.floatVal
    else:
      return E_ARGS.md("invalid number " & $lhsd)
    if rhsd.isType(dInt):
      rhs = rhsd.intVal.float
    elif rhsd.isType(dFloat):
      rhs = rhsd.floatVal
    else:
      return E_ARGS.md("invalid number " & $rhsd)

    if lhsd.isType(dInt) and rhsd.isType(dInt):
      return op(lhs, rhs).int.md
    else:
      return op(lhs, rhs).md

defArithmeticOperator("+", `+`)
defArithmeticOperator("-", `-`)
defArithmeticOperator("*", `*`)
defArithmeticOperator("/", `/`)

# (cat str1 str2 ...)
# (cat list1 list2 ...)
# concats any number of strings or lists in a list
# use (call cat (str-list/list-list)) to call it with a list
defBuiltin "cat":
  if args.len < 1:
    return E_ARGS.md("cat needs at least one string")

  let typ = args[0].dtype
  if typ == dStr:
    var total = ""
    for argd in args:
      let arg = evalD(argd)
      checkForError(arg)
      total &= arg.toEchoString()
    return total.md
  elif typ == dList:
    var total: seq[MData] = @[]
    for argd in args:
      let arg = evalD(argd)
      checkForError(arg)
      checkType(arg, dList)
      total.add(arg.listVal)
    return total.md
  else:
    return E_ARGS.md("cat only concatenates strings or lists")
