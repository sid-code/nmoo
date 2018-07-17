# The interpreter of the scripting language used in the system

import tables
import strutils
import math
import sequtils

import types
import objects

proc `$`*(token: Token): string =
  token.image

proc nextCol(pos: var CodePosition) =
  pos.col += 1

proc nextLine(pos: var CodePosition) =
  pos.line += 1
  pos.col = 1

## LEXER

template addtoken =
  result.add(curToken)
  curToken = Token(ttype: tokAtom, image: "", pos: pos)

template addword =
  if curWord.len > 0:
    curToken.ttype = tokAtom
    curToken.image = curWord
    addtoken()
    curWord = ""

proc lex(code: string): seq[Token] =
  newSeq(result, 0)
  var
    pos: CodePosition = (1, 1)
    curToken = Token(ttype: tokAtom, image: "", pos: pos)
    curWord = ""
    strMode = false
    commentMode = false
    skipNext = false

  for idx, c in code & " ":
    pos.nextCol()
    if strMode:
      if c == '"' and not skipNext:
        curWord &= "\""
        strMode = false
      elif c == '\\' and not skipNext:
        skipNext = true
      else:
        if skipNext:
          if c == 'n':
            curWord &= "\n"
          elif c == '"':
            curWord &= "\""
          elif c == '\\':
            curWord &= "\\"
          elif c == '\'':
            curWord &= "'"
          else:
            raise newException(MParseError, "invalid escape \\" & c)
        else:
          curWord &= $c

        if skipNext: skipNext = false
    elif commentMode:
      if c == "\n"[0]:
        commentMode = false
        pos.nextLine()
    else:
      if c in Whitespace:
        addword()
        if c & "" == "\n": # why nim
          pos.nextLine()
      elif c == '\'' and curWord.len == 0:
        curToken.ttype = tokQuote
        curToken.image = "'"
        addtoken()
      elif c == '`' and curWord.len == 0:
        curToken.ttype = tokQuasiQuote
        curToken.image = "`"
        addtoken()
      elif c == ',' and curWord.len == 0:
        curToken.ttype = tokUnquote
        curToken.image = ","
        addtoken()
      elif c == '(':
        addword()
        curToken.ttype = tokOParen
        curToken.image = "("
        addtoken()
      elif c == ')':
        addword()
        curToken.ttype = tokCParen
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

  if strMode:
    raise newException(MParseError, "unterminated string meets end of code")

  curToken.ttype = tokEnd
  curToken.image = ""
  addtoken()

## PARSER

proc toData(image: string, pos: CodePosition): MData =
  let
    leader = image[0]
    rest = image[1 .. ^1]

  # Shorthand: obj.propname expands to (getprop obj "propname")
  if '.' in image and leader notin {'"', '\'', '-', '.'} and leader notin Digits:
    let parts = image.split('.')
    if parts.len > 1:
      let objStr = parts[0..^2].join(".")
      let obj = objStr.toData(pos)

      var propname = parts[^1].md
      # compute the position of propname
      propName.pos = (pos.line + objStr.len + 1, pos.col)

      var getpropsym = "getprop".mds
      getpropsym.pos = pos

      return @[getpropsym, obj, propname].md
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
      try:
        if '.' in image or 'e' in image:
          result = parseFloat(image).md
        else:
          result = parseInt(image).md
      except OverflowError:
        raise newException(MParseError, "literal number overflow " & image)
      except ValueError:
        return image.mds
    else:
      if image == "nil":
        return nilD
      else:
        return image.mds

proc toData(token: Token): MData =
  if token.ttype != tokAtom: return nilD
  var data = token.image.toData(token.pos)
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

const QuoteTokens = {tokQuote, tokQuasiQuote, tokUnquote}

proc parseAtom*(parser: var MParser): MData =
  # An atom has two (potential) parts. The quote (optional), and the real stuff.
  # Before grabbing the real stuff, we need to check if there's a quote in the way.
  # If there is, we need to tack around the corresponding (quote ...) form.

  var quoteTokType: TokenType
  var quotePos: CodePosition = (0, 0)
  var quote = false

  var next = parser.peek()
  if next.ttype in QuoteTokens:
    quoteTokType = next.ttype
    quotePos = parser.consume(quoteTokType).pos
    next = parser.peek()
    quote = true

  case next.ttype:
    of tokOParen:
      result = parser.parseList()
    of tokAtom:
      result = parser.consume(tokAtom).toData()
    else:
      raise newException(MParseError, "unexpected token '" & next.image & "'")

  if quote:
    var quoteSym: MData
    case quoteTokType:
      of tokQuote:
        quoteSym = "quote".mds
      of tokQuasiQuote:
        quoteSym = "quasiquote".mds
      of tokUnquote:
        quoteSym = "unquote".mds
      else:
        raise newException(MParseError, "unknown quote token type: " & $quoteTokType)

    quoteSym.pos = quotePos
    result = @[quoteSym, result].md

proc parseList*(parser: var MParser): MData =
  var resultL: seq[MData] = @[]

  let oparen = parser.consume(tokOParen)
  let pos = oparen.pos

  var next = parser.peek()
  while next.ttype != tokCParen:
    if next.ttype == tokOParen:
      resultL.add(parser.parseList())
    else:
      resultL.add(parser.parseAtom())
    next = parser.peek()
  discard parser.consume(tokCParen)

  # Shorthand syntax: (obj:verb arg1 arg2 ...) => (verbcall obj "verb" (list arg1 arg2 ...))
  if resultL.len > 0:
    let first = resultL[0]
    if first.isType(dSym):
      let name = first.symVal
      let parts = name.split(":")
      if parts.len > 1:
        if resultL.len > 1:
          resultL[1..^1] = [("list".mds & resultL[1..^1]).md]
        resultL[0] = parts[0].toData(pos)
        resultL.insert(parts[1].md, 1)
        var verbCallSymbol = "verbcall".mds
        verbCallSymbol.pos = first.pos
        resultL.insert(verbCallSymbol, 0)

  result = resultL.md
  result.pos = pos

proc parseFull*(parser: var MParser): MData =
  var forms = @["do".mds]

  while parser.peek().ttype != tokEnd:
    forms.add(parser.parseAtom())

  discard parser.consume(tokEnd)
  return forms.md

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

# TODO: find out new meanings of immediate and dirty pragmas and see if they're
# really needed here.
template defBuiltin*(name: string, body: untyped) {.dirty.} =
  template bname: string = name
  scripting.builtins[name] =
    proc (args: seq[MData], world: World,
          self, player, caller, owner: MObject,
          symtable: SymbolTable, pos: CodePosition, phase = 0,
          task: Task = nil): Package =
      body

