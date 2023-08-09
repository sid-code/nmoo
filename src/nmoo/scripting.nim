# The interpreter of the scripting language used in the system

import tables
import strutils
import math
import streams
import deques
from parseutils import parseHex

import types

proc `$`*(token: Token): string {.inline.} =
  token.image

proc nextCol(pos: var CodePosition) {.inline.} =
  pos.col += 1

proc nextLine(pos: var CodePosition) {.inline.} =
  pos.line += 1
  pos.col = 1

proc hasError[T](thingy: T): bool {.inline.} =
  return thingy.error.errVal != E_NONE

template propogateError[T](thingy: T) =
  if thingy.hasError():
    # the empty return is fine, we just have to make sure we always
    # propogate if there's the possibility of error. This allows us to
    # use this template to propogate errors along call chains with
    # varying return types.
    return

## LEXER

proc newLexer(code: string): MLexer =
  MLexer(stream: newStringStream(code), pos: (1, 1), error: E_NONE.md)

proc throwError(lexer: var MLexer, errstr: string) =
  var error = E_PARSE.md(errstr)
  error.pos = lexer.pos
  lexer.error = error

proc getChar(lexer: var MLexer): char =
  if lexer.stream.atEnd():
    return '\0'
  else:
    let c = lexer.stream.readChar()
    if c == '\n':
      lexer.pos.nextLine()
    else:
      lexer.pos.nextCol()
    return c

proc peekChar(lexer: var MLexer): char =
  if lexer.stream.atEnd():
    return '\0'
  else:
    return lexer.stream.peekChar()

proc wantChar(lexer: var MLexer, msgIfNoChar: string): char =
  result = lexer.getChar()
  if result == '\0':
    lexer.throwError(msgIfNoChar)

proc getStringLiteral(lexer: var MLexer): string =
  while true:
    let strchr = lexer.wantChar("unterminated string meets end of code")
    lexer.propogateError()

    if strchr == '"':
      return

    elif strchr == '\\':
      let escchr = lexer.getChar()
      if escchr == '\0':
        lexer.throwError("invalid escape")
        return
      elif escchr == '\'' or escchr == '\\':
        result &= escchr
      elif escchr == 'n':
        result &= '\n'
      elif escchr == 'x':
        let hex1 = lexer.wantChar("invalid hex escape; should be \\xHH")
        lexer.propogateError()
        let hex2 = lexer.wantChar("invalid hex escape; should be \\xHH")
        lexer.propogateError()

        if hex1 notin HexDigits or hex2 notin HexDigits:
          lexer.throwError("invalid hex esccape; only 0-9A-Fa-f allowed")
          return

        var ci: int
        discard parseHex(hex1 & hex2, ci)
        result &= chr(ci)
    else:
      result &= strchr

const IdentCharsXL = AllChars - {'"', '`', ',', '\'', '(', ')', '\0'} - Whitespace

proc getIdentifier(lexer: var MLexer): string =
  while true:
    if lexer.peekChar() notin IdentCharsXL:
      return

    result &= lexer.getChar()

proc skipComment(lexer: var MLexer) =
  var c = ';'
  while c notin {'\n', '\0'}:
    c = lexer.getChar()
    discard

proc getToken(lexer: var MLexer): Token =
  # If the lexer is in an error state, don't do anything
  lexer.propogateError()

  result.pos = lexer.pos
  result.ttype = tokAtom
  result.image = ""

  if lexer.stream.atEnd():
    result.ttype = tokEnd
    return

  # skip all whitespace and comments before this token
  var first = ' '
  while first in Whitespace + {';'}:
    if first == ';':
      lexer.skipComment()
    first = lexer.getChar()

  # update the pos
  result.pos = lexer.pos

  # now we switch on the first character
  case first:
    of '\0':
      result.ttype = tokEnd
      result.image = "<end>"

    of '"':
      # start of a string literal
      result.image = "\"$#\"".format(lexer.getStringLiteral())
      lexer.propogateError()

    of IdentCharsXL:
      result.image = first & lexer.getIdentifier()
      lexer.propogateError()

    of '(':
      result.ttype = tokOParen
      result.image = "("

    of ')':
      result.ttype = tokCParen
      result.image = ")"

    of '\'':
      result.ttype = tokQuote
      result.image = "'"

    of '`':
      result.ttype = tokQuasiQuote
      result.image = "`"

    of ',':
      result.ttype = tokUnquote
      result.image = ","

    else:
      lexer.throwError("unrecognized character '$#'".format(first))

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
      except OverflowDefect:
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
      except OverflowDefect:
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

