nmoo is a MOO inspired by LambdaMOO
===================================

`LambdaMOO <http://en.wikipedia.org/wiki/LambdaMOO>`__ is an old virtual
community that's still running. It's a text-based world that caught my eye with
its interesting design principle: everything is an object in a parent-child
inheritance hierarchy with a single root object. Rooms, players, containers,
and everything else are described by properties that are either inherited from
their parents or defined directly on them. Actions are carried out by executing
"verbs" which can be modified by other verbs (and by extension, players). A MOO
is the  kind of game in which the primary goals of players are not only to play
and interact, but to build.

This project is an attempt to create a system similar to LambdaMOO using a new
programming language called Nim.

I'm using the LambdaMOO `Programmer's Manual
<http://www.hayseed.net/MOO/manuals/ProgrammersManual.html>`__ as a very loose
guide for this project.

How do I use this?
==================

You can't really use it yet because this is just an engine. There's a whole
world that I have to build within it which I have not completed yet. However,
in the meantime you can run tests to make sure that some parts of the engine
work properly on your system.

The tools needed to build this package are `the Nim compiler
<http://nim-lang.org/>`__ and the Nim package manager, `Nimble
<https://github.com/nim-lang/nimble>`__.

Start by cloning this repository::

    $ git clone https://github.com/sid-code/nmoo

   
Then, simply build with nimble::

    $ nimble build
  
Check the bin directory for the server executable.

You can also run tests with ``nimble test`` or generate docs with
``nimble docs`` (they go into the ``doc/`` folder)

The scripting language
======================

Verb code is written using a custom S-expression based scripting language. The
fundamental concepts of the language differ from traditional S-exp languages
such as Lisp or Scheme because the fundamental data type is not the pair, but
rather the MOO data type (which can hold numbers, strings, and lists among
other things).


License
=======

MIT
