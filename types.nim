import strutils, tables

type

  ObjID* = distinct int
  World* = ref object
    objects: seq[MObject]
    verbObj*: MObject # object that holds global verbs

  OutputProc = proc(obj: MObject, msg: string)

  MObject* = ref object
    id: ObjID
    world: World
    isPlayer*: bool
    owner*: MObject

    props*: seq[MProperty]
    verbs*: seq[MVerb]

    parent*: MObject
    children*: seq[MObject]

    level*: int

    pubWrite*: bool
    pubRead*: bool
    fertile*: bool

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
    pAs, pOff, pNone

  ObjSpec* = enum
    oAny, oThis, oNone, oStr

  MVerb* = ref object
    names*: string
    owner*: MObject
    inherited*: bool

    code*: string # This has to be public but don't use it, use setCode
    parsed*: MData

    doSpec*: ObjSpec
    ioSpec*: ObjSpec
    prepSpec*: PrepType

    pubWrite*: bool
    pubRead*: bool
    pubExec*: bool

  MDataType* = enum
    dInt, dFloat, dStr, dSym, dErr, dList, dObj, dNil

  MData* = object
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

    E_PARSE

  SymbolTable* = Table[string, MData]
  BuiltinProc* = proc(args: var seq[MData], world: var World,
                      caller, owner: MObject, symtable: SymbolTable): MData

proc initSymbolTable*: SymbolTable = initTable[string, MData]()

let nilD* = MData(dtype: dNil, nilVal: 1)

proc id*(x: int): ObjID = ObjID(x)
proc getID*(obj: MObject): ObjID = obj.id
proc setID*(obj: MObject, newID: ObjID) = obj.id = newID
proc getWorld*(obj: MObject): World = obj.world
proc setWorld*(obj: MObject, newWorld: World) = obj.world = newWorld

proc md*(x: int): MData = MData(dtype: dInt, intVal: x)
proc md*(x: float): MData = MData(dtype: dFloat, floatVal: x)
proc md*(x: string): MData = MData(dtype: dStr, strVal: x)
proc mds*(x: string): MData = MData(dtype: dSym, symVal: x)
proc md*(x: MError): MData = MData(dtype: dErr, errVal: x, errMsg: "no message set")
proc md*(x: MError, s: string): MData = MData(dtype: dErr, errVal: x, errMsg: s)
proc md*(x: seq[MData]): MData = MData(dtype: dList, listVal: x)
proc md*(x: ObjID): MData = MData(dtype: dObj, objVal: x)
proc md*(x: MObject): MData = x.id.md

proc blank*(dt: MDataType): MData =
  case dt:
    of dInt: 0.md
    of dFloat: 0.0'f64.md
    of dStr: "".md
    of dSym: "".mds
    of dErr: E_NONE.md
    of dList: @[].md
    of dObj: 0.ObjID.md
    of dNil: nilD


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

proc isType*(datum: MData, dtype: MDataType): bool {.inline.}=
  return datum.dtype == dtype

proc toEchoString*(x: MData): string =
  if x.isType(dStr):
    x.strVal
  else:
    $x

proc truthy*(datum: MData): bool =
  return not (datum.isType(dInt) and datum.intVal == 0 or datum.isType(dFloat) and datum.floatVal == 0)

proc byID*(world: World, id: ObjID): MObject =
  let idint = id.int
  if idint > world.objects.len:
    return nil
  else:
    return world.objects[id.int]

proc dataToObj*(world: World, objd: MData): MObject =
  world.byID(objd.objVal)

proc defaultOutput(obj: MObject, m: string) =
  echo "sent to #$1: $2" % [$obj.getID(), m]


proc blankObject*: MObject =
  result = MObject(
    id: 0.id,
    world: nil,
    isPlayer: false,
    props: @[],
    verbs: @[],
    owner: nil,
    parent: nil,
    children: @[],
    pubRead: true,
    pubWrite: false,
    fertile: true,
    output: defaultOutput
  )

proc send*(obj: MObject, msg: string) =
  obj.output(obj, msg)


proc newProperty*(
  name: string,
  val: MData,
  owner: MObject,
  inherited: bool,
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
  parsed: MData = nilD,

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
    parsed: nilD,

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
    parsed: verb.parsed,

    doSpec: verb.doSpec,
    ioSpec: verb.ioSpec,
    prepSpec: verb.prepSpec,

    pubRead: verb.pubRead,
    pubWrite: verb.pubWrite,
    pubExec: verb.pubExec
  )

proc newWorld*: World =
  World( objects: @[], verbObj: nil )

proc getObjects*(world: World): ptr seq[MObject] =
  addr world.objects

proc getVerbObj*(world: World): MObject =
  world.verbObj