proc newParser*(code: string, options: set[MParserOption] = {}): MParser =
  var fixedCode = code.strip()
  if fixedCode.len == 0:
    fixedCode = "()"

  #let (tokens, errd) = lex(fixedCode)
  let lexer = newLexer(code)

  MParser(
    code: fixedCode,
    error: E_NONE.md,
    lexer: lexer,
    queuedTokens: initDeque[Token](),
    options: options
  )

template parseError(parser: var MParser, estr: string, epos: CodePosition) =
  parser.error = E_PARSE.md(estr)
  parser.error.pos = epos
  return

proc getToken(parser: var MParser): Token =
  if len(parser.queuedTokens) > 0:
    return parser.queuedTokens.popFirst()

  result = parser.lexer.getToken()
  if parser.lexer.hasError():
    parser.error = parser.lexer.error
    return

proc peek(parser: var MParser, distance: int = 0): Token =
  result = parser.getToken()
  parser.queuedTokens.addLast(result)

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
      parser.parseError("unexpected token of type $#: '$#'".format(next.ttype, next.image), next.pos)

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

## The verb call syntax sugar takes two forms. One for verb calling at
## runtime, and another at compile time.
##
## Runtime:      (obj:verb arg1 arg2 ...)
## Compile time: (@obj:verb args arg2 ...)
##
## Remember, if you call a verb at compile time, the arguments are
## passed before evaluation.
proc transformVerbCallSyntax(parser: var MParser, form: var seq[MData], pos: CodePosition) =
  assert(form.len > 0) # sanity check

  let first = form[0]
  let name = first.symVal
  let parts = name.split(":")

  var verbCallSymbol: MData

  if parts.len > 1:
    if form.len > 0:
      var lhsStr = parts[0]
      if lhsStr[0] == '@':
        # (x a b c) => (x (quote (a b c)))
        form[1..^1] = [@["quote".mds, form[1..^1].md].md]
        verbCallSymbol = "macrocall".mds
        lhsStr = lhsStr[1..^1]
      else:
        # (x a b c) => (x (list a b c))
        form[1..^1] = [("list".mds & form[1..^1]).md]
        verbCallSymbol = "verbcall".mds

      let (lhs, error) = lhsStr.toData(pos)
      if error.len > 0:
        parser.parseError(error, pos)

      form[0] = lhs
      form.insert(parts[1].md, 1)
      verbCallSymbol.pos = first.pos
      form.insert(verbCallSymbol, 0)

proc transformDataForm(parser: var MParser, resultL: seq[MData], pos: CodePosition): MData =
  # The goal here is to transform the data form:
  #    '(table (a b) (c d))
  # into a MData of type dTable, not dList.
  #
  # TODO: perhaps also transform (list a b c)?
  var resultT = initTable[MData, MData]()
  for i in 1..resultL.len - 1:
    # do all of the checks
    if not resultL[i].isType(dList):
      parser.parseError("invalid table: format is (table (key1 val1) (key2 val2) ...)", pos)
    let pair = resultL[i].listVal
    if not pair.len == 2:
      parser.parseError("invalid table pair: need len 2", resultL[i].pos)

    let key = pair[0]
    let val = pair[1]

    resultT[key] = val

  result = resultT.md
  result.pos = pos

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

  if resultL.len == 0:
    result = resultL.md
    result.pos = pos
    return

  let first = resultL[0]

  # Shorthand syntax: (obj:verb arg1 arg2 ...) => (verbcall obj "verb" (list arg1 arg2 ...))
  if first.isType(dSym):
    parser.transformVerbCallSyntax(resultL, pos)
    parser.propogateError()

  if poTransformDataForms in parser.options:
    if first == "table".mds:
      result = parser.transformDataForm(resultL, pos)
      parser.propogateError()
      return

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
