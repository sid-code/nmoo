# this file is for everything from command parsing to command handling
# not just verbs

import sequtils
import strutils
import tables
import pegs

import types
import objects
import querying
import scripting
import compile

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

    (pNone, "none"),
    (pAny, "any")
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

proc parseCommand*(str: string): ParsedCommand =
  result.prep = (pNone, "none")

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

    var (success, ptype) = strToPrepSpec(word)
    if success and ptype in {pNone, pAny}:
      success = false

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
  if str == verb.names:
    return true

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

iterator matchingVerbs(obj: MObject, name: string, all = true): MVerb =
  let searchSpace = if all: obj.allVerbs() else: obj.verbs
  for v in searchSpace:
    if v.matchesName(name):
      yield v

proc getVerb*(obj: MObject, name: string, all = true): MVerb =
  for v in matchingVerbs(obj, name, all):
    return v

  return nil

proc getVerb*(obj: MObject, index: int): MVerb =
  if index in 0..obj.verbs.len-1:
    obj.verbs[index]
  else:
    nil

# Code duplication, I know, but I'm lazy
proc getVerbAndObj*(obj: MObject, name: string, all = true): tuple[o: MObject, v: MVerb] =
  for v in obj.verbs:
    if v.matchesName(name):
      return (obj, v)

  if all:
    let parent = obj.parent
    if not isNil(parent) and parent != obj:
      return parent.getVerbAndObj(name, all)

  return (nil, nil)

proc addVerb*(obj: MObject, verb: MVerb): MVerb =
  obj.verbs.add(verb)
  return verb

proc delVerb*(obj: MObject, verb: MVerb): MVerb =
  for i, v in obj.verbs:
    if v == verb:
      obj.verbs.delete(i)
      return verb

  return nil

iterator vicinityVerbs(obj: MObject, name: string): tuple[o: MObject, v: MVerb] =
  var searchSpace = obj.getVicinity()

  var world = obj.getWorld()
  doAssert(not isNil(world))
  searchSpace.add(world.getVerbObj())

  for o in searchSpace:
    for v in matchingVerbs(o, name):
      if obj.canExecute(v):
        yield (o, v)

proc call(verb: MVerb, world: World, holder, caller: MObject,
          symtable: SymbolTable, taskType = ttFunction, callback = -1): Task =
  if not isNil(verb.compiled.code):
    let name = "$#:$#" % [holder.toObjStr(), verb.names]
    return world.addTask(name, verb.owner, caller, symtable, verb.compiled, taskType, callback)
  else:
    return nil

proc verbCallRaw*(self: MObject, verb: MVerb, caller: MObject,
                  args: seq[MData], symtable: SymbolTable = newSymbolTable(),
                  holder: MObject = nil, taskType = ttFunction, callback = -1): Task =
  var
    world = caller.getWorld()
    symtable = symtable

  var holder = if isNil(holder): self else: holder

  doAssert(not isNil(world))

  symtable["caller"] = caller.md
  symtable["args"] = args.md
  symtable["self"] = self.md
  symtable["holder"] = holder.md
  symtable["verb"] = verb.names.md

  return verb.call(world, holder, caller, symtable, taskType, callback)

proc verbCall*(owner: MObject, name: string, caller: MObject,
               args: seq[MData], symtable = newSymbolTable(),
               taskType = ttFunction, callback = -1): Task =

  for v in matchingVerbs(owner, name):
    if caller.canExecute(v):
      return owner.verbCallRaw(v, caller, args, symtable = symtable, taskType = taskType, callback = callback)
  return nil

proc setCode*(verb: MVerb, newCode: string) =
  verb.code = newCode
  let compiled = compileCode(newCode)
  verb.compiled = compiled

proc preprocess(command: string): string =
  if command[0] == '(':
    return "eval " & command
  return command

