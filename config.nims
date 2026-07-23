# begin Nimble config (version 2)
# --noNimblePath
--legacy:laxEffects
--mm:orc
# --d:useMalloc
# --deepcopy:on
--passC:"-Wno-implicit-function-declaration"
--passC:"-Wno-int-conversion"
--d:includeWizardUtils

when getEnv("NMOO_DEBUG") == "1":
  --d:debug
  --d:useGcAssert
  --debugger:native

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
