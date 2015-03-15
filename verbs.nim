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
  Prepositions*: seq[Preposition] = @[
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
    (pOff, "off"), (pOff, "off of"),

    (pNone, "none")
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

proc setCode*(verb: MVerb, newCode: string) =
  verb.code = newCode
  var parser = newParser(newCode)
  verb.parsed = parser.parseList()

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

  return name.len == str.len or ci == '*' or tolerateSize

proc call(verb: MVerb, world: var World, caller: MObject, symtable: SymbolTable): MData =
  eval(verb.parsed, world, caller, verb.owner, symtable)

proc matchesName(verb: MVerb, str: string): bool =
  let names = verb.names.split(" ")
  for name in names:
    if nameMatchesStr(name, str):
      return true

  return false

iterator matchingVerbs(obj: MObject, name: string): MVerb =
  for v in obj.verbs:
    if v.matchesName(name):
      yield v

proc getVerb*(obj: MObject, name: string): MVerb =
  for v in matchingVerbs(obj, name):
    return v

  return nil

iterator vicinityVerbs(obj: MObject, name: string): tuple[o: MObject, v: MVerb] =
  var searchSpace = obj.getVicinity()

  var world = obj.getWorld()
  doAssert(world != nil)
  searchSpace.add(world.getVerbObj())

  for o in searchSpace:
    for v in matchingVerbs(o, name):
      if obj.canExecute(v):
        yield (o, v)

proc verbCall*(owner: MObject, name: string, caller: MObject, args: seq[MData]): MData =
  var
    world = caller.getWorld()
    symtable = initSymbolTable()

  doAssert(world != nil)


  symtable["caller"] = caller.md
  symtable["args"] = args.md

  for v in matchingVerbs(owner, name):
    if caller.canExecute(v):
      return v.call(world, caller, symtable)

  return nilD


proc handleCommand*(obj: MObject, command: string): MData =

  let
    parsed = parseCommand(command)
    verb = parsed.verb
    doString = parsed.doString
    ioString = parsed.ioString
    prep = parsed.prep
    rest = parsed.rest

    doQuery = obj.query(doString.toLower())
    ioQuery = obj.query(ioString.toLower())
    restQuery = obj.query(rest.toLower())

  var
    world = obj.getWorld()
    symtable = initSymbolTable()

  symtable["caller"] = obj.md

  for o, v in vicinityVerbs(obj, verb):
    symtable["dobjstr"] = doString.md
    symtable["iobjstr"] = ioString.md
    symtable["dobj"] = nilD
    symtable["iobj"] = nilD
    symtable["argstr"] = rest.md

    if v.prepSpec != pNone and v.prepSpec != prep.ptype:
      continue

    var
      useddoQuery = doQuery
      useddoString = doString

    if v.prepSpec == pNone:
      useddoQuery = restQuery
      useddoString = rest
      symtable["dobjstr"] = useddoString.md

    if useddoQuery.len > 0:
      if v.doSpec == oAny:
        symtable["dobj"] = useddoQuery[0].md
      elif v.doSpec == oStr:
        discard
      elif v.doSpec == oThis:
        if useddoQuery[0] != o:
          continue
        else:
          symtable["dobj"] = o.md
      else:
        continue
    else:
      if v.doSpec == oNone:
        discard
      elif v.doSpec == oStr:
        if useddoString.len == 0:
          continue
        else:
          discard
      else:
        continue

    if ioQuery.len > 0:
      if v.ioSpec == oAny:
        symtable["iobj"] = ioQuery[0].md
      elif v.ioSpec == oStr:
        discard
      elif v.ioSpec == oThis:
        if ioQuery[0] != o:
          continue
        else:
          symtable["iobj"] = o.md
      else:
        continue
    else:
      if v.ioSpec == oNone:
        discard
      elif v.ioSpec == oStr:
        if ioString.len == 0:
          continue
        else:
          discard
      else:
        continue

    return v.call(world, obj, symtable)

  obj.send("Sorry, I couldn't understand that")
  return nilD

