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
  result.tokens.add(curToken)
  curToken = Token(ttype: tokAtom, image: "", pos: pos)

template addword =
  if curWord.len > 0:
    curToken.ttype = tokAtom
    curToken.image = curWord
    addtoken()
    curWord = ""

proc lex(code: string): tuple[tokens: seq[Token], error: MData] =
  newSeq(result.tokens, 0)
  result.error = E_NONE.md
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
            result.error = E_PARSE.md("Invalid escape \\" & c)
            result.error.pos = pos
            return
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
    result.error = E_PARSE.md("unterminated string meets end of code")
    result.error.pos = pos
    return

  curToken.ttype = tokEnd
  curToken.image = ""
  addtoken()

## PARSER

# returns (data, "") if there is no error, otherwise (nil, "error
# description")
#
# Using Go-style error handling here seems dubious because I hardly do
# that anywhere else. However, since an error is data and this
# function can return arbitrary data values, there is no room for
# out-of-band errors. Hence, the string in the returned tuple.
proc toData(image: string, pos: CodePosition): (MData, string) =
  let
    leader = image[0]
    rest = image[1 .. ^1]

  # Shorthand: obj.propname expands to (getprop obj "propname")
  if '.' in image and leader notin {'"', '\'', '-', '.'} and leader notin Digits:
    let parts = image.split('.')
    if parts.len > 1:
      let objStr = parts[0..^2].join(".")
      let (obj, error) = objStr.toData(pos)

      if error.len > 0:
        return (nilD, error)

      var propname = parts[^1].md
      # compute the position of propname
      propName.pos = (pos.line + objStr.len + 1, pos.col)

      var getpropsym = "getprop".mds
      getpropsym.pos = pos

      return (@[getpropsym, obj, propname].md, "")
    else:
      return (nilD, "misplaced dot in " & image)

  try:
    let err = parseEnum[MError](image)
    return (err.md, "")
  except ValueError:
    discard

  case leader:
    of '#':
      if ':' in image:
        return (image.mds, "")

      try:
        let num = parseInt(rest)
        return (num.ObjID.md, "")
      except OverflowError:
        return (nilD, "object id overflow " & image)
      except ValueError:
        return (nilD, "invalid object " & image)
    of '"':
      return (rest[0 .. ^2].md, "")
    of Digits, '-', '.':
      try:
        if '.' in image or 'e' in image:
          return (parseFloat(image).md, "")
        else:
          return (parseInt(image).md, "")
      except OverflowError:
        return (nilD, "literal number overflow " & image)
      except ValueError:
        return (image.mds, "")
    else:
      if image == "nil":
        return (nilD, "")
      else:
        return (image.mds, "")

proc toData(token: Token): (MData, string) =
  if token.ttype != tokAtom:
    return (nilD, "")
  var (data, error) = token.image.toData(token.pos)

  if error.len > 0:
    return (nilD, error)

  data.pos = token.pos
  return (data, "")

proc newParser*(code: string): MParser =
  var fixedCode = code.strip()
  if fixedCode.len == 0:
    fixedCode = "()"

  let (tokens, errd) = lex(fixedCode)

  MParser(
    code: fixedCode,
    error: errd,
    tokens: tokens,
    tindex: 0
  )


template propogateError(parser: MParser) =
  if parser.error.errVal != E_NONE:
    # the empty return is fine, we just have to make sure we always
    # propogate if there's the possibility of error. This allows us to
    # use this template to propogate errors along call chains with
    # varying return types.
    return

template parseError(parser: var MParser, estr: string, epos: CodePosition) =
  parser.error = E_PARSE.md(estr)
  parser.error.pos = epos
  return

proc getToken(parser: var MParser): Token =
  result = parser.tokens[parser.tindex]
  parser.tindex += 1
  if parser.tindex > parser.tokens.len:
    parser.parseError("ran out of tokens unexpectedly", result.pos)

proc peek(parser: var MParser, distance: int = 0): Token =
  let index = parser.tindex + distance
  if index >= parser.tokens.len:
    parser.parseError("ran out of tokens unexpectedly", parser.tokens[^1].pos)
  parser.tokens[index]

proc consume(parser: var MParser, ttype: TokenType): Token =
  let tok = parser.getToken()
  if tok.ttype != ttype:
    parser.parseError("expected token " & $ttype & ", instead got " & $tok.ttype, tok.pos)

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
  parser.propogateError()
  if next.ttype in QuoteTokens:
    quoteTokType = next.ttype
    quotePos = parser.consume(quoteTokType).pos
    parser.propogateError()
    next = parser.peek()
    parser.propogateError()
    quote = true

  case next.ttype:
    of tokOParen:
      result = parser.parseList()
      parser.propogateError()
    of tokAtom:
      let (atom, errorStr) = parser.consume(tokAtom).toData()
      parser.propogateError()
      if errorStr.len > 0:
        parser.parseError(errorStr, next.pos)
      result = atom
    else:
      parser.parseError("unexpected token '" & next.image & "'", next.pos)

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
        parser.parseError("unknown quote token type: " & $quoteTokType, next.pos)

    quoteSym.pos = quotePos
    result = @[quoteSym, result].md

proc parseList*(parser: var MParser): MData =
  var resultL: seq[MData] = @[]

  let oparen = parser.consume(tokOParen)
  let pos = oparen.pos
  parser.propogateError()

  var next = parser.peek()
  parser.propogateError()

  while next.ttype != tokCParen:
    if next.ttype == tokOParen:
      resultL.add(parser.parseList())
      parser.propogateError()
    else:
      resultL.add(parser.parseAtom())
      parser.propogateError()

    next = parser.peek()
    parser.propogateError()

  discard parser.consume(tokCParen)
  parser.propogateError()

  # Shorthand syntax: (obj:verb arg1 arg2 ...) => (verbcall obj "verb" (list arg1 arg2 ...))
  if resultL.len > 0:
    let first = resultL[0]
    if first.isType(dSym):
      let name = first.symVal
      let parts = name.split(":")
      if parts.len > 1:
        if resultL.len > 1:
          resultL[1..^1] = [("list".mds & resultL[1..^1]).md]
        let (lhs, error) = parts[0].toData(pos)
        if error.len > 0:
          parser.parseError(error, pos)

        resultL[0] = lhs
        resultL.insert(parts[1].md, 1)
        var verbCallSymbol = "verbcall".mds
        verbCallSymbol.pos = first.pos
        resultL.insert(verbCallSymbol, 0)

  result = resultL.md
  result.pos = pos

proc parseFull*(parser: var MParser): MData =
  if parser.error.errVal != E_NONE:
    return parser.error

  var forms = @["do".mds]

  while parser.peek().ttype != tokEnd:
    forms.add(parser.parseAtom())
    parser.propogateError()

  discard parser.consume(tokEnd)
  parser.propogateError()

  return forms.md

var builtins* = initTable[string, BuiltinProc]()

proc builtinExists*(name: string): bool =
  builtins.hasKey(name)

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

