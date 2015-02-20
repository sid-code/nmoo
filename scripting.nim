import objects, tables, strutils

type
  BuiltinProc = proc(args: seq[MData]): MData
  TokenType = enum
    OPAREN_TOK, CPAREN_TOK,
    ATOM_TOK

  Token = object
    ttype: TokenType
    image: string

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

# proc toData(token: Token): MData =
#  case token.ttype:
#    of INT_TOK: parseInt(token.image).md
#    of FLOAT_TOK: parseFloat(token.image).md
#    of STR_TOK: token.image.md
#    of BIN_TOK: token.image.mdb
#    of ERR_TOK: parseEnum[MError](token.image, E_NONE).md
#    of OBJ_TOK: parseInt(token.image[1 .. -1]).ObjID.md
#    of NIL_TOK, OPAREN_TOK, CPAREN_TOK: nilD


## EVALUATOR

var builtins* = initTable[string, BuiltinProc]()

template defBuiltin(name: string, bproc: BuiltinProc) {.immediate.} =
  builtins[name] = bproc

defBuiltin("echo") do (args: seq[MData]) -> MData:
  echo args
  return args.md

proc eval(exp: MData): MData =
  if not exp.isType(dList):
    return exp

  var listv = exp.listVal
  if listv.len == 0 or not listv[0].isType(dBin):
    return exp

  var bin = listv[0].binVal

  for idx, term in listv:
    listv[idx] = eval(term)

  if builtins.hasKey(bin):
    return builtins[bin](listv[1 .. -1])
  else:
    return E_BUILTIN.md


