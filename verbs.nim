# this file is for everything from command parsing to command handling
# not just verbs

import types, objects, querying, scripting, strutils, tables

type

  Preposition = tuple[ptype: PrepType, image: string]
  ParsedCommand = object
    verb: string
    rest: string
    doString: string
    ioString: string
    prep: Preposition

const
  Prepositions: seq[Preposition] = @[
    (pWith, "with"),
    (pWith, "using"),
    (pAt, "at"), (pAt, "to"),
    (pInFront, "in front of"),
    (pIn, "in"), (pIn, "inside"), (pIn, "into"),
    (pOn, "on top of"), (pOn, "on"), (pOn, "onto"), (pOn, "upon"),
    (pFrom, "out of"), (pFrom, "from inside"), (pFrom, "from"),
    (pOver, "over"),
    (pThrough, "through"),
    (pUnder, "under"), (pUnder, "underneath"), (pUnder, "beneath"),
    (pBehind, "behind"),
    (pBeside, "beside"),
    (pFor, "for"), (pFor, "about"),
    (pIs, "is"),
    (pAs, "as"),
    (pOff, "off"), (pOff, "off of")
  ]

proc newParsedCommand: ParsedCommand =
  ParsedCommand(verb: "", rest: "", doString: "", ioString: "", prep: (pNone, ""))

proc parseCommand(str: string): ParsedCommand =
  let firstSpace = str.find(' ')
  var prepLoc = 0

  result = newParsedCommand()

  if firstSpace == -1:
    result.verb = str[0 .. firstSpace]
  else:
    result.verb = str[0 .. firstSpace - 1]

  if firstSpace == -1:
    result.rest = ""
  else:
    result.rest = str[firstSpace + 1 .. -1]

    for prep in Prepositions:
      prepLoc = result.rest.find(prep.image)
      if prepLoc > -1:
        result.prep = prep
        break

    if prepLoc == -1:
      result.doString = result.rest
    else:
      result.doString = result.rest[0 .. prepLoc - 2]
      result.ioString = result.rest[prepLoc + result.prep.image.len + 1 .. -1]

proc nameMatchesStr(name: string, str: string): bool =
  if name == "*": return true

  var
    i = 0
    j = 0
    tolerateSize = false

  var
    ci = '\0'
    cj = '\0'

  while i < name.len and j < str.len:
    ci = name[i]
    cj = str[j]

    if ci == '*':
      i += 1
      tolerateSize = true
      continue

    if ci != cj:
      return false

    i += 1
    j += 1

  return ci == '*' or tolerateSize

proc verbMatchesName(verb: MVerb, str: string): bool =
  let names = verb.names.split(" ")
  for name in names:
    if nameMatchesStr(name, str):
      return true

  return false

proc handleCommand*(obj: MObject, command: string): MData =

  let
    parsed = parseCommand(command)
    verb = parsed.verb
    doString = parsed.doString
    ioString = parsed.ioString
    prep = parsed.prep
    rest = parsed.rest

    doQuery = obj.query(doString)
    ioQuery = obj.query(ioString)

  var world = obj.getWorld

  var searchSpace = obj.getVicinity()
  searchSpace.add(obj)

  doAssert(world != nil)
  searchSpace.add(world.getVerbObj())

  var symtable = initSymbolTable()
  symtable["caller"] = obj.md

  for o in searchSpace:
    for v in o.verbs:
      let owner = v.owner
      doAssert(owner != nil)

      symtable["dobjstr"] = doString.md
      symtable["iobjstr"] = ioString.md
      symtable["dobj"] = nilD
      symtable["iobj"] = nilD
      symtable["argstr"] = rest.md

      if v.prepSpec != prep.ptype:
        continue

      if doQuery.len > 0:
        if v.doSpec == oAny:
          symtable["dobj"] = doQuery[0].md
        elif v.doSpec == oStr:
          discard
        else:
          continue
      else:
        if v.doSpec == oThis:
          symtable["dobj"] = o.md
        elif v.doSpec == oNone:
          discard
        else:
          continue

      if ioQuery.len > 0:
        if v.ioSpec == oAny:
          symtable["iobj"] = ioQuery[0].md
        elif v.ioSpec == oStr:
          discard
        else:
          continue
      else:
        if v.ioSpec == oThis:
          symtable["iobj"] = o.md
        elif v.ioSpec == oNone:
          discard
        else:
          continue
      
      return eval(v.parsed, world, symtable, owner.level)
      
  return nilD

