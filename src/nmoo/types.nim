
# This file contains the types used throughout the system.
# It also contains some constructors and utility procs that are used
# everywhere.

import strutils
import sequtils
import tables
import times
import hashes
import deques
import streams
import options

from asyncnet import AsyncSocket

type
  ObjID* = distinct int
  World* = ref object
    name*: string
    persistent*: bool
    objects*: seq[MObject]
    verbObj*: MObject # object that holds global verbs
    tasks*: Table[TaskID, Task]
    taskIDCounter*: int
    taskFinishedCallback*: proc(world: World, tid: TaskID)

  InvalidWorldError* = object of ValueError

  OutputProc = proc(obj: MObject, msg: string)

  MObject* = ref object
    id*: ObjID
    world*: World
    isPlayer*: bool

    props*: seq[MProperty]
    verbs*: seq[MVerb]

    parent*: MObject
    children*: seq[MObject]

    output*: OutputProc

  MProperty* = ref object
    name*: string
    val*: MData
    owner*: MObject
    inherited*: bool

    copyVal*: bool

    pubWrite*: bool
    pubRead*: bool
    ownerIsParent*: bool

  PrepType* = enum
    pWith, pAt, pInFront, pIn, pOn, pFrom, pOver,
    pThrough, pUnder, pBehind, pBeside, pFor, pIs,
    pAs, pOff, pNone, pAny

  Preposition* = tuple[ptype: PrepType, image: string]

  ObjSpec* = enum
    oAny, oThis, oNone, oStr

  MVerb* = ref object
    names*: string
    owner*: ObjID
    inherited*: bool

    code*: string # This has to be public but don't use it, use setCode
    compiled*: CpOutput

    doSpec*: ObjSpec
    ioSpec*: ObjSpec
    prepSpec*: PrepType

    pubWrite*: bool
    pubRead*: bool
    pubExec*: bool

  MDataType* = enum
    dInt, dFloat, dStr, dSym, dErr, dList, dTable, dObj, dNil

  MData* = object
    pos*: CodePosition
    case dtype*: MDataType
      of dInt: intVal*: int
      of dFloat: floatVal*: float
      of dStr: strVal*: string
      of dSym: symVal*: string # builtin call
      of dErr:
        errVal*: MError
        errMsg*: string
        trace*: seq[tuple[name: string, pos: CodePosition]]
      of dList: listVal*: seq[MData]
      of dTable: tableVal*: Table[MData, MData]
      of dObj: objVal*: ObjID
      of dNil: nilVal*: int    # dummy

  PackageType* = enum
    ## The type of a builtin return package. See docs of `Package`
    ## type for more information.
    ptData, ## The builtin has completed and is returning data.
    ptCall, ## The builtin is calling something else and waiting for a
            ## result.
    ptInput ## The builtin is waiting for user input.

  Package* = object
    ## The actual return value of a builtin proc, which may represent a
    ## partial result of the builtin.
    case ptype*: PackageType
      of ptData:
        val*: MData
      of ptCall, ptInput:
        phase*: int

  CodePosition* = tuple[line: int, col: int]

  MError* = enum
    E_NONE,
    E_TYPE,
    E_BUILTIN,
    E_ARGS,
    E_UNBOUND,
    E_BADCOND,
    E_PERM,
    E_NACC,
    E_RECMOVE,
    E_FMOVE,
    E_PROPNF,
    E_VERBNF,
    E_BOUNDS,
    E_QUOTA,
    E_MAXREC,

    E_INTERNAL,
    E_PARSE,
    E_COMPILE,
    E_SIDECHAN

  TokenType* = enum
    tokOParen, tokCParen,
    tokAtom,
    tokQuote, tokQuasiQuote, tokUnquote,
    tokEnd

  Token* = object
    ttype*: TokenType
    image*: string
    pos*: CodePosition

  MParserOption* = enum
    poTransformDataForms ## \
    ## transform (table (a b) (c d)) into the appropriate data type
    ## instead of just leaving it as a list. This should only ever be
    ## used for data serialization.

  MLexer* = object
    stream*: Stream
    pos*: CodePosition
    error*: MData

  MParser* = ref object
    code*: string
    error*: MData
    lexer*: MLexer
    queuedTokens*: Deque[Token]
    options*: set[MParserOption]

  SymbolTable* = Table[string, MData]
  BuiltinProc* = proc(args: seq[MData], world: World,
                      self, player, caller, owner: MObject,
                      symtable: SymbolTable, pos: CodePosition, phase: int,
                      tid: TaskID): Package

  Instruction* = object
    itype*: InstructionType
    operand*: MData
    pos*: CodePosition

  InstructionType* = enum
    inPUSH, inDUP, inCALL, inACALL, inLABEL, inJ0, inJT, inJNT, inJMP, inPOP,
    inRET, inRETJ
    inLPUSH,          # strictly for labels - gets replaced by the renderer
    inGTID,           # Push the task's ID onto the stack
    inMCONT, inCCONT, # first-class continuations
    inSTO, inGET, inGGET, inGSTO, inCLIST,
    inPOPL, inPUSHL, inLEN, inSWAP, inSWAP3, inREV,
    inMENV, inGENV,
    inTRY, inETRY,
    inHALT

  SymGen* = ref object
    ## Used for generating label names
    counter*: int
    prefix*: string

  CSymTable* = Table[string, int]

  MCompilerOption* = enum
    coOptInline

  MCompiler* = ref object
    programmer*: MObject ## \
      ## The object (usually player) whose permissions any
      ## compile-time tasks will run with.

    subrs*, real*: seq[Instruction] ## \
      ## Two sections of code that grow independently.
      ## All code generated from functions (or lambdas) are appended
      ## to `subrs`. All other code generated from the toplevel goes
      ## in `real`. At the end of compilation, these two sections are
      ## concatenated.

    options*: set[MCompilerOption]

    symtable*: CSymTable ## \
      ## A mapping from symbol name to position in the runtime's
      ## symbol table.

    extraLocals*: seq[SymbolTable] ## \
      ## A stack of extra locals defined.
      ##
      ## Warning: This is extremely janky.  Push (`add`) to the stack
      ## when entering a new scope and add names to it. These will be
      ## cleaned up when exiting the scope.
      ##
      ## NB: This is (at least IMO) needed to implement `define`. I
      ## can't think of any other way that doesn't involve rewriting
      ## the whole compiler.

    symgen*: SymGen ## Symbol name generator.

    depth*: int ## Compile-time call stack depth.

    syntaxTransformers*: TableRef[string, SyntaxTransformer] ## \
      ## Map of macro name to macro function.
      ##
      ## Macro functions are extremely simple; they take code as input
      ## (any value, usually a list) and returns any code as an
      ## output.

  SyntaxTransformer* = ref object
    code*: MData

  SpecialProc* = proc(compiler: MCompiler, args: seq[MData],
      pos: CodePosition): MData

  MCompileError* = object of ValueError

  VSymTable* = TableRef[int, MData]
  Frame* = ref object
    symtableIndex*: uint
    calledFrom*: int
    tries*: seq[int]

  TaskType* = enum
    ttFunction, ttInput

  TaskStatus* = enum
    tsRunning, tsAwaitingInput, tsAwaitingResult,
    tsReceivedInput, tsSuspended, tsDone

  # First class continuations
  Continuation* = object
    pc*: int
    stack*: seq[MData]
    globals*: SymbolTable
    frames*: seq[Frame]

  TaskID* = distinct int
  Task* = ref object
    id*: TaskID
    name*: string
    startTime*: Time

    stack*: seq[MData]
    when defined(depthStack):
      depthStack*: seq[int]

    symtables*: seq[VSymTable]        ## All of the symbol tables
    globals*: SymbolTable             ## Same type as used by parser
    code*: seq[Instruction]
    pc*: int                          ## Program counter

    frames*: seq[Frame]
    continuations*: seq[Continuation] ## For continuations

    world*: World
    self*: MObject
    player*: MObject
    caller*: MObject
    owner*: MObject

    status*: TaskStatus
    suspendedUntil*: Time
    tickCount*: int
    tickQuota*: int

    hasCallPackage*: bool
    callPackage*: Package
    builtinToCall*: MData
    builtinArgs*: seq[MData]

    taskType*: TaskType
    callback*: Option[TaskID]
    waitingFor*: Option[TaskID]

  TaskResultType* = enum trFinish, trSuspend, trError, trTooLong
  TaskResult* = object
    case typ*: TaskResultType
      of trFinish: res*: MData
      of trSuspend: discard
      of trError: err*: MData
      of trTooLong: discard

  InstructionProc* = proc(world: World, tid: TaskID, operand: MData)
  CpOutput* = tuple[entry: int, code: seq[Instruction], error: MData]

  Client* = ref object
    world*: World
    player*: MObject
    address*: string
    sock*: AsyncSocket
    outputQueue*: seq[string]
    inputQueue*: seq[string]
    tasksWaitingForInput*: seq[TaskID]
    currentInputTask*: Option[TaskID]

