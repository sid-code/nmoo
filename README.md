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

It's far from complete, in fact there is hardly anything to suggest that it
even will be a text game yet.

I'm using the LambdaMOO [Programmer's Manual][2] as a very loose specification
for this project. 

Things I have done (or almost done):
  * set up an acceptable object system with inheritance
  * created a scripting language to define verbs
  * player command parsing
  * verb handling

Things left to do:
  * build up the object database
  * networking
  * any sort of documentation

  [1]: http://en.wikipedia.org/wiki/LambdaMOO
  [2]: http://www.hayseed.net/MOO/manuals/ProgrammersManual.html

## The scripting language

It looks like Lisp and that's because that was the easiest thing to parse, but
I wouldn't call it a Lisp dialect because the fact like it looks like Lisp is
one of the only things it has in common with Lisp. This might change, however.

It's just supposed to be a flexible but very simple imperative DSL for describing
what objects should do.

## Using

There's not much to use, but here's what can be done.

The only dependency for this project is `nake` (`nimble install nake`)

Clone the repository, build the executables with the following command:

```
$ nake
```

Setup a minimal world:

```
$ nake setup
```

Run the tests:

```
$ ./tests
```
(Note: due to the recent switch from an interpreter to a compiler, hardly any of
these will even pass.)

```
$ ./server
```

You can connect to it with the details provided. The only command implemented is
"eval", so you can mess around with the scripting language.

Note: The server polls every 10ms and this is also the interval between each task
tick (when an instruction is executed). This means that verbs will run ridiculously
slowly. I'll change it later when I'm confident that the compiler and the VM are
working properly.


The main program is in a constant state of flux and therefore has no well defined
behavior. Today it does this and tomorrow it might do something else. Don't use it.

## License

MIT
