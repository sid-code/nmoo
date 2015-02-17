import sequtils

type
  World* = ref object
    objects: seq[MObject]

  MObject* = ref object
    id: ObjID
    world: World
    is_player: bool

    props: seq[MProperty]
    verbs: seq[MVerb]

    parent: MObject
    children: seq[MObject]

    pub_write: bool
    pub_read: bool
    fertile: bool

  MProperty* = ref object
    name: string
    val: MData
    owner: MObject
    inherited: bool

    pub_write: bool
    pub_read: bool
    owner_is_parent: bool

  MVerb* = ref object # stub
    names: string
    owner: MObject
    inherited: bool

    code: string

  MDataType* = enum
    dInt, dFloat, dStr, dErr, dList, dObj, dNil

  MData* = object
    case dtype*: MDataType
      of dInt: intVal*: int
      of dFloat: floatVal*: float
      of dStr: strVal*: string
      of dErr: errVal*: MError
      of dList: listVal*: seq[MData]
      of dObj: objVal*: ObjID
      of dNil: nilVal*: int # dummy

  MError* = enum
    E_WHOOPS

  ObjID* = distinct int


proc id*(x: int): ObjID = ObjID(x)
proc getID*(obj: MObject): ObjID = obj.id

proc md*(x: int): MData = MData(dtype: dInt, intVal: x)
proc md*(x: float): MData = MData(dtype: dFloat, floatVal: x)
proc md*(x: string): MData = MData(dtype: dStr, strVal: x)
proc md*(x: MError): MData = MData(dtype: dErr, errVal: x)
proc md*(x: seq[MData]): MData = MData(dtype: dList, listVal: x)
proc md*(x: ObjID): MData = MData(dtype: dObj, objVal: x)
proc md*(x: MObject): MData = x.id.md
let nilD* = MData(dtype: dNil, nilVal: 1)

proc `$`*(x: ObjID): string {.borrow.}
proc `==`*(x: ObjID, y: ObjID): bool {.borrow.}
proc `$`*(x: MData): string {.inline.} =
  case x.dtype:
    of dInt: $x.intVal
    of dFloat: $x.floatVal & "f"
    of dStr: "\"" & $x.strVal & "\""
    of dErr: "some error"
    of dList: $x.listVal
    of dObj: "#" & $x.objVal
    of dNil: "nil"

proc isType*(datum: MData, dtype: MDataType): bool {.inline.}=
  return datum.dtype == dtype

proc byID*(world: World, id: ObjID): MObject =
  world.objects[id.int]

proc copy(prop: MProperty): MProperty =
  MProperty(
    name: prop.name,
    val: prop.val,
    owner: prop.owner,
    inherited: prop.inherited,

    pub_read: prop.pub_read,
    pub_write: prop.pub_write,
    owner_is_parent: prop.owner_is_parent
  )

proc copy(verb: MVerb): MVerb =
  MVerb(
    names: verb.names,
    owner: verb.owner,
    inherited: verb.inherited,
    code: verb.code
  )

proc blankObject*: MObject =
  MObject(
    id: 0.id,
    world: nil,
    is_player: false,
    props: @[],
    verbs: @[],
    parent: nil,
    children: @[],
    pub_read: true,
    pub_write: false,
    fertile: true
  )

proc world*(obj: MObject): World = obj.world

proc getProp*(obj: MObject, name: string): MProperty =
  for p in obj.props:
    if p.name == name:
      return p

  return nil

proc getPropVal*(obj: MObject, name: string): MData =
  var result = obj.getProp(name)
  if result == nil:
    nilD
  else:
    result.val

proc setProp*(obj: MObject, name: string, newVal: MData) =
  var p = obj.getProp(name)
  if p == nil:
    obj.props.add(MProperty(
      name: name,
      val: newVal,
      owner: obj,
      inherited: false,
      pub_read: true,
      pub_write: false,
      owner_is_parent: true
    ))
  else:
    p.val = newVal

template setPropR*(obj: MObject, name: string, newVal: expr) =
  obj.setProp(name, newVal.md)

proc getLocation*(obj: MObject): MObject =
  let world = obj.world
  if world == nil: return nil

  let loc = obj.getPropVal("location")

  if loc.isType(dObj):
    return world.byID(loc.objVal)
  else:
    return nil

proc getRawContents(obj: MObject): tuple[hasContents: bool, contents: seq[MData]] =

  let contents = obj.getPropVal("contents")

  if contents.isType(dList):
    return (true, contents.listVal)
  else:
    return (false, @[])


proc getContents*(obj: MObject): tuple[hasContents: bool, contents: seq[MObject]] =
  let world = obj.world
  if world == nil: return (false, @[])

  var result: seq[MObject] = @[]

  var (has, contents) = obj.getRawContents();

  if has:
    for o in contents:
      if o.isType(dObj):
        result.add(world.byID(o.objVal))

    return (true, result)
  else:
    return (false, @[])
  


proc addToContents*(obj: MObject, newMember: var MObject): bool =
  var (has, contents) = obj.getRawContents();
  if has:
    contents.add(newMember.md)
    obj.setPropR("contents", contents)
    return true
  else:
    return false

proc removeFromContents(obj: MObject, member: var MObject): bool =
  var (has, contents) = obj.getRawContents();

  if has:
    for idx, o in contents:
      if o.objVal == obj.id:
        system.delete(contents, idx)

    obj.setPropR("contents", contents)
    return true
  else:
    return false


proc getAliases*(obj: MObject): seq[string] =
  let aliases = obj.getPropVal("aliases")
  var result: seq[string] = @[]

  if aliases.isType(dList):
    for o in aliases.listVal:
      if o.isType(dStr):
        result.add(o.strVal)

  return result

proc getStrProp*(obj: MObject, name: string): string =
  let datum = obj.getPropVal(name)

  if datum.isType(dStr):
    return datum.strVal
  else:
    return ""

proc createWorld*: World =
  World( objects: @[] )

proc getObjects*(world: World): ptr seq[MObject] =
  addr world.objects

proc add*(world: World, obj: MObject) =
  var objs = world.getObjects()
  var newid = ObjID(objs[].len)

  obj.id = newid
  obj.world = world
  objs[].add(obj)

proc size*(world: World): int =
  world.objects.len

proc delete*(world: var World, obj: MObject) =
  var objs = world.getObjects()
  var idx = obj.id.int

  objs[idx] = nil

proc changeParent*(obj: var MObject, newParent: var MObject) =
  if not newParent.fertile:
    return

  if obj.parent != nil:
    # delete currently inherited properties
    obj.props.keepItIf(not it.inherited)
    obj.verbs.keepItIf(not it.inherited)

    # remove this from old parent's children
    obj.parent.children.keepItIf(it != obj)


  for p in newParent.props:
    var pc = p.copy
    pc.inherited = true
    obj.props.add(pc)

  for v in obj.verbs:
    var vc = v.copy
    vc.inherited = true
    obj.verbs.add(vc)

  obj.parent = newParent
  newParent.children.add(obj)

proc createChild*(parent: var MObject): MObject =
  if not parent.fertile:
    return nil

  var newObj = blankObject()

  newObj.is_player = parent.is_player
  newObj.pub_read = parent.pub_read
  newObj.pub_write = parent.pub_write
  newObj.fertile = parent.fertile

  newObj.changeParent(parent)

  return newObj

proc moveTo*(obj: var MObject, newLoc: var MObject): bool =
  var loc = obj.getLocation()
  if loc != nil:
    discard loc.removeFromContents(obj)

  if newLoc.addToContents(obj):
    obj.setPropR("location", newLoc)
    return true
  else:
    return false


    

