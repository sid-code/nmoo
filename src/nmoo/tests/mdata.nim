import unittest
import types

suite "core data tests":
  test "== operator compares MData values properly":
    var
      x = 2.md
      y = 2.md

    check x == y

    x = @[1.md, "two".md, "three".mds].md
    y = @[1.md, "two".md, "three".mds].md

    check x == y

    x = @[2.md, "two".md, "three".mds].md

    check x != y

  test "== ignores line number information for MData":
    var
      x = 2.md
      y = 2.md

    x.pos = (10, 5)
    y.pos = (10, 6)

    check x == y

  test "`$` works":
    let x = @[@[1.md, 2.md, 3.md].md, 3.md].md
    check ($x) == "((1 2 3) 3)"