proc handleCommand*(player: MObject, command: string): Task =
  let command = preprocess(command.strip())
  if command.len == 0: return nil

  let originalCommand = command

  let
    parsed = parseCommand(command)
    verb = parsed.verb
    doString = parsed.doString
    ioString = parsed.ioString
    prep = parsed.prep
    rest = parsed.rest
    restStr = rest.join(" ")
    frest = parsed.fixedRest

    doQuery = player.query(doString.toLower())
    ioQuery = player.query(ioString.toLower())

    doQuerySuccess = doString.len > 0 and doQuery.len > 0
    ioQuerySuccess = ioString.len > 0 and ioQuery.len > 0

    dobject = if doQuerySuccess: doQuery[0] else: nil
    iobject = if ioQuerySuccess: ioQuery[0] else: nil

  var
    world = player.getWorld()
    symtable = newSymbolTable()

  symtable["cmd"] = command.md
  symtable["verb"] = verb.md
  symtable["caller"] = player.md
  symtable["args"] = frest.map(proc (x: string): MData = x.md).md
  symtable["argstr"] = restStr.md

  var objectVerbPairs: seq[tuple[o: MObject, v: MVerb]] = @[]
  proc considerObject(o: MObject) =
    for v in o.allVerbs():
      objectVerbPairs.add((o, v))

  considerObject(player)

  if doQuerySuccess:
    considerObject(dobject)
  if ioQuerySuccess:
    considerObject(iobject)

  let loc = player.getLocation()
  if not isNil(loc):
    considerObject(loc)

  for o, v in objectVerbPairs.items:
    if not v.matchesName(verb):
      continue

    symtable["self"] = o.md

    if v.prepSpec == pNone:
      symtable["dobjstr"] = symtable["argstr"]
    else:
      symtable["dobjstr"] = doString.md

    symtable["iobjstr"] = ioString.md
    symtable["dobj"] = nilD
    symtable["iobj"] = nilD

    if v.prepSpec != pAny and v.prepSpec != prep.ptype:
      continue

    case v.doSpec:
      of oAny:
        if doQuerySuccess:
          if o != player and o != loc:
            continue
          symtable["dobj"] = dobject.md
      of oThis:
        if doQuerySuccess and dobject == o: symtable["dobj"] = o.md else: continue
      of oStr:
        if doString.len == 0: continue
      of oNone:
        if doString.len > 0: continue
    case v.ioSpec:
      of oAny:
        if ioQuerySuccess:
          if o != player and o != loc:
            continue
          symtable["iobj"] = iobject.md
      of oThis:
        if ioQuerySuccess and iobject == o: symtable["iobj"] = o.md else: continue
      of oStr:
        if ioString.len == 0: continue
      of oNone:
        if ioString.len > 0: continue

    symtable["holder"] = o.md
    return v.call(world, holder = o, caller = player, symtable = symtable, taskType = ttInput)

  let locationd = player.getPropVal("location")
  if not locationd.isType(dObj):
    return nil

  let location = world.dataToObj(locationd)
  if isNil(location.verbCall("huh", player, @[originalCommand.md], taskType = ttInput)):
    player.send("Huh?")

  return nil

# Return MObject because the goal of these commands is to determine the
# player the connection owns.
proc handleLoginCommand*(player: MObject, command: string): MObject =
  let command = command.strip()
  if command.len == 0: return nil

  let
    parsed = parseCommand(command)
    commandName = parsed.verb
    rest = parsed.rest
    restStr = rest.join(" ")
    frest = parsed.fixedRest

  var
    world = player.getWorld()
    symtable = newSymbolTable()

  let verbObj = world.verbObj

  let args = frest.map(md)

  symtable["command"] = commandName.md
  symtable["args"] = args.md
  symtable["argstr"] = restStr.md
  symtable["caller"] = player.md
  symtable["self"] = verbObj.md

  let lcTask = verbObj.verbCall("handle-login-command", player, args,
                                symtable = symtable, taskType = ttInput)

  if isNil(lcTask):
    player.send("Failed to run your login command; server is set up incorrectly.")
    return nil

  let tr = lcTask.run
  case tr.typ:
    of trFinish:
      if tr.res.isType(dObj):
        return world.dataToObj(tr.res)
      else:
        return nil
    of trSuspend:
      verbObj.send("The task for #0:handle-new-connection got suspended!")
    of trError:
      verbObj.send("The task for #0:handle-new-connection had an error.")
    of trTooLong:
      verbObj.send("The task for #0:handle-new-connection ran for too long!")

  player.send("Failed to run your login command; server is set up incorrectly.")
  return nil



