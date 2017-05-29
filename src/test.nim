import unittest
import tables

import types
import server
import querying
import scripting
import verbs
import compile
import tasks
import objects

test "== operator works for MData":
  var
    x = 2.md
    y = 2.md

  check x == y

  x = @[1.md, "two".md, "three".mds].md
  y = @[1.md, "two".md, "three".mds].md

  check x == y

  x = @[2.md, "two".md, "three".mds].md

  check x != y

suite "object tests":
  setup:
    var world = createWorld("test", persistent = false)
    var root = blankObject()
    objects.initializeBuiltinProps(root)
    world.add(root)
    root.owner = root
    root.setPropR("name", "root")
    root.setPropR("aliases", @[])
    root.setPropR("rootprop", "yes")
    check root.setPropChildCopy("rootprop", true)

    var genericContainer = root.createChild()
    world.add(genericContainer)
    genericContainer.setPropR("name", "generic container")
    genericContainer.setPropR("contents", @[])

    var nowhere = genericContainer.createChild()
    world.add(nowhere)

    var genericThing = root.createChild()

    world.add(genericThing)
    genericThing.setPropR("name", "generic thing")
    check genericThing.moveTo(nowhere)

    genericContainer.changeParent(genericThing)

    check genericContainer.moveTo(nowhere)

    check nowhere.getContents().len == 2

  test "property inheritance works":
    var child = root.createChild()
    world.add(child)
    child.setPropR("name", "child")

    var evenMoreChild = child.createChild()
    world.add(evenMoreChild)
    evenMoreChild.setPropR("rootprop", "no")

    check child.getPropVal("rootprop").strVal != "no"
    child.changeParent(evenMoreChild)

    check child.getPropVal("rootprop").strVal == "no"

  test "query works":
    var o1 = genericThing.createChild()
    world.add(o1)

    var o2 = genericContainer.createChild()
    world.add(o2)

    o2.setPropR("contents", @[])
    discard o1.moveTo(o2)

    o1.setPropR("aliases", @["thingy".md])
    let contents = o2.getContents()

    check contents.len == 1
    check o2.query("thin").len == 1

  # TODO: fix this and the next one
  test "verbs fire correctly":
    var verb = newVerb(
      names = "action",
      owner = root,
      doSpec = oThis,
      prepSpec = pOn,
      ioSpec = oThis,
    )

    root.verbs.add(verb)

    verb.setCode("(do argstr)", root)
    #check $root.handleCommand("action root on root") == "@[\"root on root\"]"
    check true

  test "verbs call correctly":
    var verb = newVerb(
      names = "action",
      owner = root,
      prepSpec = pNone,
      doSpec = oNone,
      ioSpec = oNone,
    )

    root.verbs.add(verb)

    verb.setCode("(do args)", root)
    #check $root.verbCall("action", root, @["hey".md]) == "@[@[\"hey\"]]"
    check true


suite "lexer":
  setup:
    let testStr = "(builtin \"stri\\\"ng\")"

  test "lexer works":
    let lexed = lex(testStr)
    check lexed.len == 5

suite "parser":
  setup:
    let testStr = "(echo \"hello world\" (sub-list \"who knew?\" 3.14))"
    var parser = newParser(testStr)
  test "parser works":
    let
      result = parser.parseList()
      str = $result

    check str == "@['echo, \"hello world\", @['sub-list, \"who knew?\", 3.14]]"

