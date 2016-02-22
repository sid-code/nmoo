import nake

const
  defaultOptions = "--verbosity:0 --hint[XDeclaredButNotUsed]:off"
  mainDeps =
    @[
      "types",
      "objects",
      "scripting",
      "querying",
      "verbs",
      "builtins",
      "persist",
      "compile",
      "tasks"
    ]
  exes = {
    "main": mainDeps,
    "test": mainDeps,
    "setupmin": mainDeps,
    "server": mainDeps
  }

  outDir = "bin"

var forceRefresh = false
proc needsRefreshH(f1, f2: string): bool =
  forceRefresh or (outDir / f1).needsRefresh(f2)

task defaultTask, "builds everything":
  for info in exes:
    let (exe, deps) = info
    runTask(exe)

proc simpleBuild(name: string, deps: seq[string]) =
  task name, "builds " & name:
    let sourceFile = name & ".nim"
    var refresh = false
    for dep in deps:
      let depName = dep & ".nim"
      refresh = refresh or name.needsRefreshH(depName)

    refresh = refresh or name.needsRefreshH(sourceFile)

    if refresh:
      if direShell(nimExe, defaultOptions, "--out:" & outDir / name, "c", name):
        echo "success building " & name
    else:
      echo name & " is up to date"

task "clean", "removes executables":
  for info in exes:
    let (exe, deps) = info
    echo "removing " & exe
    removeFile(outDir / exe)

  echo "removing nimcache"
  removeDir("nimcache")

task "tests", "run tests":
  runTask("test")
  direShell("./test")

task "setup", "sets up a minimal world":
  runTask("setupmin")
  stdout.write "setting up a minimal world to use (worlds/min)... "
  direShell("./setupmin")
  echo "done!"
  echo "use this world by running \"main\" (nake main && ./main)"

task "serve", "builds and starts the server":
  runTask("server")
  direShell("./bin/server")

for info in exes:
  let (exe, deps) = info
  simpleBuild(exe, deps)
