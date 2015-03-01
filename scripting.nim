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
    if not builtins.hasKey(symVal):
      return E_UNBOUND.md("unbound symbol '$1'" % symVal)
    else:
      return symVal.mds
  else:
    return symtable[symVal]

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
    return E_BUILTIN.md("undefined builtin: $1" % sym)


