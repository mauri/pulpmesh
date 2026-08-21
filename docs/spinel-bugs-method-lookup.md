# spinel bug: a top-level method shadows a class's own method of the same name

**Method lookup is inverted for top-level definitions.** An unqualified call
inside a class dispatches to a same-named top-level method instead of to the
class's own. It happens silently: no warning at compile time, no error at run
time, just the other method's return value.

Found 2026-08-21 while compiling a Ruby project's test suite with spinel.

| | |
| --- | --- |
| spinel | `79937affbf53` |
| host cc | Apple clang 16.0.0 (clang-1600.0.26.6) |
| platform | macOS 14.6, arm64 |
| compared against | CRuby 3.3.9 |

Reproduction: [`repro/toplevel_method_shadowing.rb`](repro/toplevel_method_shadowing.rb),
self-checking — every line prints `ok` under CRuby.

```sh
ruby docs/repro/toplevel_method_shadowing.rb
spinel docs/repro/toplevel_method_shadowing.rb -o /tmp/shadow && /tmp/shadow
```

## The bug

In CRuby a top-level `def` is a private instance method on `Object`. A class's
own method therefore wins for instances of that class — ordinary lookup, the
class before its ancestors. Under spinel the top-level method wins instead.

```ruby
class Greeter
  def greeting
    "from the class"
  end

  def render
    greeting          # unqualified call to its own method
  end
end

def greeting          # top-level method, same name
  "from the top level"
end

Greeter.new.render
# CRuby:  "from the class"
# spinel: "from the top level"
```

## It can also raise, or fail the build

The visible symptom depends on what the two definitions look like. Where the
arities differ it becomes a runtime error that points nowhere near the
top-level `def`:

```ruby
class Labelled
  attr_reader :label

  def render
    "<#{label}>"
  end
end

def label(prefix)
  "#{prefix}!"
end

Labelled.new("a").render
# CRuby:  "<a>"
# spinel: ArgumentError: wrong number of arguments (given 0, expected 1)
```

Where the types cannot be reconciled at all it fails the C compile, naming a
generated symbol rather than either definition:

```
error: initializing 'sp_RbVal' with an expression of incompatible type 'sp_Post *'
```

## Severity

The silent form is the dangerous one. The program keeps running and returns a
plausible value from the wrong method, and the two definitions can sit in
different files with nothing at the call site to suggest a conflict.

It is easy to hit by accident. A file that defines a small helper at the top
level — `def post(...)`, `def config(...)`, `def render(...)` — captures every
unqualified call to a same-named method anywhere in the program, including
methods belonging to classes it has nothing to do with.

It is also harder to diagnose than a normal compile failure, because the same
file behaves correctly under CRuby. A test that passes under `ruby` and fails
under spinel gives no hint that the cause is a name collision.

## Workaround

Do not define top-level methods whose names collide with any method name used
elsewhere in the program. Give top-level helpers a distinguishing prefix, or
define them inside a module or class rather than at the top level.

## How it was found

A test file for a static site generator defined a top-level helper
`def post(name)` returning a `Post` object. Elsewhere in the same program, an
`attr_reader :post` on a `Site::Context` class is called unqualified from
generated template code. Compiling the test produced a C type error against the
generated template file, which never mentioned the test file or the helper. The
identical file ran correctly under CRuby. Renaming the helper to `fixture_post`
resolved it.
