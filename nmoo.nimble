# Package

version       = "0.1.0"
author        = "Sidharth Kulkarni"
description   = "[TODO: CHANGE]"
license       = "MIT"
srcDir        = "src"
bin           = @["nmoo"]

# Dependencies

requires "nim >= 0.17"
requires "bcrypt"

task test, "Run tests":
  exec "nim c -r src/nmoopkg/test.nim"
