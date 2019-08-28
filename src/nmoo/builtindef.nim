import types
import tables

var builtins* = initTable[string, BuiltinProc]()

proc builtinExists*(name: string): bool =
  builtins.hasKey(name)

# defining builtins

# TODO: find out new meanings of immediate and dirty pragmas and see if they're
# really needed here.
template defBuiltin*(name: string, body: untyped) {.dirty.} =
  template bname: string = name
  builtins[name] =
    proc (args: seq[MData], world: World,
          self, player, caller, owner: MObject,
          symtable: SymbolTable, pos: CodePosition, phase = 0,
          task: Task = nil): Package =
      body