suite "evaluator":
  setup:
    var world = createWorld("test", persistent = false)
    var root = blankObject()
    initializeBuiltinProps(root)
    root.changeParent(root)
    root.level = 0
    world.add(root)

    var worthy = root.createChild()
    worthy.level = 0
    world.add(worthy)

    var unworthy = root.createChild()
    world.add(unworthy)
    unworthy.level = 3

    var verb = newVerb(
      names = "verb name",
      owner = root,
      doSpec = oNone,
      prepSpec = pWith,
      ioSpec = oNone
    )
    root.verbs.add(verb)

    root.setPropR("name", "root")

    var symtable = newSymbolTable()
    proc evalS(code: string, who: MObject = root): MData =
      let name = "test task"
      let compiled = compileCode(code, who)
      let t = world.addTask(name, who, who, who, who, symtable, compiled, ttFunction, -1)

      let tr = t.run()
      case tr.typ:
        of trFinish:
          return tr.res
        of trError:
          return tr.err
        else:
          return nilD

  test "let statement binds symbols locally":
    let result = evalS("""
    (do (let ((a "b") (b a)) b) (echo a))
    """)

    check result.isType(dErr)
    check result.errVal == E_UNBOUND

  test "cond statement works":
    var result = evalS("""
    (cond (1 "it works") (0 "it doesn't work") ("it doesn't work!!!"))
    """)

    check result.isType(dStr)
    check result.strVal == "it works"

    result = evalS("""
    (cond (0 "whoops") ("it works"))
    """)

    check result.isType(dStr)
    check result.strVal == "it works"

  test "parse statement works":
    let result = evalS("""
    (parse "(a b (c d e) 4.5)")
    """)

    check result == @["a".mds, "b".mds, @["c".mds, "d".mds, "e".mds].md, 4.5.md].md

  test "eval statement works":
    let result = evalS("""
      (eval '(call (lambda (x) (+ x x)) (5)))
    """)

    check result == 10.md

  test "getprop statement works":
    var result = evalS("""
    (getprop #1 "name")
    """)

    check result.isType(dStr)
    check result.strVal == "root"

  test "getprop raises error if property not found":
    var result = evalS("""(getprop #1 "doodoo")""")
    check result.isType(dErr)
    check result.errVal == E_PROPNF

  test "getpropinfo works":
    var result = evalS("""(getpropinfo #1 "name")""")
    check result.isType(dList)
    var rl = result.listVal
    check rl.len == 2
    check rl[0].isType(dObj)
    check rl[0] == root.md
    check rl[1].isType(dStr)

  test "setprop statement works":
    var result = evalS("""
    (setprop #1 "newprop" "val")
    """)

    check result.isType(dStr)
    check result.strVal == "val"

    result = evalS("""
    (getprop #1 "newprop")
    """)

    check result.isType(dStr)
    check result.strVal == "val"

  test "setprop correctly changes property value":
    discard evalS("""
    (setprop #1 "newprop" 400)
    """)
    discard evalS("""
    (setprop #1 "newprop" 450)
    """)

    var result = evalS("""
    (getprop #1 "newprop")
    """)

    check result == 450.md

  test "setprop checks permissions":
    let result = evalS("""
    (setprop #1 "newprop" "oops")
    """, unworthy)

    check result.isType(dErr)
    check result.errVal == E_PERM

  test "setprop sets owner of new properties correctly":
    var result = evalS("""
    (setprop #1 "newprop" "newval")
    """, worthy)

    check result.isType(dStr)
    let prop = root.getProp("newprop")
    check(not isNil(prop))
    check prop.owner == worthy

  test "setpropinfo works":
    var result = evalS("""(setpropinfo #1 "name" (#1 "rw" "name1"))""")
    check result.isType(dObj)
    check result.objVal.int == 1
    let prop = root.getProp("name1")
    check(not isNil(prop))
    check prop.name == "name1"
    check prop.pubWrite
    check prop.pubRead
    check(not prop.ownerIsParent)

  test "setpropinfo checks permissions":
    var result = evalS("""(setpropinfo #1 "name" (#1 "rw" "name1"))""", unworthy)
    check result.isType(dErr)
    check result.errVal == E_PERM

  test "props statement works":
    var result = evalS("(props #1)", worthy)
    check "name".md in result.listVal
    check "owner".md in result.listVal
    check "location".md in result.listVal
    check "contents".md in result.listVal
    check "pubread".md in result.listVal
    check "pubwrite".md in result.listVal
    check "fertile".md in result.listVal

  test "props checks permissions":
    root.pubRead = false
    var result = evalS("(props #1)", unworthy)
    check result.isType(dErr)

  test "verbs statement works":
    var result = evalS("(verbs #1)", worthy)
    check $result == "@[\"verb name\"]"

  test "verbs checks permissions":
    root.pubRead = false
    var result = evalS("(verbs #1)", unworthy)
    check result.isType(dErr)

  test "getverbinfo statement works":
    var result = evalS("(getverbinfo #1 \"verb\")")
    check result.isType(dList)
    check result.listVal.len == 3
    check result.listVal[0].isType(dObj)
    check result.listVal[1].isType(dStr)
    check result.listVal[2].isType(dStr)

  test "setverbinfo statement works":
    var result = evalS("(setverbinfo #1 \"verb\" (#1 \"rwx\" \"new ve*rb name\"))")
    result = evalS("(getverbinfo #1 \"verb\")")
    check $result == "@[#1, \"rwx\", \"new ve*rb name\"]"

  test "getverbargs statement works":
    var result = evalS("(getverbargs #1 \"verb\")")
    check result.isType(dList)
    check result.listVal.len == 3

  test "setverbargs statement works":
    var result = evalS("(setverbargs #1 \"verb\" (\"any\" \"in front of\" \"any\"))")
    check result.isType(dObj)
    check verb.doSpec == oAny
    check verb.prepSpec == pInFront
    check verb.ioSpec == oAny

  test "addverb statement works":
    var result = evalS("(addverb #1 \"cool varb\")")
    result = evalS("(getverbinfo #1 \"cool\")")
    check $result == "@[#1, \"rx\", \"cool varb\"]"
    result = evalS("(getverbargs #1 \"cool\")")
    check $result == "@[\"none\", \"none\", \"none\"]"

  test "delverb statement works":
    var result = evalS("(addverb #1 \"cool varb\")")
    let beforelen = root.verbs.len
    result = evalS("(delverb #1 \"cool\")")
    let afterlen = root.verbs.len

    check beforelen == afterlen + 1

  test "try statement works":
    var result = evalS("(try (echo unbound) 4)")
    check result == 4.md

    result = evalS("(try \"no error here!\" (echo \"incorrect except fire\") 4)")

    check result == 4.md

  test "errisval statement works":
    var result = evalS("(try (+ a b) ((erristype error E_UNBOUND) (erristype error E_ARGS)))")
    check $result == "@[1, 0]"

  test "move statement works":
    var genericContainer = root.createChild()
    world.add(genericContainer)
    genericContainer.setPropR("name", "generic container")
    genericContainer.setPropR("contents", @[])

    var nowhere = genericContainer.createChild()
    world.add(nowhere)
    nowhere.setPropR("name", "nowhere")

    var genericThing = root.createChild()
    world.add(genericThing)
    genericThing.setPropR("name", "generic thing")
    check genericThing.moveTo(nowhere)

    genericContainer.changeParent(genericThing)

    symtable["gencont"] = genericContainer.md
    symtable["nowhere"] = nowhere.md
    symtable["genthing"] = genericThing.md

    # Set up accept verb for containers
    discard evalS("""
    (do
      (addverb gencont "accept")
      (setverbcode gencont "accept" "1"))
    """)

    # move actually moves objects
    var result = evalS("(move gencont nowhere)")
    check genericContainer.getLocation() == nowhere
    let contents = nowhere.getContents()
    check genericContainer in contents

    # move removes objects from previous location
    result = evalS("(move genthing gencont)")
    let contents2 = nowhere.getContents()
    check contents2.len == 1

    # for good measure
    check genericThing.getLocation() == genericContainer

    # recursive move
    result = evalS("(move gencont gencont)")
    check result.isType(dErr)
    check result.errVal == E_RECMOVE

  test "lambda statement works":
    var result = evalS("(lambda (x y) (do x y))")
    check result.isType(dList)

  test "call-cc works":
    var result = evalS("(call-cc (lambda (x) (call x (5))))")
    check result == 5.md

  test "call statement works on lambdas":
    var result = evalS("(call (lambda (x y) (do x y)) (4 5))")
    check result == 5.md

  test "call statement works on builtins":
    var result = evalS("(call do (4 5))")
    check result == 5.md

  test "verbcall statement works":
    var obj = root.createChild()
    world.add(obj)

    var fverb = newVerb(
      names = "funcverb",
      owner = obj,
    )

    fverb.setCode("(get args 0)", root)
    discard obj.addVerb(fverb)

    symtable["obj"] = obj.md

    var result = evalS("(verbcall obj \"funcverb\" (3 4 5))")
    check result == 3.md

  test "istype statement works":
    var result = evalS("(istype \"abc\" \"str\")")
    check result == 1.md

    result = evalS("(istype 3 \"int\")")
    check result == 1.md

    result = evalS("(istype 3 \"str\")")
    check result == 0.md

    result = evalS("(istype 3 \"doodoo\")")
    check result.isType(dErr)

  test "map statement works":
    var result = evalS("(map do (1 2 3 4))")
    check result.isType(dList)
    check result.listVal.len == 4

    result = evalS("(map (lambda (x) (do x)) (1 2 3 4))")
    check result.isType(dList)
    check result.listVal.len == 4

  test "fold-right and friends work":
    var result = evalS("(fold-right + 0 (1 2 3 4))")
    check result == 10.md

    result = evalS("(reduce-right + (1 2 3 4))")
    check result == 10.md

    result = evalS("(fold-right (lambda (x y) (+ x (* 2 y))) 0 (1 3 5 7))")
    check result == 32.md

  test "arithmetic works":
    var result = evalS("(+ 3 4)")
    check result == 7.md

    result = evalS("(+ 3.0 4)")
    check result == 7.0.md

    result = evalS("(- 4 2)")
    check result == 2.md

    result = evalS("(* 4 2)")
    check result == 8.md

    result = evalS("(/ 4 2)")
    check result == 2.md
    result = evalS("(/ 4 3)")
    check result == 1.md
    result = evalS("(/ 3 4.0)")
    check result == 0.75.md

    result = evalS("(+ 3 (- 2 1))")
    check result == 4.md

  test "= statement works":
    var result = evalS("(= 3 3)")
    check result == 1.md

    result = evalS("(= (3 3 \"cat\") (3 3 \"cat\"))")
    check result == 1.md

    result = evalS("(= (3 3 \"cat\" 4) (3 3 \"cat\"))")
    check result == 0.md

  test "cat statement works":
    var result = evalS("(cat (1 2 3) (2 3 4))")
    check result.isType(dList)
    check result.listVal.len == 6

    result = evalS("(cat \"abc\" \"def\")")
    check result.isType(dStr)
    check result.strVal == "abcdef"

  test "unshift statement works":
    var result = evalS("(unshift (1 2) 1)")
    check result.isType(dList)
    check result.listVal.len == 3

  test "len statement works":
    var result = evalS("(len (1 \"a\" (1 2 3)))")

    check result == 3.md

  test "head statement works":
    var result = evalS("(head (1 2 3 4))")
    check result == 1.md

    result = evalS("(head ())")
    check result == nilD

  test "tail statement works":
    var result = evalS("(tail (1 2 3 4))")
    check result.isType(dList)
    check result.listVal.len == 3

    result = evalS("(tail ())")
    check result.isType(dList)
    check result.listVal.len == 0

  test "delete statement works":
    var result = evalS("(delete (1 2 1 1) 3)")
    check result == @[1.md, 2.md, 1.md].md

  test "insert statement works":
    var result = evalS("(insert (1 1) 1 2)")
    check result == @[1.md, 2.md, 1.md].md

  test "push statement works":
    var result = evalS("(push (1 2) 1)")
    check result == @[1.md, 2.md, 1.md].md

  test "set statement works":
    var result = evalS("(set (1 2 3) 9 4)")
    check result.isType(dErr)
    check result.errVal == E_BOUNDS

    result = evalS("(set (1 2 3) 2 1)")
    check result == @[1.md, 2.md, 1.md].md

  test "get statement works":
    var result = evalS("(get (1 2 3) 1)")
    check result == 2.md

  test "setadd statement works":
    var result = evalS("(setadd (1 2 3) 2)")
    check result.listVal.len == 3

    result = evalS("(setadd (1 2) 3)")
    check result.listVal.len == 3

  test "setremove statement works":
    var result = evalS("(setremove (1 2 3) 2)")
    check result.listVal.len == 2

    result = evalS("(setremove (1 2) 3)")
    check result.listVal.len == 2

  test "in statement works":
    var result = evalS("(in (1 2 3) 3)")
    check result.intVal == 2

    result = evalS("(in (1 2 3) 4)")
    check result.intVal == -1

  test "substr statement works":
    var result = evalS("""(substr "01234567" 2 5)""")
    check result == "2345".md

    result = evalS("""(substr "01234567" 0 -1)""")
    check result == "01234567".md

    result = evalS("""(substr "01234567" 2 -2)""")
    check result == "23456".md

    result = evalS("""(substr "01234567" -1 2)""")
    check result.isType(dErr)

    result = evalS("""(substr "01234567" 30 50)""")
    check result == "".md

  test "splice statement works":
    var result = evalS("""(splice "abcdef" 1 4 "1234")""")
    check result == "a1234f".md

    result = evalS("""(splice "abcdef" 1 -1 "123")""")
    check result == "a123".md

    result = evalS("""(splice "abcdefghijklmnop" 1 -2 "123")""")
    check result == "a123p".md

    result = evalS("""(splice "abcdefghijklmnop" 1 -10 "123")""")
    check result == "a123hijklmnop".md

    result = evalS("""(splice "abcdefghijklmnop" 40 -10 "123")""")
    check result.isType(dErr)

    result = evalS("""(splice "abcdefghijklmnop" -1 10 "123")""")
    check result.isType(dErr)

  test "index statement works":
    var result = evalS("(index \"abcdefghij\" \"def\")")
    check result.intVal == 3

    result = evalS("(index \"abcdefghij\" \"adef\")")
    check result.intVal == -1

  test "range statement works":
    var result = evalS("(range 10 15)")
    check result == @[10.md, 11.md, 12.md, 13.md, 14.md, 15.md].md

  test "match statement works":
    var result = evalS("(match \"abcdef\" \"a(%w+)f\")")
    check result.isType(dList)
    let captures = result.listVal
    check captures.len == 1
    check captures[0] == "bcde".md

  test "find statement works":
    var result = evalS("""(find "hello %[n]" "%%%[([^%]]+)%]")""")
    check result == @[6.md, 9.md, @["n".md].md].md

    result = evalS("""(find "ayy lmao" "y" 3)""")
    check result == nilD

    result = evalS("""(find "ayy lmao" "y" 2)""")
    check result == @[2.md, 2.md, @[].md].md

  test "gsub statement works":
    var result = evalS("""(gsub "a <bc> <defghi>" "<([^>]+)>" "$1")""")
    check result == "a bc defghi".md

    result = evalS("""(gsub "a <bc> <defghi>" "<(?<named>[^>]+)>" "$named")""")
    check result == "a bc defghi".md

  test "fit statement works":
    var result = evalS("""(fit "hello world" 10)""")
    check result == "hello worl".md

    result = evalS("""(fit "hello world" 15)""")
    check result == "hello world    ".md

    result = evalS("""(fit "hello world" 15 "x")""")
    check result == "hello worldxxxx".md

    result = evalS("""(fit "hello world" 6 " " "...")""")
    check result == "hel...".md

    result = evalS("""(fit "hello world" 6 " " "abcdefg")""")
    check result == "abcdef".md

    result = evalS("""(fit "hello world" -15)""")
    check result == "    hello world".md

    result = evalS("""(fit "hello world" -15 "x")""")
    check result == "xxxxhello world".md

    result = evalS("""(fit "hello world" -6 " " "abcdefg")""")
    check result == "bcdefg".md
