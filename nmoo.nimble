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

requires "nim >= 0.20"
requires "bcrypt"
requires "nimboost"
requires "asynctools"

const coverage = getEnv("NMOO_COVERAGE") == "1"
const debugBuild = getEnv("NMOO_DEBUG") == "1"
const devBuild = true
const releaseBuild = getEnv("NMOO_RELEASE") == "1"
const useGcAssert = getEnv("NMOO_GC_ASSERT") == "1"

task test, "Run tests":
  var compilerParams: string
  if coverage:
    let gccParams = "'-ftest-coverage -fprofile-arcs'"

    compilerParams &= " --debugger:native --passC:" & gccParams &
      " --passL:" & gccParams &
      " --nimcache:./nimcache"

  if debugBuild:
    compilerParams &= " -d:debug"

  if useGcAssert:
    compilerParams &= " -d:useGcAssert"

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

  if useGcAssert:
    compilerParams &= " -d:useGcAssert"

  exec "nim c -r " & compilerParams & " -o:bin/server src/nmoo"

task docs, "Generate builtin function documentation":
  exec "nim c -r src/nmoo/doc/builtindocgen.nim"
