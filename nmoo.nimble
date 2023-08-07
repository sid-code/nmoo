# Package

version       = "0.1.0"
author        = "Sidharth Kulkarni"
description   = "[TODO: CHANGE]"
license       = "MIT"
srcDir        = "src"
binDir        = "bin"
bin           = @["nmoo"]
skipFiles     = @["sidechtest.nim"]

# Dependencies

requires "nim >= 1.16.4"
requires "bcrypt"
requires "nimboost"
requires "asynctools"

const coverage = getEnv("NMOO_COVERAGE") == "1"
const debugBuild = getEnv("NMOO_DEBUG") == "1"
const releaseBuild = getEnv("NMOO_RELEASE") == "1"
const estpProfiler = getEnv("NMOO_PROFILE") == "default"
const hottieProfiler = getEnv("NMOO_PROFILE") == "hottie"
const useGcAssert = getEnv("NMOO_GC_ASSERT") == "1"

proc getBuildFlags(): string =
  result &= " --legacy:laxEffects"
  result &= " --mm:orc --deepcopy:on"

  # without this we get weird ORC segfaults
  result &= " -d:useMalloc"

  if debugBuild:
    result &= " -d:debug"
    result &= " --debugger:native"

  if releaseBuild:
    result &= " -d:release -d:danger"

  if estpProfiler:
    result &= " -d:profiler --profiler:on --stacktrace:on"

  if hottieProfiler:
    result &= " --debugger:native -d:release -d:danger --passL:\"-no-pie\""

  if useGcAssert:
    result &= " -d:useGcAssert"

task test, "Run tests":
  var compilerParams: string
  if coverage:
    let gccParams = "'-ftest-coverage -fprofile-arcs'"

    compilerParams &= " --passC:" & gccParams &
      " --passL:" & gccParams &
      " --nimcache:./nimcache"

  compilerParams &= getBuildFlags()

  exec "nim c -r " & compilerParams & " src/nmoo/test.nim"

task serve, "Run the server":
  var compilerParams: string

  compilerParams &= " -d:includeWizardUtils"
  compilerParams &= getBuildFlags()

  exec "nim c -r " & compilerParams & " -o:bin/server src/nmoo"

task serveHttp, "Run the http server":
  var compilerParams: string
  compilerParams &= getBuildFlags()
  exec "nim c -r " & compilerParams & " -o:bin/httpd src/nmoo/httpd/httpd.nim"

task docs, "Generate builtin function documentation":
  exec "nim c -r src/nmoo/doc/builtindocgen.nim"
