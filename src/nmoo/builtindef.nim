{.used.}
import types
import tables

var builtins* = initTable[string, BuiltinProc]()

proc builtinExists*(name: string): bool =
  builtins.hasKey(name)

# defining builtins

template defBuiltin*(name: string, body: untyped) {.dirty.} =
  template bname: string {.used, redefine.} = name
  builtins[name] =
    proc (args: seq[MData], world: World,
          self, player, caller, owner: MObject,
          symtable: SymbolTable, pos: CodePosition, phase = 0,
          tid: TaskID): Package =
      let task {.used.} = world.getTaskByID(tid).get
      body
