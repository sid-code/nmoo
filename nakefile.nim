import nake

const
  Exes = ["test", "main"]
  DefaultOptions = "--verbosity:0"

task defaultTask, "builds everything":
  for exe in Exes:
    runTask(exe)

proc isGood(name: string): bool =
  name.needsRefresh(name & ".nim")

proc simpleBuild(name: string) =
  task name, "builds " & name:
    if name.isGood():
      if shell(nimExe, DefaultOptions, "c", name):
        echo "success building " & name
    else:
      echo name & " is up to date"

task "clean", "removes executables":
  for exe in Exes:
    echo "removing " & exe
    shell("rm ", exe)

task "tests", "run tests":
  runTask("test")
  shell("./test")


for exe in Exes:
  simpleBuild(exe)
