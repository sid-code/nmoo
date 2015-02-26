import types, objects, tables, strutils, math, sequtils

type
  TokenType = enum
    OPAREN_TOK, CPAREN_TOK,
    ATOM_TOK

  Token = object
    ttype: TokenType
    image: string

  MParseError* = object of Exception

  MParser* = ref object
    code: string
    tokens: seq[Token]
    tindex: int

proc initSymbolTable*: SymbolTable = initTable[string, MData]()

proc `$`*(token: Token): string =
  token.image
## LEXER

template ADD {.immediate.} =
  result.add(curToken)
  curToken = Token(ttype: ATOM_TOK, image: "")

template ADDWORD {.immediate.} =
  if curWord.len > 0:
    curToken.ttype = ATOM_TOK
    curToken.image = curWord
    ADD()
    curWord = ""

proc lex*(code: string): seq[Token] =
  result = @[]
  var
    curToken = Token(ttype: ATOM_TOK, image: "")
    curWord = ""
    strMode = false
    skipNext = false

  for idx, c in code & " ":
    if strMode:
      if c == '"' and not skipNext:
        curWord &= "\""
        strMode = false
      elif c == '\\' and not skipNext:
        skipNext = true
      else:
        curWord &= $c
        if skipNext: skipNext = false

    else:
      if c in Whitespace:
        ADDWORD()
      elif c == '(':
        ADDWORD()
        curToken.ttype = OPAREN_TOK
        curToken.image = "("
        ADD()
      elif c == ')':
        ADDWORD()
        curToken.ttype = CPAREN_TOK
        curToken.image = ")"
        ADD()
      elif c == '"':
        curWord = "\""
        strMode = true
      else:
        curWord &= $c

## PARSER

proc toData(token: Token): MData =
  if token.ttype != ATOM_TOK: return nilD
  result = nilD

  let
    image = token.image
    leader = image[0]
    rest = image[1 .. -1]

  case leader:
    of '#':
      try:
        let num = parseInt(rest)
        result = num.ObjID.md
      except OverflowError:
        raise newException(MParseError, "object id overflow " & image)
      except ValueError:
        raise newException(MParseError, "invalid object " & image)
    of '\'':
      result = rest.mds
    of '"':
      result = rest[0 .. -2].md
    of Digits, '-', '.':
      try:
        let num = parseFloat(image)
        if num.floor == num:
          result = num.int.md
        else:
          result =  num.md
      except OverflowError:
        raise newException(MParseError, "number overflow " & image)
      except ValueError:
        raise newException(MParseError, "malformed number " & image)
    else:
      result = image.mds

proc newParser*(code: string): MParser =
  MParser(
    code: code,
    tokens: lex(code),
    tindex: 0
  )

proc getToken(parser: var MParser): Token =
  result = parser.tokens[parser.tindex]
  parser.tindex += 1
  if parser.tindex > parser.tokens.len:
    raise newException(MParseError, "ran out of tokens unexpectedly")

proc peek(parser: MParser, distance: int = 0): Token =
  let index = parser.tindex + distance
  if index >= parser.tokens.len:
    raise newException(MParseError, "ran out of tokens unexpectedly")
  parser.tokens[parser.tindex + distance]

proc consume(parser: var MParser, ttype: TokenType): Token =
  let tok = parser.getToken()
  if tok.ttype != ttype:
    raise newException(MParseError, "expected token " & $ttype & ", instead got " & $tok.ttype)

  return tok

proc parseList*(parser: var MParser): MData =
  var resultL: seq[MData] = @[]

  discard parser.consume(OPAREN_TOK)

  var next = parser.peek()
  while next.ttype != CPAREN_TOK:
    if next.ttype == OPAREN_TOK:
      resultL.add(parser.parseList())
    else:
      resultL.add(parser.consume(ATOM_TOK).toData())
    next = parser.peek()
  discard parser.consume(CPAREN_TOK)

  return resultL.md



## EVALUATOR

var builtins* = initTable[string, BuiltinProc]()

proc resolveSymbol(symVal: string, symtable: SymbolTable): MData =
  if not symtable.hasKey(symVal):
    E_UNBOUND.md("unbound symbol '$1'" % symVal)
  else:
    symtable[symVal]

proc eval*(exp: MData, world: var World, caller, owner: MObject,
           symtable: SymbolTable = initSymbolTable()): MData =
  if not exp.isType(dList):
    if exp.isType(dSym):
      return resolveSymbol(exp.symVal, symtable)
    else:
      return exp

  var listv = exp.listVal
  if listv.len == 0 or not listv[0].isType(dSym):
    return exp


  var listvr = listv[1 .. -1]
  for idx, el in listvr:
    if el.isType(dSym):
      let val = resolveSymbol(el.symVal, symtable)
      if val.isType(dErr):
        return val
      else:
        listvr[idx] = val

  let
    sym = listv[0].symVal

  if builtins.hasKey(sym):
    return builtins[sym](listvr, world, caller, owner, symtable)
  else:
    return E_BUILTIN.md

template defBuiltin(name: string, body: stmt) {.immediate.} =
  var bproc: BuiltinProc = proc (args: var seq[MData], world: var World,
                                 caller, owner: MObject, symtable: SymbolTable): MData =
    # to provide a simpler call to eval (note the optional args)
    proc evalD(e: MData, w: var World = world, c: MObject = caller,
               o: MObject = owner, st: SymbolTable = symtable): MData =
      eval(e, w, c, o, st)

    body

  builtins[name] = bproc

template checkForError(value: MData) {.immediate.} =
  if value.isType(dErr):
    return value

template checkType(value: MData, expected: MDataType, ifnot: MError = E_ARGS)
          {.immediate.} =
  if not value.isType(expected):
    return ifnot.md("expected argument of type " & $expected & " instead got " & $value.dType)

proc toObjStr(obj: MObject): string =
  let 
    name = obj.getPropVal("name")
    objdstr = $obj.md
  if name.isType(dStr):
    return "$2 ($1)" % [objdstr, name.strVal]
  else:
    return "No name ($1)" % objdstr

proc toObjStr(objd: MData, world: World): string =
  ## Converts MData holding objects into strings
  let 
    obj = world.dataToObj(objd)
  if obj == nil:
    return "Invalid object ($1)" % $objd
  else:
    return toObjStr(obj)

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
  for arg in args:
    let res = evalD(arg)
    checkForError(res)
    echo res
  return args.md

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
