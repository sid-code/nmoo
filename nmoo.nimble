# Package

version       = "0.1.0"
author        = "Sidharth Kulkarni"
description   = "[TODO: CHANGE]"
license       = "MIT"
srcDir        = "src"
binDir        = "bin"
bin           = @["nmoo/server"]
skipFiles     = @["sidechtest.nim"]

# Dependencies

requires "nim >= 0.17"
requires "bcrypt"
requires "nimboost"

task test, "Run tests":
  exec "nim c -r src/nmoopkg/test.nim"

task docs, "Generate builtin function documentation":
  exec "nim c -r src/nmoopkg/doc/builtindocgen.nim"