let nilD* = MData(dtype: dNil, nilVal: 1)

# forward declarations
proc `$`*(x: MData): string {.inline, procvar.}
proc hash*(x: MData): Hash
proc `==`*(x: MData, y: MData): bool

proc id*(x: int): ObjID = ObjID(x)
proc getID*(obj: MObject): ObjID = obj.id
proc setID*(obj: MObject, newID: ObjID) = obj.id = newID
proc getWorld*(obj: MObject): World = obj.world
proc setWorld*(obj: MObject, newWorld: World) = obj.world = newWorld

proc md*(x: int): MData {.procvar.} = MData(dtype: dInt, intVal: x)
proc md*(x: float): MData {.procvar.} = MData(dtype: dFloat, floatVal: x)
proc md*(x: string): MData {.procvar.} = MData(dtype: dStr, strVal: x)
proc mds*(x: string): MData {.procvar.} = MData(dtype: dSym, symVal: x)
proc md*(x: MError): MData {.procvar.} = MData(dtype: dErr, errVal: x,
    errMsg: "no message set", trace: @[])
proc md*(x: MError, s: string): MData {.procvar.} = MData(dtype: dErr,
    errVal: x, errMsg: s, trace: @[])
proc md*(x: seq[MData]): MData {.procvar.} = MData(dtype: dList, listVal: x)
proc md*(x: ObjID): MData {.procvar.} = MData(dtype: dObj, objVal: x)
proc md*(x: MObject): MData {.procvar.} = x.id.md
proc md*(x: Table[MData, MData]): MData {.procvar.} = MData(dtype: dTable, tableVal: x)
proc md*(x: openArray[(MData, MData)]): MData {.procvar.} =
  var tableVal = toTable(x)
  MData(dtype: dTable, tableVal: tableVal)

