# The interpreter of the scripting language used in the system

import types, objects, tables, strutils, math, sequtils

type
  TokenType = enum
    OPAREN_TOK, CPAREN_TOK,
    ATOM_TOK, QUOTE_TOK

  Token = object
    ttype: TokenType
    image: string
    pos: CodePosition

  MParseError* = object of Exception

  MParser* = ref object
    code: string
    tokens: seq[Token]
    tindex: int

proc `$`*(token: Token): string =
  token.image

proc nextCol(pos: var CodePosition) =
  pos.col += 1

proc nextLine(pos: var CodePosition) =
  pos.line += 1
  pos.col = 1

## LEXER

template addtoken {.immediate.} =
  result.add(curToken)
  curToken = Token(ttype: ATOM_TOK, image: "", pos: pos)

template addword {.immediate.} =
  if curWord.len > 0:
    curToken.ttype = ATOM_TOK
    curToken.image = curWord
    addtoken()
    curWord = ""

proc lex*(code: string): seq[Token] =
  newSeq(result, 0)
  var
    curToken = Token(ttype: ATOM_TOK, image: "")
    curWord = ""
    strMode = false
    commentMode = false
    skipNext = false

    pos: CodePosition = (1, 1)

  for idx, c in code & " ":
    pos.nextCol()
    if strMode:
      if c == '"' and not skipNext:
        curWord &= "\""
        strMode = false
      elif c == '\\' and not skipNext:
        skipNext = true
      else:
        if skipNext and c == 'n':
          curWord &= "\n"
        else:
          curWord &= $c

        if skipNext: skipNext = false
    elif commentMode:
      if c == "\n"[0]:
        commentMode = false
    else:
      if c in Whitespace:
        addword()
        if c & "" == "\n": # why nim
          pos.nextLine()
      elif c == '\'' and curWord.len == 0:
        curToken.ttype = QUOTE_TOK
        curToken.image = "'"
        addtoken()
      elif c == '(':
        addword()
        curToken.ttype = OPAREN_TOK
        curToken.image = "("
        addtoken()
      elif c == ')':
        addword()
        curToken.ttype = CPAREN_TOK
        curToken.image = ")"
        addtoken()
      elif c == '"':
        curWord = "\""
        strMode = true
      elif c == ';':
        addword()
        commentMode = true
      else:
        curWord &= $c

## PARSER

proc toData(image: string): MData =
  let
    leader = image[0]
    rest = image[1 .. ^1]

  # Shorthand: obj.propname expands to (getprop obj "propname")
  if '.' in image and leader notin {'"', '\'', '-', '.'} and leader notin Digits:
    let parts = image.split('.')
    if parts.len > 1:
      let obj = parts[0..^2].join(".").toData()
      let propname = parts[^1].md
      return @["getprop".mds, obj, propname].md
    else:
      raise newException(MParseError, "misplaced dot in " & image)

  try:
    let err = parseEnum[MError](image)
    return err.md
  except ValueError:
    discard

  case leader:
    of '#':
      if ':' in image:
        return image.mds

      try:
        let num = parseInt(rest)
        return num.ObjID.md
      except OverflowError:
        raise newException(MParseError, "object id overflow " & image)
      except ValueError:
        raise newException(MParseError, "invalid object " & image)
    of '"':
      return rest[0 .. ^2].md
    of Digits, '-', '.':
      if image == "-": # special case
        return "-".mds
      else:
        try:
          if '.' in image or 'e' in image:
            result = parseFloat(image).md
          else:
            result = parseInt(image).md
        except OverflowError:
          raise newException(MParseError, "number overflow " & image)
        except ValueError:
          raise newException(MParseError, "malformed number " & image)
    else:
      return image.mds


proc toData(token: Token): MData =
  if token.ttype != ATOM_TOK: return nilD
  var data = token.image.toData()
  data.pos = token.pos
  return data

proc newParser*(code: string): MParser =
  var fixedCode = code.strip()
  if fixedCode.len == 0:
    fixedCode = "()"

  MParser(
    code: fixedCode,
    tokens: lex(fixedCode),
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
  parser.tokens[index]

proc consume(parser: var MParser, ttype: TokenType): Token =
  let tok = parser.getToken()
  if tok.ttype != ttype:
    raise newException(MParseError, "expected token " & $ttype & ", instead got " & $tok.ttype)

  return tok
proc parseList*(parser: var MParser): MData

proc parseAtom*(parser: var MParser): MData =
  var quotePos: CodePosition = (0, 0)
  var quote = false

  var next = parser.peek()
  if next.ttype == QUOTE_TOK:
    quotePos = parser.consume(QUOTE_TOK).pos
    next = parser.peek()
    quote = true

  case next.ttype:
    of OPAREN_TOK:
      result = parser.parseList()
    of ATOM_TOK:
      result = parser.consume(ATOM_TOK).toData()
    else:
      raise newException(MParseError, "unexpected token '" & next.image & "'")

  if quote:
    var quoteSym = "quote".mds
    quoteSym.pos = quotePos
    result = @[quoteSym, result].md

proc parseList*(parser: var MParser): MData =
  var resultL: seq[MData] = @[]

  discard parser.consume(OPAREN_TOK)

  var next = parser.peek()
  while next.ttype != CPAREN_TOK:
    if next.ttype == OPAREN_TOK:
      resultL.add(parser.parseList())
    else:
      resultL.add(parser.parseAtom())
    next = parser.peek()
  discard parser.consume(CPAREN_TOK)

  # Shorthand syntax: (obj:verb arg1 arg2 ...) => (verbcall obj "verb" (arg1 arg2 ...))
  if resultL.len > 0:
    let first = resultL[0]
    if first.isType(dSym):
      let name = first.symVal
      let parts = name.split(":")
      if parts.len > 1:
        if resultL.len > 1:
          resultL[1..^1] = [resultL[1..^1].md]
        resultL[0] = parts[0].toData()
        resultL.insert(parts[1].md, 1)
        var verbCallSymbol = "verbcall".mds
        verbCallSymbol.pos = first.pos
        resultL.insert(verbCallSymbol, 0)

  return resultL.md


var builtins* = initTable[string, BuiltinProc]()

proc builtinExists*(name: string): bool =
  builtins.hasKey(name)

## DISPLAYING PARSED CODE

proc toCodeStr*(parsed: MData): string =
  result = ""
  if parsed.isType(dList):
    var list = parsed.listVal
    result.add('(')
    result.add(list.map(toCodeStr).join(" "))
    result.add(')')
  elif parsed.isType(dSym):
    result.add(($parsed)[1 .. ^1])
  else:
    result.add($parsed)

# defining builtins

template defBuiltin*(name: string, body: stmt) {.immediate, dirty.} =
  scripting.builtins[name] =
    proc (args: seq[MData], world: World, caller, owner: MObject,
          symtable: SymbolTable, pos: CodePosition, phase = 0,
          task: Task = nil): Package =
      # to provide a simpler call to eval (note the optional args)
      proc evalD(e: MData, w: World = world, c: MObject = caller,
                 o: MObject = owner, st: SymbolTable = symtable): MData =
        return e # Disabled

      proc builtinCall(othername: string, args = args, world = world, caller = caller,
                       owner = owner, symtable = symtable, pos = pos, phase = phase,
                       task = task): Package =
        scripting.builtins[othername](args, world, caller, owner, symtable, pos, phase, task)

      # to avoid "declared but not used" warnings
      discard evalD
      discard builtinCall

      body

