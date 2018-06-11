import strutils
import nre
import options
import streams
import packages/docutils/rstgen
import packages/docutils/rst

const
  builtinsSourceFile = "src/builtins.nim"


proc genrstdocs*(infilename = builtinsSourceFile, outfilename: string) =
  var currentComment = ""

  let outfile = open(outfilename, fmWrite)

  for line in lines(infilename):
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
        outfile.writeLine(builtinName)
        outfile.writeLine(repeat('~', numTildes))
        outfile.writeLine(currentComment)
      currentComment = ""

  outfile.close()

proc genhtmldocs*(rstinfile, outfile: string) =
  var gen: RstGenerator
  gen.initRstGenerator(outHtml, defaultConfig(), outfile, {})

  # This is a param of rstParse, an undocumented yet important proc.
  var wtf = false

  let rst = readFile(rstinfile)
  # I have no clue what most of the arguments do, so they're just going to be
  # dummy values.
  var parsedrst = rstParse(rst, rstinfile, 0, 0, wtf, {})

  var generatedHtml = ""
  gen.renderRstToOut(parsedrst, generatedHtml)
  writeFile(outFile, generatedHtml)


when isMainModule:
  gendocs()
