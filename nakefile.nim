import nake, tables

const
  DefaultOptions = "--verbosity:0"

var Exes = initTable[string, seq[string]]()
Exes["test"] = @["types", "objects", "scripting", "querying", "verbs"]
Exes["main"] = @["types", "objects"]

task defaultTask, "builds everything":
  for exe, deps in Exes:
    runTask(exe)


proc simpleBuild(name: string, deps: seq[string]) =
  task name, "builds " & name:
    let sourceFile = name & ".nim"
    var refresh = false
    for dep in deps:
      let depName = dep & ".nim"
      refresh = refresh or name.needsRefresh(depName)

    refresh = refresh or name.needsRefresh(sourceFile)

    if refresh:
      if shell(nimExe, DefaultOptions, "c", name):
        echo "success building " & name
    else:
      echo name & " is up to date"

task "clean", "removes executables":
  for exe, deps in Exes:
    echo "removing " & exe
    shell("rm ", exe)

task "tests", "run tests":
  runTask("test")
  shell("./test")


for exe, deps in Exes:
  simpleBuild(exe, deps)