proc pack*(x: MData): Package = Package(ptype: ptData, val: x)
proc pack*(phase: int): Package = Package(ptype: ptCall, phase: phase)
proc inputPack*(phase: int): Package = Package(ptype: ptInput, phase: phase)

proc isType*(datum: MData, dtype: MDataType): bool {.inline.} =
  return datum.dtype == dtype


proc `$M`(m: Table[MData, MData]): string =
  result &= "(table"
  for k, v in pairs(m):
    result &= " ($# $#)".format(k, v)
  result &= ")"

proc `$`*(x: ObjID): string {.borrow.}
proc `==`*(x: ObjID, y: ObjID): bool {.borrow.}
proc `$`*(x: MData): string {.inline, procvar.} =
  case x.dtype:
    of dInt: $x.intVal
    of dFloat: $x.floatVal
    of dStr: x.strVal.escape
    of dSym: x.symVal
    of dErr: $x.errVal & ": " & x.errMsg & "\n" & x.trace.mapIt($it.pos & "  " &
        it.name).join("\n")
    of dList:
      "(" & x.listVal.mapIt($it).join(" ") & ")"
    of dTable: `$M`(x.tableVal)
    of dObj: "#" & $x.objVal
    of dNil: "nil"

proc hash(m: Table[MData, MData]): Hash =
  var h = 0.hash
  for k, v in pairs(m):
    h = h !& k.hash
    h = h !& v.hash

  return !$h

proc hash*(x: MData): Hash =
  var h = ord(x.dtype).hash
  case x.dtype:
    of dInt: h = h !& x.intVal
    of dFloat: h = h !& x.floatVal.hash
    of dStr: h = h !& x.strVal.hash
    of dSym: h = h !& x.symVal.hash
    of dErr: h = h !& x.errVal.hash
    # TODO: cache these (map and list)
    of dList: h = h !& x.listVal.hash
    of dTable: h = h !& x.tableVal.hash
    of dObj: h = h !& x.objVal.int
    of dNil: h = h !& 0

  return !$h

proc `==`*(x: MData, y: MData): bool =
  if x.dtype == y.dtype:
    case x.dtype:
      of dInt: return x.intVal == y.intVal
      of dFloat: return x.floatVal == y.floatVal
      of dStr: return x.strVal == y.strVal
      of dSym: return x.symVal == y.symVal
      of dErr: return x.errVal == y.errVal
      of dList: return x.listVal == y.listVal
      of dTable: return x.tableVal == y.tableVal
      of dObj: return x.objVal == y.objVal
      of dNil: return true
  else:
    return false

proc truthy*(datum: MData): bool =
  return not datum.isType(dNil) and
         not (datum.isType(dInt) and datum.intVal == 0 or
              datum.isType(dFloat) and datum.floatVal == 0)

proc byID*(world: World, id: ObjID): Option[MObject] =
  let idint = id.int
  if idint >= world.objects.len:
    return none[MObject]()
  else:
    return option(world.objects[id.int])

