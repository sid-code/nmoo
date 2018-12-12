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

const coverage = false
const debugBuild = false
const devBuild = true
const releaseBuild = false

task test, "Run tests":
  var compilerParams: string
  if coverage:
    let gccParams = "'-ftest-coverage -fprofile-arcs'"

    compilerParams &= " --debugger:native --passC:" & gccParams &
      " --passL:" & gccParams &
      " --nimcache:./nimcache"

  if debugBuild:
    compilerParams &= " -d:debug"

  exec "nim c -r " & compilerParams & " src/nmoo/test.nim"

task serve, "Run the server":
  var compilerParams: string

  compilerParams &= " -d:includeWizardUtils"

  if debugBuild:
    compilerParams &= " -d:debug"

  if devBuild:
    compilerParams &= " --debugger:native"

  if releaseBuild:
    compilerParams &= " -d:release"

  exec "nim c -r " & compilerParams & " -o:bin/server src/nmoo"

task docs, "Generate builtin function documentation":
  exec "nim c -r src/nmoo/doc/builtindocgen.nim"
