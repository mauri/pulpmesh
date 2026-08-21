# spinel bugs found while porting pulpmesh, part 2

Found 2026-08-21, while writing the markdown renderer and the syntax
highlighter. Companion to [spinel-bugs.md](spinel-bugs.md), which covers the
`case`/empty-array miscompile. Same environment:

| | |
| --- | --- |
| spinel | `79937affbf53` |
| host cc | Apple clang 16.0.0 (clang-1600.0.26.6) |
| platform | macOS 14.6, arm64 |
| compared against | CRuby 3.3.9 |

Neither is described in
[limitations.md](https://github.com/matz/spinel/blob/master/docs/limitations.md).

---

## 3. `\p{...}` Unicode property escapes match nothing

Reproduction: [`repro/regex_unicode_properties.rb`](repro/regex_unicode_properties.rb),
self-checking — every line prints `ok` under CRuby.

```sh
ruby docs/repro/regex_unicode_properties.rb
spinel docs/repro/regex_unicode_properties.rb -o /tmp/re_props && /tmp/re_props
```

**A `\p{...}` property escape compiles, and then matches nothing.** No warning
at compile time, no error at run time.

```ruby
"abc def.1_2".scan(/\p{Word}/).join    # CRuby: "abcdef1_2"   spinel: ""
"abc def.1_2".scan(/\p{Alpha}/).join   # CRuby: "abcdef"      spinel: ""
"abc def.1_2".scan(/\p{Digit}/).join   # CRuby: "12"          spinel: ""
```

Negated inside a character class the failure inverts, so instead of matching
nothing the pattern matches nearly everything — and a `gsub` built on it deletes
the string:

```ruby
"abc def.1_2".gsub(/[^\p{Word}\- \t]/, "")
# CRuby:  "abc def1_2"
# spinel: " d"
```

### Severity

Silent, and the negated form is the dangerous one: a sanitising `gsub` written
against `\p{Word}` does not fail, it quietly destroys its input. The ASCII
spellings are correct and are the workaround:

```ruby
str.gsub(/[^\w\- \t]/, "")           # correct under both
str.gsub(/[^a-zA-Z0-9_\- \t]/, "")   # correct under both
```

`\w` is ASCII-only in both implementations, so this is a true workaround only for
ASCII input. Matching CRuby's `\p{Word}` for non-ASCII text needs an explicit
codepoint test — this port keeps any character at or above U+0080, which is an
approximation, not an equivalence.

### Where this hit the port

The GFM heading-id rule is literally `text.downcase.gsub(/[^\p{Word}\- \t]/, '')`.
Ported as written, every generated heading anchor came out mangled.

---

## 4. `String.new` on a poly value fails to compile

Reproduction: [`repro/string_new_poly.rb`](repro/string_new_poly.rb).

```sh
ruby docs/repro/string_new_poly.rb                     # prints x, exit 0
spinel docs/repro/string_new_poly.rb -o /tmp/str_poly  # C compilation failed
```

**`String.new(x)` where `x` is a poly value — an element of a nested array, for
instance — emits C that does not compile.**

```ruby
nested = [["class", "x"]]
::String.new(nested[0][1])
```

```
error: passing 'sp_RbVal' to parameter of incompatible type 'const char *'
   ... sp_String_new_shared(sp_str_dup_external(sp_poly_arr_get_hash(...)))
note: passing argument to parameter 's' here
   static inline const char *sp_str_dup_external(const char *s)
```

A *flat* array element, a local, and a literal all compile:

```ruby
flat = ["class", "x"]
::String.new(flat[1])   # ok
::String.new(local)     # ok
::String.new("x")       # ok
```

Workarounds, all correct: `nested[0][1].dup`, `+nested[0][1]`, or
`buffer = ::String.new; buffer << nested[0][1]`.

### Severity

Loud — it fails the build rather than producing a wrong answer, which makes it
much less dangerous than bugs 1–3. The cost is the diagnostic: it surfaces as a
C type error against generated code, naming spinel runtime internals rather than
the Ruby construct at fault. The reported line is right, which is what makes it
tractable at all.

---

## A related inference gotcha (not reduced to a minimal case)

A method whose body is a `gsub` with a block, called on an un-narrowed
parameter, was inferred as returning **void**, and every caller then failed to
compile with `passing 'void' to parameter of incompatible type 'sp_RbVal'`.

```ruby
# inferred void, in the context of the full program
def self.escape_text(text)
  text.gsub(/[&<>]/) { |char| ... }
end

# fixed by giving the receiver a concrete type
def self.escape_text(text)
  text.to_s.gsub(/[&<>]/) { |char| ... }
end
```

Stated carefully, because it resisted reduction: the same method in isolation —
with and without `to_s`, with `case` or `if` in the block, with a typed or
untyped parameter — compiles and runs correctly. It only failed inside the full
program, where the method sits in a mutually recursive call graph. So this is
recorded as a workaround that fixed a real build, not as a characterised bug.
Adding `.to_s` costs nothing and makes the inference unambiguous.
