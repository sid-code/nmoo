
# This file contains the types used throughout the system.
# It also contains some constructors and utility procs that are used
# everywhere.

import strutils
import tables
import times
import hashes

from asyncnet import AsyncSocket

type

  ObjID* = distinct int
  World* = ref object
    name*: string
    persistent*: bool
    objects: seq[MObject]
    verbObj*: MObject # object that holds global verbs
    tasks*: seq[Task]
    taskIDCounter*: int

  InvalidWorldError* = object of Exception

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

  ObjSpec* = enum
    oAny, oThis, oNone, oStr

  MVerb* = ref object
    names*: string
    owner*: MObject
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
    dInt, dFloat, dStr, dSym, dErr, dList, dObj, dNil

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
      of dList: listVal*: seq[MData]
      of dObj: objVal*: ObjID
      of dNil: nilVal*: int # dummy

  PackageType* = enum
    ptData, ptCall, ptInput

  Package* = object
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

    E_INTERNAL,
    E_PARSE,
    E_COMPILE

  TokenType* = enum
    tokOParen, tokCParen,
    tokAtom,
    tokQuote, tokQuasiQuote, tokUnquote,
    tokEnd

  Token* = object
    ttype*: TokenType
    image*: string
    pos*: CodePosition

  MParseError* = object of Exception

  MParser* = ref object
    code*: string
    tokens*: seq[Token]
    tindex*: int

  SymbolTable* = Table[string, MData]
  BuiltinProc* = proc(args: seq[MData], world: World,
                      self, player, caller, owner: MObject,
                      symtable: SymbolTable, pos: CodePosition, phase: int,
                      task: Task): Package

  Instruction* = object
    itype*: InstructionType
    operand*: MData
    pos*: CodePosition

  InstructionType* = enum
    inPUSH, inDUP, inCALL, inACALL, inLABEL, inJ0, inJT, inJNT, inJMP, inPOP,
    inRET, inRETJ
    inLPUSH, # strictly for labels - gets replaced by the renderer
    inGTID, # Push the task's ID onto the stack
    inMCONT, inCCONT, # first-class continuations
    inSTO, inGET, inGGET, inCLIST,
    inPOPL, inPUSHL, inLEN, inSWAP, inSWAP3, inREV,
    inMENV, inGENV,
    inTRY, inETRY
    inHALT

  SymGen* = ref object
    ## Used for generating label names
    counter*: int
    prefix*: string

  CSymTable* = Table[string, int]

  MCompiler* = ref object
    subrs*, real*: seq[Instruction]
    symtable*: CSymTable
    symgen*: SymGen

  SpecialProc* = proc(compiler: MCompiler, args: seq[MData], pos: CodePosition)

  MCompileError* = object of Exception

  VSymTable* = Table[int, MData]
  Frame* = ref object
    symtable*:   VSymTable
    calledFrom*: int
    tries*:      seq[int]

  TaskType* = enum
    ttFunction, ttInput

  TaskStatus* = enum
    tsRunning, tsAwaitingInput, tsAwaitingResult,
    tsReceivedInput, tsSuspended, tsDone

  # First class continuations
  Continuation* = object
    pc*:      int
    stack*:   seq[MData]
    globals*: SymbolTable
    frames*:  seq[Frame]

  Task* = ref object
    id*: int
    name*: string
    startTime*: Time

    stack*:     seq[MData]
    symtables*: seq[VSymTable]     ## All of the symbol tables
    globals*:   SymbolTable        ## Same type as used by parser
    code*:      seq[Instruction]
    pc*:        int                ## Program counter

    frames*:    seq[Frame]
    continuations*: seq[Continuation]  ## For continuations

    world*:     World
    self*:      MObject
    player*:    MObject
    caller*:    MObject
    owner*:     MObject

    status*: TaskStatus
    suspendedUntil*: Time
    tickCount*: int
    tickQuota*: int

    hasCallPackage*: bool
    callPackage*: Package
    builtinToCall*: MData
    builtinArgs*: seq[MData]

    taskType*: TaskType
    callback*: int
    waitingFor*: int

  TaskResultType* = enum trFinish, trSuspend, trError, trTooLong
  TaskResult* = object
    case typ*: TaskResultType
      of trFinish: res*: MData
      of trSuspend: discard
      of trError: err*: MData
      of trTooLong: discard

  InstructionProc* = proc(task: Task, operand: MData)
  CpOutput* = tuple[entry: int, code: seq[Instruction]]

  Client* = ref object
    world*: World
    player*: MObject
    sock*: AsyncSocket
    outputQueue*: seq[string]
    inputQueue*: seq[string]
    tasksWaitingForInput*: seq[Task]
    currentInputTask*: Task

