
type
  MObject = ref object
    id: int
    is_player: bool
    
    props: seq[MProperty]
    verbs: seq[MVerb]

    parent: MObject
    children: seq[MObject]

    pub_write: bool
    pub_read: bool
    fertile: bool

  MProperty = ref object
    name: string
    val: MData
    owner: MObject
    inheritor: MObject

    pub_write: bool
    pub_read: bool
    owner_is_parent: bool

  MVerb = object # stub
    names: string
    owner: MObject
    inheritor: MObject

    code: string

  MDataType = enum
    dInt, dFloat, dStr, dErr, dList, dObj

  MData = object
    case dtype: MDataType
      of dInt: intVal: int
      of dFloat: floatVal: float
      of dStr: strVal: string
      of dErr: errVal: MError
      of dList: listVal: seq[MData]
      of dObj: objVal: ObjID

  MError = enum
    E_WHOOPS

  ObjID = distinct int

proc md*(x: int): MData = MData(dtype: dInt, intVal: x)
proc md*(x: float): MData = MData(dtype: dFloat, floatVal: x)
proc md*(x: string): MData = MData(dtype: dStr, strVal: x)
proc md*(x: MError): MData = MData(dtype: dErr, errVal: x)
proc md*(x: seq[MData]): MData = MData(dtype: dList, listVal: x)
proc md*(x: ObjID): MData = MData(dtype: dObj, objVal: x)
proc md*(x: MObject): MData = x.id.md

proc `$`*(x: ObjID): string {.borrow.}
proc `$`*(x: MData): string {.inline.} =
  case x.dtype:
    of dInt: return $x.intVal
    of dFloat: return $x.floatVal & "f"
    of dStr: return "\"" & $x.strVal & "\""
    of dErr: return "some error"
    of dList: return $x.listVal
    of dObj: return "#" & $x.objVal

proc blankObject*(): MObject =
  var obj = MObject(
    id: 0,
    is_player: false,
    props: @[],
    verbs: @[],
    parent: nil,
    children: @[],
    pub_read: true,
    pub_write: false,
    fertile: true
  )

  return obj

proc getProp*(obj: MObject, name: string): MProperty =
  for p in obj.props:
    if p.name == name:
      return p

  return nil

proc `val=`*(prop: MProperty, newVal: MData) =
  prop.val = newVal

proc setProp*(obj: MObject, name: string, newVal: MData) =
  var p = obj.getProp(name)
  if p == nil:
    obj.props.add(MProperty(
      name: name,
      val: newVal,
      owner: obj,
      inheritor: nil,
      
      pub_read: true,
      pub_write: false,
      owner_is_parent: true
    ))
  else:
    p.val = newVal

var o = blankObject()
o.setProp("name", "hi".md)

