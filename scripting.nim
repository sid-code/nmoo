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

proc peek(parser: MParser, distance: int = 0): Token =
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

template defBuiltin(name: string, body: stmt) {.immediate.} =
  var bproc: BuiltinProc = proc (args: var seq[MData], symtable: SymbolTable, level: int): MData =
    body

  builtins[name] = bproc

proc resolveSymbol(symVal: string, symtable: SymbolTable): MData =
  if not symtable.hasKey(symVal):
    E_UNBOUND.md
  else:
    symtable[symVal]

proc eval*(exp: MData, symtable: SymbolTable = initSymbolTable(), level: int = 3): MData =
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
    return builtins[sym](listvr, symtable, level)
  else:
    return E_BUILTIN.md


defBuiltin "echo":
  for arg in args:
    let result = eval(arg, symtable, level)
    if result.isType(dErr):
      return result
    else:
      echo result
  return args.md

defBuiltin "do":
  var newArgs: seq[MData] = @[]
  for arg in args:
    let result = eval(arg, symtable, level)
    if result.isType(dErr):
      return result
    else:
      newArgs.add(result)

  return newArgs.md

defBuiltin "let":
  # First argument: list of pairs
  # Second argument: expression to evaluate with the symbol table
  if args.len != 2:
    return E_ARGS.md

  if not args[0].isType(dList):
    return E_ARGS.md

  var newSymtable = symtable

  let asmtList = args[0].listVal
  for asmt in asmtList:
    if not asmt.isType(dList):
      return E_ARGS.md
    let pair = asmt.listVal
    if not pair.len == 2:
      return E_ARGS.md
    if not pair[0].isType(dSym):
      return E_ARGS.md

    let 
      symName = pair[0].symVal
      setVal = eval(pair[1], newSymtable, level)

    if setVal.isType(dErr):
      return setVal
    newSymtable[symName] = setVal

  return eval(args[1], newSymtable, level)
