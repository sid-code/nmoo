import std/unittest
import std/tables

import nmoo/types
import nmoo/scripting

suite "parser":
  setup:
    proc parse(str: string, options: set[MParserOption] = {}): MData {.used.} =
      var parser = newParser(str, options)
      result = parser.parseFull()
      if parser.error.errVal != E_NONE:
        return parser.error
    proc parseOne(str: string, options: set[MParserOption] = {}): MData {.used.} =
      var parser = newParser(str, options)
      result = parser.parseAtom()
      if parser.error.errVal != E_NONE:
        return parser.error

  test "parser works":
    let parsed = parse("(echo \"hello world\" (sub-list \"who knew?\" 3.14))")

    check parsed == @["begin".mds, @["echo".mds, "hello world".md, @["sub-list".mds, "who knew?".md, 3.14.md].md].md].md

  test "quote works":
    let parsed = parse("'(1 2 3)")
    check parsed == @["begin".mds, @["quote".mds, @[1.md, 2.md, 3.md].md].md].md

  test "quasiquote/unquote works":
    let parsed = parse("`(2 3 ,(x))")
    check parsed == @["begin".mds, @["quasiquote".mds, @[2.md, 3.md, @["unquote".mds, @["x".mds].md].md].md].md].md

  test "quasiquote/unquotesplat works":
    let parsed = parse("`(2 3 ,@x)")
    check parsed == @["begin".mds, @["quasiquote".mds, @[2.md, 3.md, @["unquotesplat".mds, "x".mds].md].md].md].md

  test "parser expands (obj:verb) shorthand correctly":
    let parsed = parse("(#0:filter closed door-list)")
    check parsed == @["begin".mds, @["verbcall".mds, 0.ObjID.md, "filter".md, @["list".mds, "closed".mds, "door-list".mds].md].md].md

  test "parser handles weird cases":
    var parsed = parse("((((()))))")
    check parsed.isType(dList)

    parsed = parse("((((((")
    check parsed.isType(dErr)

  test "parser propogates unexpected token errors properly":
    let parsed = parse("(let ((x 5) (y '(lambda (x) (+ x ))))) stuff)")
    check parsed.isType(dErr)

  test "parser treats 5.5.5 as a symbol":
    let parsed = parse("5.5.5")
    check parsed == @["begin".mds, "5.5.5".mds].md

  test "parser treats 5.5 as a float":
    let parsed = parse("5.5")
    check parsed == @["begin".mds, md(5.5)].md

  test "parser rejects trailing parens":
    let parsed = parse("(abc))")
    check parsed.isType(dErr)

  test "parser parses serialized tables properly":
    let parsed = parseOne("(table (1 2) (3 4))", { poTransformDataForms })
    check parsed.isType(dTable)
    check parsed.tableVal.len == 2

  test "parser handles \\n escapes properly":
    let parsed = parseOne("\"abc\\ndef\"")
    check parsed == "abc\ndef".md

  test "parser handles \\xHH escapes properly":
    var parsed = parseOne("\"abc\\x0adef\"")
    check parsed == "abc\ndef".md

    parsed = parseOne("\"abc\\x11\\x22\\xFF\"")
    check parsed == "abc\x11\x22\xFF".md
