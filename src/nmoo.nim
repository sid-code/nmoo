import nmoo/server

when defined(profiler):
  import nimprof

when isMainModule:
  server.start()
