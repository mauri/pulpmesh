# spinel bugs found while porting pulpmesh

Found 2026-08-21 while porting [pulpmesh](https://github.com/mauriciogaravaglia/pulpmesh)
to an AOT binary. Both trace to one root cause. Neither is covered by
[limitations.md](https://github.com/matz/spinel/blob/master/docs/limitations.md) —
these look like codegen bugs rather than documented subset boundaries.

| | |
| --- | --- |
| spinel | `79937affbf53` (`spinel --version`: `spinel 79937affbf53`) |
| host cc | Apple clang 16.0.0 (clang-1600.0.26.6) |
| platform | macOS 14.6, arm64 |
| compared against | CRuby 3.3.9 |

Reproduction: [`repro/case_empty_array.rb`](repro/case_empty_array.rb). It is
self-checking — every line prints `ok` under CRuby.

```sh
ruby docs/repro/case_empty_array.rb                              # 12 ok, exit 0
spinel docs/repro/case_empty_array.rb -o /tmp/case_empty && /tmp/case_empty
```

---

## 1. An empty collection literal in a `case` branch is miscompiled

**An empty `Array` or `Hash` literal written as the value of a `case`/`when`
branch does not survive compilation.** It comes back as `nil`, or as the zero
value of whatever type the `case` expression merges to.

```ruby
case "s" when String then [] else ["x"] end   # CRuby: []   spinel: nil
case "s" when String then [] else "str" end   # CRuby: []   spinel: ""
case "s" when String then [] else 7 end       # CRuby: []   spinel: 0
case "s" when String then {} else ["x"] end   # CRuby: {}   spinel: nil
case "s" when String then [] else [] end      # CRuby: []   spinel: nil
case "s" when String then [] end              # CRuby: []   spinel: nil
```

The substituted value tracks the *other* branch's type, which is what suggests a
type-merge over the branch results: the empty literal appears to be re-typed to
the merged type and then materialised as that type's zero value, rather than as
an empty array.

**What is not affected**, from the same run:

- Non-empty array literals in the same position — `["a"] vs ["b"]`, `["a"] vs "str"`.
- An empty array that reaches the branch as a **local** or a **method call**
  rather than a literal. Only the literal in branch position is miscompiled.
- The `if`/`else` and ternary spellings of the same choice.

That last pair is the workaround: rewrite the `case` as guard clauses.

```ruby
# miscompiled
def list(value)
  case value
  when nil then []
  when Array then value
  else value.to_s.split(",")
  end
end

# correct under both
def list(value)
  return [] if value.nil?
  return value if value.is_a?(Array)

  value.to_s.split(",")
end
```

### Severity

Silent. There is no compile-time diagnostic and no runtime error at the point
of the bad value — the program simply carries a `nil` where an empty array
should be, and fails somewhere else entirely. In the port this surfaced as
`undefined method 'each' for nil` several call frames away from the `case`
that produced it, in code that reads as obviously correct Ruby.

## 2. The miscompiled value segfaults instead of raising

Because the result is statically typed as `Array`, calling a method on it does
not go through a nil check — it is a direct call on a null pointer.

```ruby
r = case "s" when String then [] else ["x"] end
puts "about to call .each on #{r.inspect}"
$stdout.flush
r.each { |e| puts e }
```

```
CRuby   about to call .each on []      → exit 0
spinel  about to call .each on nil     → Segmentation fault: 11 (exit 139)
```

CRuby would raise `NoMethodError` for a genuine `nil` here, and spinel raises it
correctly for a `nil` it knows about — `rescue NoMethodError` around
`nil.each { }` works fine on its own. It is specifically the *statically
Array-typed null* from bug 1 that crashes.

Without the explicit `$stdout.flush` the crash loses all buffered stdout, so the
program prints nothing at all and the segfault is the only evidence.

---

## Where this hit the port

`FrontMatter.list` normalises a front-matter value that may be absent, already a
list, or a comma-separated string. Its `case value; when nil then []` branch
returned `nil` for a post with no `tags:` key, and the failure appeared later, in
the template, as `undefined method 'each' for nil`. The ported file now uses
guard clauses, with the reason recorded at the call site.
