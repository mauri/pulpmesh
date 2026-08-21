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
| kramdown | `pulpmesh/markdown.rb` — the markdown the blog uses, not CommonMark |
| Rouge | `pulpmesh/highlight.rb` — hand-rolled `sh` and `ruby` tokenizers emitting Rouge's class names |
| ERB | `templates/*.erb` compiled ahead of time by Erubi into `pulpmesh/templates.rb` |
| WEBrick | `pulpmesh/server.rb` on `TCPServer` |
| CGI | `pulpmesh/escape.rb` |
| FileUtils | `pulpmesh/fsutil.rb` |
| Date | ISO-only parsing in `pulpmesh/post.rb` |

Output is byte-identical to the gem's across the real blog and both fixture
sites, with and without `base_url`.

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
rake generate   # regenerate pulpmesh/templates.rb and pulpmesh/assets.rb
spin build
spin test       # six snapshot programs, 115 checks
rake check      # fail if the committed codegen artifacts are stale
rake parity     # re-run every test under CRuby against the same snapshots
```

`pulpmesh/templates.rb` and `pulpmesh/assets.rb` are **generated and committed** —
`spin.toml` has no pre-build hook. Never hand-edit them; edit `templates/*.erb`
or `assets/*.css` and run `rake generate`. Erubi is a dev-machine tool, not a
dependency of the binary.

## spinel bugs found here

Five, each with a runnable reproduction under `docs/repro/`:

- [docs/spinel-bugs.md](docs/spinel-bugs.md) — an empty array literal in a `case`
  branch compiles to `nil`, and then segfaults when used.
- [docs/spinel-bugs-regex-and-types.md](docs/spinel-bugs-regex-and-types.md) —
  `\p{...}` matches nothing; `String.new` on a poly value fails to compile.
- [docs/spinel-bugs-method-lookup.md](docs/spinel-bugs-method-lookup.md) — a
  top-level `def` shadows a class's own method of the same name.