proc newSymbolTable*: SymbolTable = initTable[string, MData]()
proc toData*(st: SymbolTable): MData =
  var pairs: seq[MData] = @[]
  for key, val in st:
    pairs.add(@[key.md, val].md)
  return pairs.md

proc toST*(data: MData): SymbolTable =
  result = newSymbolTable()
  if not data.isType(dList):
    return

  let list = data.listVal
  for pair in list:
    if not pair.isType(dList): continue

    let pairdata = pair.listVal
    let keyd = pairdata[0]
    let val = pairdata[1]
    if not keyd.isType(dStr): continue
    let key = keyd.strVal
    result[key] = val

proc dataToObj*(world: World, objd: MData): Option[MObject] =
  world.byID(objd.objVal)

proc objSpecToStr*(osp: ObjSpec): string =
  ($osp).toLowerAscii[1 .. ^1]

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

proc strToObjSpec*(osps: string): Option[ObjSpec] =
  let realSpec = "o" & osps[0].toUpperAscii & osps[1 .. ^1]
  try:
    return some(parseEnum[ObjSpec](realSpec))
  except:
    return none[ObjSpec]()

proc prepSpecToStr*(psp: PrepType): string =
  var images: seq[string] = @[]
  for prep in Prepositions:
    let (ptype, image) = prep
    if ptype == psp:
      images.add(image)

  return images.join("/")

proc strToPrepSpec*(psps: string): Option[PrepType] =
  let pspsLower = psps.toLowerAscii()

  for prep in Prepositions:
    let (ptype, image) = prep
    if image == pspsLower:
      return some(ptype)

  return none[PrepType]()

proc send*(obj: MObject, msg: string) =
  obj.output(obj, msg)

proc newProperty*(
  name: string,
  val: MData,
  owner: MObject,
  inherited: bool = false,
  copyVal: bool = false,

  pubRead: bool = true,
  pubWrite: bool = false,
  ownerIsParent: bool = true
): MProperty =
  MProperty(
    name: name,
    val: val,
    owner: owner,
    inherited: inherited,
    copyVal: copyVal,

    pubRead: pubRead,
    pubWrite: pubWrite,
    ownerIsParent: ownerIsParent
  )

proc newVerb*(
  names: string,
  owner: ObjID,
  inherited: bool = false,

  code: string = "",
  compiled: CpOutput = (0, @[], E_NONE.md),

  doSpec: ObjSpec = oNone,
  ioSpec: ObjSpec = oNone,
  prepSpec: PrepType = pNone,

  pubWrite: bool = false,
  pubRead: bool = true,
  pubExec: bool = true
): MVerb =
  MVerb(
    names: names,
    owner: owner,
    inherited: inherited,

    code: code,
    compiled: compiled,

    doSpec: doSpec,
    ioSpec: ioSpec,
    prepSpec: prepSpec,

    pubWrite: pubWrite,
    pubRead: pubRead,
    pubExec: pubExec
  )

proc copy*(prop: MProperty): MProperty =
  MProperty(
    name: prop.name,
    val: prop.val,
    owner: prop.owner,
    inherited: prop.inherited,

    copyVal: prop.copyVal,

    pubRead: prop.pubRead,
    pubWrite: prop.pubWrite,
    ownerIsParent: prop.ownerIsParent
  )

proc copy*(verb: MVerb): MVerb =
  MVerb(
    names: verb.names,
    owner: verb.owner,
    inherited: verb.inherited,
    code: verb.code,
    compiled: verb.compiled,

    doSpec: verb.doSpec,
    ioSpec: verb.ioSpec,
    prepSpec: verb.prepSpec,

    pubRead: verb.pubRead,
    pubWrite: verb.pubWrite,
    pubExec: verb.pubExec
  )

proc equiv*(v1, v2: MVerb): bool =
  (v1.names == v2.names) and (v1.doSpec == v2.doSpec) and (v1.ioSpec ==
      v2.ioSpec) and(v1.prepSpec == v2.prepSpec)

proc newWorld*: World =
  World(objects: @[],
         verbObj: nil,
         tasks: initTable[TaskID, Task](),
         taskIDCounter: 0,
         taskFinishedCallback: proc(world: World, tid: TaskID) = discard)

proc getObjects*(world: World): ptr seq[MObject] =
  addr world.objects

proc getVerbObj*(world: World): MObject =
  world.verbObj

proc `$`*(t: TaskID): string {.borrow.}
proc `==`*(t1, t2: TaskID): bool {.borrow.}

proc getTaskByID*(world: World, id: TaskID): Option[Task] =
  if id in world.tasks:
    return some(world.tasks[id])

  return none(Task)
