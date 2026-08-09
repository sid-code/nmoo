# Package

version       = "0.1.0"
author        = "Sidharth Kulkarni"
description   = "[TODO: CHANGE]"
license       = "MIT"
srcDir        = "src"
binDir        = "bin"
bin           = @["nmoo", "nmoo/schanlib/eval"]
skipFiles     = @["sidechtest.nim"]

# Dependencies

requires "nim >= 1.16.4"
requires "bcrypt"
requires "nimboost"
requires "asynctools"


task test, "Run tests":
  var compilerParams: string
  let gccParams = "'-ftest-coverage -fprofile-arcs'"

  compilerParams &= " --passC:" & gccParams &
    " --passL:" & gccParams &
    " --nimcache:./nimcache"

  exec "nim c -r " & compilerParams & " -o:bin/test test/test.nim"

task serve, "Run the server":
  exec "nim c -r -o:bin/server src/nmoo.nim"

task sccli, "Build the side channel CLI":
  exec "nim c -o:bin/sccli src/nmoo/schanlib/eval.nim"

task neval, "Build the evaluation CLI":
  exec "nim c -d:dumpTaskCode -d:singleStepTasks -o:bin/neval src/nmoo/util/eval.nim"

task serveHttp, "Run the http server":
  exec "nim c -r -o:bin/httpd src/nmoo/httpd/httpd.nim"

task docs, "Generate builtin function documentation":
  exec "nim c -r src/nmoo/doc/builtindocgen.nim"

task inline, "Run inline server (for debugging stuff)":
  exec "nim c -r -o:bin/main src/nmoo/main.nim"
