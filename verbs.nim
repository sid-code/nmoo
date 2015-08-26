# this file is for everything from command parsing to command handling
# not just verbs

import types, objects, querying, scripting, compile
import strutils, tables, pegs

type

  Preposition = tuple[ptype: PrepType, image: string]
  ParsedCommand = object
    verb: string
    rest: seq[string]
    fixedRest: seq[string]
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

### Utilities
proc objSpecToStr*(osp: ObjSpec): string =
  ($osp).toLower[1 .. ^1]

proc strToObjSpec*(osps: string): tuple[success: bool, result: ObjSpec] =
  let realSpec = "o" & osps[0].toUpper & osps[1 .. ^1]
  try:
    return (true, parseEnum[ObjSpec](realSpec))
  except:
    return (false, oNone)

proc prepSpecToStr*(psp: PrepType): string =
  var images: seq[string] = @[]
  for prep in Prepositions:
    let (ptype, image) = prep
    if ptype == psp:
      images.add(image)

  return images.join("/")

proc strToPrepSpec*(psps: string): tuple[success: bool, result: PrepType] =
  let pspsLower = psps.toLower()

  for prep in Prepositions:
    let (ptype, image) = prep
    if image == pspsLower:
      return (true, ptype)

  return (false, pNone)

proc shellwords(str: string): seq[string] =
  newSeq(result, 0)
  let
    shellword = peg"""\" ( "\\" . / [^"] )* \" / \S+"""

  for match in str.findAll(shellword):
    result.add(match)

### End utilities

proc newParsedCommand: ParsedCommand =
  ParsedCommand(
    verb: "",
    rest: @[],
    fixedRest: @[],
    doString: "",
    ioString: "",
    prep: (pNone, "")
  )

proc parseCommand(str: string): ParsedCommand =
  let
    words = shellwords(str)
    fixup = peg"""\\{.} / \"{[^\\] / $}"""
    fixedWords = words.map(
      proc (w: string): string =
        w.replacef(fixup, "$1"))

  if words.len == 0:
    raise newException(Exception, "command cannot be an empty string!")

  result.verb = fixedWords[0]
  result.rest = words[1 .. ^1]
  result.fixedRest = fixedWords[1 .. ^1]

  var
    i = 1
    doString = ""
    ioString = ""

  while i < fixedWords.len:
    let word = fixedWords[i]
    i += 1

    let (success, ptype) = strToPrepSpec(word)
    if success:
      result.prep = (ptype, word)
      break
    else:
      doString.add(" ")
      doString.add(word)

  # The [1 .. ^1] subscript is necessary because the string will
  # have a leading space
  result.doString = doString[1 .. ^1]

  while i < fixedWords.len:
    let word = fixedWords[i]
    i += 1

    ioString.add(" ")
    ioString.add(word)

  result.ioString = ioString[1 .. ^1]

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

  return name.len == str.len or name[i] == '*' or tolerateSize

proc matchesName(verb: MVerb, str: string): bool =
  let names = verb.names.split(" ")
  for name in names:
    if nameMatchesStr(name, str):
      return true

  return false

proc allVerbsHelper(obj: MObject, collector: var seq[MVerb]) =
  collector.add(obj.verbs)
  if obj.parent != obj:
    allVerbsHelper(obj.parent, collector)

proc allVerbs*(obj: MObject): seq[MVerb] =
  newSeq(result, 0)
  allVerbsHelper(obj, result)

iterator matchingVerbs(obj: MObject, name: string): MVerb =
  for v in obj.allVerbs():
    if v.matchesName(name):
      yield v

proc getVerb*(obj: MObject, name: string): MVerb =
  for v in matchingVerbs(obj, name):
    return v

  return nil

proc addVerb*(obj: MObject, verb: MVerb): MVerb =
  obj.verbs.add(verb)
  return verb

