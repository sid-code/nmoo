import nake

const
  DefaultOptions = "--verbosity:0 --hint[XDeclaredButNotUsed]:off"
  MainDeps =
    @["types", "objects", "scripting", "querying", "verbs", "builtins", "persist"]
  Exes = {
    "main": MainDeps,
    "test": MainDeps
  }


task defaultTask, "builds everything":
  for info in Exes:
    let (exe, deps) = info
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
      if direShell(nimExe, DefaultOptions, "c", name):
        echo "success building " & name
    else:
      echo name & " is up to date"

task "clean", "removes executables":
  for info in Exes:
    let (exe, deps) = info
    echo "removing " & exe
    removeFile(exe)

  echo "removing nimcache"
  removeDir("nimcache")

task "tests", "run tests":
  runTask("test")
  direShell("./test")


for info in Exes:
  let (exe, deps) = info
  simpleBuild(exe, deps)
