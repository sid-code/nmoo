import nake

const
  Exes = ["test", "main", "scripting"]
  DefaultOptions = "--verbosity:0"

task defaultTask, "builds everything":
  for exe in Exes:
    runTask(exe)

template simpleBuild(name: string) =
  task name, "builds " & name:
    if name.needsRefresh(name & ".nim"):
      if shell(nimExe, DefaultOptions, "c", name):
        echo "success building " & name
    else:
      echo name & " is up to date"

task "clean", "removes executables":
  for exe in Exes:
    echo "removing " & exe
    shell("rm ", exe)

simpleBuild("test")
simpleBuild("main")
simpleBuild("scripting")
