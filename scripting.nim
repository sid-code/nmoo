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
    E_UNBOUND.md
  else:
    symtable[symVal]

proc eval*(exp: MData, world: var World, user: MObject,
           symtable: SymbolTable = initSymbolTable()): MData =
  if not exp.isType(dList):
    if exp.isType(dSym):
      let val = resolveSymbol(exp.symVal, symtable)
      if val.isType(dErr):
        return E_UNBOUND.md
      else:
        return val
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
        return E_UNBOUND.md
      else:
        listvr[idx] = val

  let
    sym = listv[0].symVal

  if builtins.hasKey(sym):
    return builtins[sym](listvr, world, user, symtable)
  else:
    return E_BUILTIN.md

template defBuiltin(name: string, body: stmt) {.immediate.} =
  var bproc: BuiltinProc = proc (args: var seq[MData], world: var World,
                                 user: MObject, symtable: SymbolTable): MData =
    # to provide a simpler call to eval (note the optional args)
    proc evalD(e: MData, w: var World = world, u: MObject = user,
               st: SymbolTable = symtable): MData =
      eval(e, w, u, st)

    body

  builtins[name] = bproc

template checkForError(value: MData) {.immediate.} =
  if value.isType(dErr):
    return value

template checkType(value: MData, expected: MDataType, ifnot: MError = E_ARGS)
          {.immediate.} =
  if not value.isType(expected):
    return ifnot.md

defBuiltin "echo":
  for arg in args:
    let res = evalD(arg)
    checkForError(res)
    echo result
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
    return E_ARGS.md

  let first = args[0]
  checkType(first, dList)
  if first.listVal.len != 2:
    return E_ARGS.md

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
      return E_ARGS.md
    let pair = asmt.listVal
    if not pair.len == 2:
      return E_ARGS.md
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
      return E_ARGS.md

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
    return E_ARGS.md

  let objd = args[0]
  checkType(objd, dObj)
  let obj = world.dataToObj(objd)
  if obj == nil:
    return E_ARGS.md

  if not user.canRead(obj):
    return E_PERM.md

  let propd = args[1]
  checkType(propd, dStr)
  let
    prop = propd.strVal
    propO = obj.getProp(prop)

  if propO == nil:
    return nilD

  if not user.canRead(propO):
    return E_PERM.md

  return propO.val

# (setprop what propname newprop)
defBuiltin "setprop":
  if not args.len == 3:
    return E_ARGS.md

  let objd = args[0]
  checkType(objd, dObj)
  let obj = world.dataToObj(objd)
  if obj == nil:
    return E_ARGS.md

  if not user.canWrite(obj):
    return E_PERM.md

  let
    propd = args[1]
    newVal = args[2]
  checkType(propd, dStr)
  let prop = propd.strVal
  var propO = obj.setProp(prop, newVal)

  propO.owner = user

  return newVal
