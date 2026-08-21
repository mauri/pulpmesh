# spinel bug: top-level methods shadow a class's own methods

Found 2026-08-21, while porting pulpmesh's test suite. Third in a series with
[spinel-bugs.md](spinel-bugs.md) (the `case`/empty-array miscompile) and
[spinel-bugs-regex-and-types.md](spinel-bugs-regex-and-types.md) (`\p{...}` and
`String.new`). This is the worst of the five: it silently returns the wrong
value, from a construct with no warning sign at the call site.

| | |
| --- | --- |
| spinel | `79937affbf53` |
| host cc | Apple clang 16.0.0 (clang-1600.0.26.6) |
| platform | macOS 14.6, arm64 |
| compared against | CRuby 3.3.9 |

Reproduction: [`repro/toplevel_method_shadowing.rb`](repro/toplevel_method_shadowing.rb),
self-checking — all four lines print `ok` under CRuby.

```sh
ruby docs/repro/toplevel_method_shadowing.rb
spinel docs/repro/toplevel_method_shadowing.rb -o /tmp/shadow && /tmp/shadow
```

## 5. Method lookup is inverted for top-level definitions

In CRuby a top-level `def` is a private instance method on `Object`. A class's
own method therefore wins for instances of that class — normal lookup, the class
before its ancestors. **Under spinel the top-level method wins instead.**

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

No warning, no error — just the other method's return value.

### It can also raise, or fail the build

The visible symptom depends on what the two definitions look like. With
mismatched arity it becomes a runtime error, still pointing nowhere near the
top-level `def`:

```ruby
class Labelled
  attr_reader :label
  def render = "<#{label}>"
end

def label(prefix) = "#{prefix}!"

Labelled.new("a").render
# CRuby:  "<a>"
# spinel: ArgumentError: wrong number of arguments (given 0, expected 1)
```

And when the types cannot be reconciled it fails the C compile, naming the
generated symbol rather than either definition:

```
error: initializing 'sp_RbVal' with an expression of incompatible type 'sp_Post *'
```

### Severity

The highest of the bugs found so far. The other four either fail the build or
mangle a value in a way that shows up quickly; this one **silently calls a
different method**, and the two definitions can be in different files with
nothing at the call site to suggest a conflict.

It is also easy to hit by accident. A test file that defines a small helper at
the top level — `def post(...)`, `def config(...)`, `def render(...)` — will
quietly capture every unqualified call to a same-named method anywhere in the
program.

### Workaround

Do not define top-level methods whose names collide with any method in the
program. Give helpers a distinguishing prefix, or define them inside a module.

### Where this hit the port

`test/post_test.rb` had a top-level `def post(name)` returning a `Post`. The
generated templates call `post` unqualified inside `Site::Context`, where it is
an `attr_reader`. The result was a C compile error against `pulpmesh/templates.rb`
that never mentioned the test file. The same file runs correctly under CRuby,
which is what made it confusing: `spin test` compiled one thing and `ruby` ran
another. Renaming the helper to `fixture_post` fixed it.
