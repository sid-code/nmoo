import nmoo/server
import nmoo/schanlib/eval

when defined(profiler):
  import nimprof

when isMainModule:
  server.start()
