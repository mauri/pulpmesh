# spinel-pulpmesh

An ahead-of-time compiled build of [pulpmesh](https://github.com/mauriciogaravaglia/pulpmesh),
the static blog generator: a folder of markdown in, a folder of html out. Built
with [spinel](https://github.com/matz/spinel), Matz's whole-program Ruby→C
compiler.

This is a **fork**, not a port. None of the gem's four runtime dependencies —
kramdown, Rouge, ERB, WEBrick — can compile under an AOT compiler, so each is
replaced here. The gem stays the reference implementation; the two are
maintained in parallel, and the content conventions are identical so both build
the same site. The reasoning is in the gem's `docs/spinel-port.md`.

```sh
spin build
./build/bin/pulpmesh build ~/Sites/my-blog --out=/tmp/site
./build/bin/pulpmesh serve ~/Sites/my-blog --port=4000
```

The binary is standalone: the stylesheets and the compiled templates are
constants inside it, so there is no gem directory to read at runtime.

## What replaces what

| gem | here |
| --- | --- |
| kramdown | `pulpmesh/markdown.rb` — the markdown the blog uses, not CommonMark, with kramdown's raw-html and entity behaviour |
| Rouge | `pulpmesh/highlight.rb` — hand-rolled `sh` and `ruby` tokenizers emitting Rouge's class names |
| ERB | `templates/*.erb` compiled ahead of time by Erubi into `pulpmesh/templates.rb` |
| WEBrick | `pulpmesh/server.rb` on `TCPServer` |
| CGI | `pulpmesh/escape.rb` |
| FileUtils | `pulpmesh/fsutil.rb` |
| Date | ISO-only parsing in `pulpmesh/post.rb` |

Output is byte-identical to the gem's across the real blog and both fixture
sites, with and without `base_url`.

Raw html passes through as kramdown passed it: an inline tag is emitted
normalised (name lowercased, attributes quoted and escaped, void elements
self-closed), a tag left open is closed at the end of its block innermost-first,
a line opening a block-level element becomes a raw block, and a `<` that does not
begin a real tag stays literal. Html entities are decoded from kramdown's own
table. The one deliberate exception is `&#0;`, left literal because spinel's
strings are NUL-terminated at the C boundary.

## CLI

Value-carrying flags are long-only. The bundled `optparse` matches such a flag by
its long form alone, so `-o DIR` and `-p N` cannot carry values and are not
offered.

```
--out=DIR        output directory (default: SOURCE/_site)
--base-url=URL   absolute site url, overriding base_url in _readme.md
--port=N         port for `serve` (default: 4000)
-v, --version
-h, --help
```

## Development

```sh
rake generate   # regenerate templates.rb, assets.rb and entities.rb
spin build
spin test       # six snapshot programs, 142 checks
rake check      # fail if the committed codegen artifacts are stale
rake parity     # re-run every test under CRuby against the same snapshots
```

`pulpmesh/templates.rb`, `pulpmesh/assets.rb` and `pulpmesh/entities.rb` are
**generated and committed** — `spin.toml` has no pre-build hook. Never hand-edit
them; edit `templates/*.erb` or `assets/*.css` and run `rake generate`. Erubi and
kramdown are dev-machine tools for that task only — kramdown supplies the entity
table as data — and neither is a dependency of the binary.

