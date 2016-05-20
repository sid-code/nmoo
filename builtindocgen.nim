# This is to be imported from the nakefile but it can be run standalone if you
# really want.  (hence the when isMainModule block at the bottom)

import strutils
import nre
import options
import streams

const
  builtinsSourceFile = "src/builtins.nim"


proc gendocs*(instream = newFileStream(builtinsSourceFile, fmRead),
              outstream = newFileStream(stdout)) =
  var currentComment = ""

  while not instream.atEnd():
    let line = instream.readLine()
    if line.strip().len == 0:
      continue

    if line[0] == '#' and line[1] == '#':
      if line.len == 2:
        currentComment &= "\n"
      else:
        if line[2] == ' ':
          currentComment &= line[3..^1] & "\n"
        else:
          currentComment &= line[2..^1] & "\n"
    elif line[0..9] == "defBuiltin":
      let matchOpt = line.match(re"""defBuiltin "([^"]+)":.*""")
      if matchOpt.isSome:
        let builtinName = matchOpt.get.captures.toSeq[0]
        let bNameLen = builtinName.len
        let numTildes = if bNameLen < 4: 4 else: bnameLen
        outstream.writeLine(builtinName)
        outStream.writeLine(repeat('~', numTildes))
        outstream.writeLine(currentComment)
      currentComment = ""

when isMainModule:
  gendocs()
