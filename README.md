## nmoo (tentative) is a MOO inspired by LambdaMOO

[LambdaMOO][1] is an old virtual community that's still running. It's a
text-based world. If you're into that sort of thing, I highly recommend going
in there once and seeing how it is.

The MOO idea that everything is an object and stems from a single root object
caught my attention. I love how the game is 100% extensible - you can define
any kind of object you want. Nothing is hard-coded, not even simple things
like rooms or characters.

This project is an attempt to create a system similar to LambdaMOO and also
an attempt to learn Nim, a very interesting new systems programming language.

I'm using the LambdaMOO [Programmer's Manual][2] as a very loose specification
for this project. 

  [1]: http://en.wikipedia.org/wiki/LambdaMOO
  [2]: http://www.hayseed.net/MOO/manuals/ProgrammersManual.html

## The scripting language

It looks like Lisp and that's because that was the easiest thing to parse, but
I wouldn't call it a Lisp dialect because the fact like it looks like Lisp is
one of the only things it has in common with Lisp. This might change, however.

It's just supposed to be a flexible but very simple imperative DSL for describing
what objects should do.

## Using

The tools needed to build this package are [the Nim compiler][5] and the Nim
package manager, [Nimble][6].

This project requires the nimble package `bcrypt`. You can type `nimble install
bcrypt` to install it. The other dependency is `nake`, but since the nimble
package doesn't have all the required features, the code for nake is included
as a submodule. That's why when you clone this repository, you need to use the
`--recursive` flag:

```
$ git clone https://github.com/sid-code/nmoo --recursive
```

First, you need to compile the nakefile:

```
$ nim c nakefile.nim
```

Then you can run the tests:

```
$ ./nakefile tests
```

That's about it for now. I'm working on getting a minimal world set up that can
be used to build upon or just showcase the features. Before that, the server and
other programs are useless.

[5]: http://nim-lang.org/ 
[6]: https://github.com/nim-lang/nimble

## HTML5 client

I've created a HTML5 client (found in `client/`) because it makes editing verbs
easier than typing stuff into raw telnet.

The client makes some assumptions about the server if you want to use the
client command "vedit" to edit verbs with CodeMirror. These assumptions are
satisfied in a "core" database that I hope to release soon.

Made possible by [jQuery Terminal][3] and [CodeMirror][4]

  [3]: http://terminal.jcubic.pl/
  [4]: https://codemirror.net/

## License

MIT
