import nake/nake

const
  defaultOptions = ""

  # Needs to be a seq to be passed in to
  # the simpleBuild proc
  mainDeps = @[
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

  nimbleDeps = [
    "bcrypt",
  ]

  srcDir = "src"
  outDir = "bin"

  defaultWorldName = "min"

var
  worldName = defaultWorldName
  extraOptions = ""

var forceRefresh = false
proc needsRefreshH(f1, f2: string): bool =
  forceRefresh or (outDir / f1).needsRefresh(f2)

task defaultTask, "builds everything":
  for info in exes:
    let (exe, _) = info
    runTask(exe)

proc toSource(name: string): string =
  srcDir / name & ".nim"

proc compile(source, output: string): bool =
  direShell(nimExe, defaultOptions, extraOptions, "--out:" & output, "c", source)

proc simpleBuild(name: string, deps: seq[string]) =
  task name, "builds " & name:
    let sourceFile = name.toSource()
    var refresh = false
    for dep in deps:
      let depName = dep.toSource()
      refresh = refresh or name.needsRefreshH(depName)

    refresh = refresh or name.needsRefreshH(sourceFile)

    if refresh:
      if compile(source = name.toSource, output = outDir / name):
        echo "success building " & name
    else:
      echo name & " is up to date"

task "clean", "removes executables":
  for info in exes:
    let (exe, _) = info
    echo "removing " & exe
    removeFile(outDir / exe)

  echo "removing compiled nakefile"
  removeFile("nakefile")

  echo "removing nimcache(s)"
  removeDir(srcDir / "nimcache")
  removeDir("nimcache")

task "tests", "run tests":
  runTask("test")
  direShell(outDir / "test")

task "setup", "sets up a minimal world":
  runTask("setupmin")
  stdout.write "setting up a minimal world to use (worlds/min)... "
  direShell("./setupmin")
  echo "done!"
  echo "use this world by running \"main\" (nake main && ./main)"

task "serve", "builds and starts the server":
  runTask("server")
  direShell(outDir / "server " & worldName)

for info in exes:
  let (exe, deps) = info
  simpleBuild(exe, deps)

static:
  echo "Checking nimble dependencies..."
  for ndep in nimbleDeps:
    let res = staticExec("nimble path " & ndep & " > /dev/null; echo $?")
    if res == "0":
      echo "Dependency '", ndep, "' met."
    else:
      echo "Nimble package '", ndep, "' missing."
      echo "Run 'nimble install ", ndep, "' to install it."
      quit(1)

for kind, key, val in getopt():
  case kind:
    of cmdArgument: discard
    of cmdLongOption, cmdShortOption:
      case key:
        of "world", "w": worldName = val
        of "debug": extraOptions &= " --debugger:native "
        else: extraOptions &= " --" & key & ":" & val & " "
    of cmdEnd: assert(false) # can't happen
