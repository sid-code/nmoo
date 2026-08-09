# begin Nimble config (version 2)
# --noNimblePath
--out:"./bin/"
--legacy:laxEffects
--mm:arc
--d:useMalloc
--deepcopy:on
--passC:"-Wno-implicit-function-declaration"
--passC:"-Wno-int-conversion"
--d:includeWizardUtils

--path:"./src"

when getEnv("NMOO_DEBUG") == "1":
  --d:debug
  --d:useGcAssert
  --passC:"-fsanitize=address,undefined"
  --passL:"-fsanitize=address,undefined"
  --debugger:native

when getEnv("NMOO_DUMP_TASKS") == "1":
  --d:dumpTaskCode

when getEnv("NMOO_SINGLE_STEP") == "1":
  --d:debug
  --d:singleStepTasks

when getEnv("NMOO_RELEASE") == "1":
  --d:release
  --d:danger

when getEnv("NMOO_PROFILE") == "1":
  --stackTrace:on
  --profiler:on

# begin Nimble config (version 2)
--noNimblePath
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config