proc addVerbRec*(obj: MObject, verb: MVerb): seq[tuple[o: MObject, v: MVerb]] =
  result = @[]
  result.add((obj, obj.addVerb(verb)))
  for child in obj.children:
    var verbCopy = verb.copy
    verbCopy.inherited = true
    result.add(child.addVerbRec(verbCopy))

proc delVerb*(obj: MObject, verb: MVerb): MVerb =
  for i, v in obj.verbs:
    # TODO: make a better way to check for verb equality
    if v.names == verb.names:
      obj.verbs.delete(i)
      return verb

  return nil

proc delVerbRec*(obj: MObject, verb: MVerb): seq[tuple[o: MObject, v: MVerb]] =
  result = @[]
  result.add((obj, obj.delVerb(verb)))
  for child in obj.children:
    result.add(child.delVerbRec(verb))

iterator vicinityVerbs(obj: MObject, name: string): tuple[o: MObject, v: MVerb] =
  var searchSpace = obj.getVicinity()

  var world = obj.getWorld()
  doAssert(world != nil)
  searchSpace.add(world.getVerbObj())

  for o in searchSpace:
    for v in matchingVerbs(o, name):
      if obj.canExecute(v):
        yield (o, v)

proc call(verb: MVerb, world: World, caller: MObject,
          symtable: SymbolTable, callback: TaskCallbackProc = nil) =
  world.addTask(verb.owner, caller, symtable, verb.compiled, callback)

proc verbCallRaw*(owner: MObject, verb: MVerb, caller: MObject,
                  args: seq[MData], callback: TaskCallbackProc = nil) =
  var
    world = caller.getWorld()
    symtable = newSymbolTable()

  doAssert(world != nil)

  symtable["caller"] = caller.md
  symtable["args"] = args.md
  symtable["self"] = owner.md
  symtable["verb"] = verb.names.md

  verb.call(world, caller, symtable, callback)

proc verbCall*(owner: MObject, name: string, caller: MObject,
               args: seq[MData], callback: TaskCallbackProc = nil): bool =

  for v in matchingVerbs(owner, name):
    if caller.canExecute(v):
      owner.verbCallRaw(v, caller, args, callback)
      return true
  return false

proc setCode*(verb: MVerb, newCode: string) =
  verb.code = newCode
  let compiler = compileCode(newCode)
  when defined(debug):
    echo verb.names
    echo compiler
  verb.compiled = compiler.render

proc preprocess(command: string): string =
  if command[0] == '(':
    return "eval " & command
  return command

proc handleCommand*(obj: MObject, command: string): MData =
  let command = preprocess(command)

  let
    parsed = parseCommand(command)
    verb = parsed.verb
    doString = parsed.doString
    ioString = parsed.ioString
    prep = parsed.prep
    rest = parsed.rest
    restStr = rest.join(" ")

    doQuery = obj.query(doString.toLower())
    ioQuery = obj.query(ioString.toLower())
    restQuery = obj.query(restStr.toLower())

  var
    world = obj.getWorld()
    symtable = world.globalSymtable

  symtable["cmd"] = command.md
  symtable["verb"] = verb.md
  symtable["caller"] = obj.md
  symtable["args"] = rest.map(proc (x: string): MData = x.md).md
  symtable["argstr"] = restStr.md

  for o, v in vicinityVerbs(obj, verb):
    symtable["self"] = o.md
    symtable["dobjstr"] = doString.md
    symtable["iobjstr"] = ioString.md
    symtable["dobj"] = nilD
    symtable["iobj"] = nilD

    if v.prepSpec != pNone and v.prepSpec != prep.ptype:
      continue

    var
      useddoQuery = doQuery
      useddoString = doString

    if v.prepSpec == pNone:
      useddoQuery = restQuery
      useddoString = restStr
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

    proc callback(task: Task, res: MData) =
      if res.isType(dErr):
        obj.send("Error while executing $1:$2 - $3" %
          [o.toObjStr(), verb, $res])

    v.call(world, obj, symtable, callback)
    return

  obj.send("Sorry, I couldn't understand that")
  return nilD

