# begin Nimble config (version 2)
# --noNimblePath
--legacy:laxEffects
--mm:orc
--deepcopy:on
--passC:"-Wno-implicit-function-declaration"
--passC:"-Wno-int-conversion"
--d:useMalloc
--d:includeWizardUtils

when getEnv("NMOO_DEBUG") == "1":
  --d:debug
  --debugger:native

when getEnv("NMOO_RELEASE") == "1": 
  --d:release
  --d:danger

# begin Nimble config (version 2)
--noNimblePath
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config
