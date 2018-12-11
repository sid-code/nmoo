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
requires "asynctools"

task test, "Run tests":
  exec "nim c -r src/nmoo/test.nim"

task serve, "Run the server":
  exec "nim c -r -d:debug -o:bin/server src/nmoo"

task docs, "Generate builtin function documentation":
  exec "nim c -r src/nmoo/doc/builtindocgen.nim"
