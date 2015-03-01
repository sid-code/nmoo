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

template extractObject(where: expr, objd: MData) {.immediate.} =
  let obj = world.dataToObj(objd)
  if obj == nil:
    return E_ARGS.md("invalid object " & $objd)

  where = obj

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
template canWrite(obj: MObject, what: MVerb) =
  if not obj.canWrite(what):
    return E_PERM.md(obj.toObjStr() & " cannot write verb: " & what.names)


defBuiltin "echo":
  var newArgs: seq[MData] = @[]
  for arg in args:
    let res = evalD(arg)
    checkForError(res)
    echo res
    newArgs.add(res)
  return newArgs.md

defBuiltin "do":
  var newArgs: seq[MData] = @[]
  for arg in args:
    let res = evalD(arg)
    checkForError(res)
    newArgs.add(res)

  return newArgs.md

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

# (getprop what propname)
defBuiltin "getprop":
  if not args.len == 2:
    return E_ARGS.md("getprop takes exactly 2 arguments")

  let objd = args[0]
  checkType(objd, dObj)
  var obj: MObject
  extractObject(obj, objd)

  let propd = args[1]
  checkType(propd, dStr)
  let
    prop = propd.strVal
    propO = obj.getProp(prop)

  if propO == nil:
    return nilD

  owner.checkRead(propO)

  return propO.val

# (setprop what propname newprop)
defBuiltin "setprop":
  if not args.len == 3:
    return E_ARGS.md("setprop takes exactly 3 arguments")

  let objd = args[0]
  checkType(objd, dObj)
  var obj: MObject
  extractObject(obj, objd)


  let
    propd = args[1]
    newVal = args[2]
  checkType(propd, dStr)
  let
    prop = propd.strVal
    oldProp = obj.getProp(prop)

  if oldProp == nil:
    owner.checkWrite(obj)
    var propO = obj.setProp(prop, newVal)

    # If the property didn't exist before, we want its owner to be us,
    # not the object that it belongs to.
    propO.owner = owner
  else:
    var propO = obj.getProp(prop)
    owner.checkWrite(propO)
    propO.val = newVal

  return newVal

# (move what dest)
defBuiltin "move":
  if args.len != 2:
    return E_ARGS.md("move takes exactly 2 arguments")

  let
    whatd = evalD(args[0])
    destd = evalD(args[1])

  checkForError(whatd)
  checkForError(destd)

  checkType(whatd, dObj)
  var what: MObject
  extractObject(what, whatd)

  checkType(destd, dObj)
  var dest: MObject
  extractObject(dest, destd)

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
    newSymtable["error"] = tryClause
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

defBuiltin "call":
  if args.len < 1:
    return E_ARGS.md("call takes one or more argument (lambda then arguments)")

  let lamb = args[0]
  checkType(lamb, dList)
  var lambl = lamb.listVal
  if lambl.len != 3:
    return E_ARGS.md("call: invalid lambda")

  lambl = lambl & args[1 .. -1]

  return evalD(lambl.md)