let nilD* = MData(dtype: dNil, nilVal: 1)

proc id*(x: int): ObjID = ObjID(x)
proc getID*(obj: MObject): ObjID = obj.id
proc setID*(obj: MObject, newID: ObjID) = obj.id = newID
proc getWorld*(obj: MObject): World = obj.world
proc setWorld*(obj: MObject, newWorld: World) = obj.world = newWorld

proc md*(x: int): MData {.procvar.} = MData(dtype: dInt, intVal: x)
proc md*(x: float): MData {.procvar.} = MData(dtype: dFloat, floatVal: x)
proc md*(x: string): MData {.procvar.} = MData(dtype: dStr, strVal: x)
proc mds*(x: string): MData {.procvar.} = MData(dtype: dSym, symVal: x)
proc md*(x: MError): MData {.procvar.} = MData(dtype: dErr, errVal: x, errMsg: "no message set")
proc md*(x: MError, s: string): MData {.procvar.} = MData(dtype: dErr, errVal: x, errMsg: s)
proc md*(x: seq[MData]): MData {.procvar.} = MData(dtype: dList, listVal: x)
proc md*(x: ObjID): MData {.procvar.} = MData(dtype: dObj, objVal: x)
proc md*(x: MObject): MData {.procvar.} = x.id.md

proc pack*(x: MData): Package = Package(ptype: ptData, val: x)
proc pack*(phase: int): Package = Package(ptype: ptCall, phase: phase)
proc inputPack*(phase: int): Package = Package(ptype: ptInput, phase: phase)

proc `$`*(x: ObjID): string {.borrow.}
proc `==`*(x: ObjID, y: ObjID): bool {.borrow.}
proc `$`*(x: MData): string {.inline.} =
  case x.dtype:
    of dInt: $x.intVal
    of dFloat: $x.floatVal
    of dStr: x.strVal.escape
    of dSym: "\'" & x.symVal
    of dErr: $x.errVal & ": " & x.errMsg
    of dList: $x.listVal
    of dObj: "#" & $x.objVal
    of dNil: "nil"

proc `==`*(x: MData, y: MData): bool =
  if x.dtype == y.dtype:
    case x.dtype:
      of dInt: return x.intVal == y.intVal
      of dFloat: return x.floatVal == y.floatVal
      of dStr: return x.strVal == y.strVal
      of dSym: return x.symVal == y.symVal
      of dErr: return x.errVal == y.errVal
      of dList:
        let
          xl = x.listVal
          yl = y.listVal
        if xl.len != yl.len:
          return false
        else:
          for idx, el in xl:
            if yl[idx] != el:
              return false
          return true
      of dObj: return x.objVal == y.objVal
      of dNil: return true
  else:
    return false

proc hash*(x: MData): Hash =
  var h = ord(x.dtype).hash
  h = h !& case x.dtype:
    of dInt: x.intVal.hash
    of dFloat: x.floatVal.hash
    of dStr: x.strVal.hash
    of dSym: x.symVal.hash
    of dErr: x.errVal.hash
    of dList: x.listVal.hash
    of dObj: x.objVal.int.hash
    of dNil: 0.hash

  return !$h

proc isType*(datum: MData, dtype: MDataType): bool {.inline.}=
  return datum.dtype == dtype

proc truthy*(datum: MData): bool =
  return not datum.isType(dNil) and
         not (datum.isType(dInt) and datum.intVal == 0 or
              datum.isType(dFloat) and datum.floatVal == 0)

proc byID*(world: World, id: ObjID): MObject =
  let idint = id.int
  if idint >= world.objects.len:
    return nil
  else:
    return world.objects[id.int]

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

proc dataToObj*(world: World, objd: MData): MObject =
  world.byID(objd.objVal)

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
  owner: MObject,
  inherited: bool = false,

  code: string = "",
  compiled: CpOutput = (0, nil),

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

proc newWorld*: World =
  World( objects: @[], verbObj: nil, tasks: @[], taskIDCounter: 0 )

proc getObjects*(world: World): ptr seq[MObject] =
  addr world.objects

proc getVerbObj*(world: World): MObject =
  world.verbObj
