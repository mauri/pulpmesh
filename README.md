# spinel-pulpmesh

A minimalist static blog generator inspired by [prose.sh](https://pico.sh/prose). Also an
excuse to dive in [spinel](https://github.com/matz/spinel) development. 

```sh
spin build
./build/bin/pulpmesh build ~/Sites/my-blog --out=/tmp/site
./build/bin/pulpmesh serve ~/Sites/my-blog --port=4000
```
## Description

Write your blog in folder of markdown and generate html out.There is no site scaffold, no theme system and no config file to create: the
markdown folder *is* the project. Output is static html with two small
stylesheets — no javascript, no build step at serve time.

The binary is standalone: the stylesheets and the compiled templates are
constants inside it, so there is no directory of Ruby files to read at
runtime.

## Usage

```
pulpmesh build [SOURCE] [options]   render SOURCE into html
pulpmesh serve [SOURCE] [options]   build, then serve it on localhost

--out=DIR        output directory (default: SOURCE/_site)
--base-url=URL   absolute site url, overriding base_url in _pulpmesh.md
--port=N         port for `serve` (default: 4000)
-v, --version
-h, --help
```

`SOURCE` defaults to the current directory. The output directory is wiped and
rewritten on every build; nothing is ever written into `SOURCE` itself.

Each build produces one `.html` per post, plus `index.html`, `404.html`,
`rss.xml`, `blog.css`, `syntax.css`, `pulpmesh-logo.svg` and `favicon.svg`.

## How a folder is read

**One `.md` file, one post.** Only the top level of the folder is scanned.

**Filenames become paths.** A leading sequencing prefix is dropped, so
`0010-frontier-model.md` and `2026-06-20-frontier-model.md` both publish as
`frontier-model.html`. Two files that would publish to the same page abort the
build.

**Files starting with `_` are drafts** and are not rendered. `_pulpmesh.md` and
`_styles.css` are configuration, not posts.

**The first `# Heading` is the title.** It is rendered in the page header and
removed from the article body so it never appears twice. Without one, the
front-matter `title:` is used, then the slug.

**The date** comes from front matter, else a `YYYY-MM-DD-` filename prefix,
else the file's mtime. Posts are listed newest first. The `last updated` line
always uses mtime.

### Post front matter

```markdown
---
date: 2026-06-20
title: only needed when there is no # heading
description: used for the meta description and og:description
tags: [ruby, static-site]
---

# Frontier model

Body text.
```

### Blog configuration — `_pulpmesh.md`

Its front matter configures the blog; its body becomes the intro section on
the index page. Every key is optional — a folder with no `_pulpmesh.md` still
builds.

| key | meaning |
| --- | --- |
| `title` | blog title (default: the folder name) |
| `description` | tagline, also the meta description |
| `base_url` | absolute site url. Without it, `rss.xml` and the `og:`/`twitter:` url tags are skipped and the build warns |
| `keywords` | meta keywords |
| `layout` | sets `class="layout-…"` on the index body |
| `with_styles` | set `false` to ignore `_styles.css` |
| `favicon` | path to a favicon, replacing the bundled `favicon.svg` |
| `card_image` | absolute url for the og:image / twitter:image card |
| `syntax_theme` | any Rouge theme name (default `base16.monokai.dark`) |
| `footer` | html for the footer line, replacing the bundled wordmark |

## Styling

Pages link three stylesheets, in order:

1. `blog.css` — bundled base styles and the utility classes the templates use.
2. `syntax.css` — generated at build time from the configured syntax theme.
3. `_styles.css` — copied from the source folder, if present. This is where a
   site's own theme goes; it is loaded last and wins.

The default colours are the pulpme.sh palette: warm paper in light, near
black in dark, links in the brand green. The pixel wordmark ships as
`pulpmesh-logo.svg` and is what the default footer line ends with;
`favicon.svg` is the same mark cut down to `pm`.

Markdown is rendered with GitHub-flavored syntax, straight (not typographic)
quotes, and `rel="nofollow"` on outbound links.

Raw html passes through normalised — an inline tag is emitted with its name
lowercased, attributes quoted and escaped, and void elements self-closed; a
tag left open is closed at the end of its block, innermost-first; a line
opening a block-level element becomes a raw block; and a `<` that does not
begin a real tag stays literal. Html entities are decoded from a bundled
entity table. The one deliberate exception is `&#0;`, left literal because
spinel's strings are NUL-terminated at the C boundary.

Post bodies, `_pulpmesh.md`'s `footer` and its body (`intro_html`) are all
rendered as raw, unescaped html by design — pulpmesh assumes the markdown
source is written by a trusted author, not submitted by end users. Do not
point it at untrusted or third-party markdown.

## What's inside

Ahead-of-time compilation rules out the usual Ruby static-site dependencies —
kramdown, Rouge, ERB, WEBrick — since none of them can compile under spinel.
Each is reimplemented here instead:

| dependency | replaced by |
| --- | --- |
| kramdown | `pulpmesh/markdown.rb` — the markdown parser this project uses, not CommonMark, with kramdown-compatible raw-html and entity handling |
| Rouge | `pulpmesh/highlight.rb` — hand-rolled `sh` and `ruby` tokenizers emitting Rouge's class names |
| ERB | `templates/*.erb` compiled ahead of time by Erubi into `pulpmesh/templates.rb` |
| WEBrick | `pulpmesh/server.rb` on `TCPServer` |
| CGI | `pulpmesh/escape.rb` |
| FileUtils | `pulpmesh/fsutil.rb` |
| Date | ISO-only parsing in `pulpmesh/post.rb` |

## Development

```sh
rake generate   # regenerate templates.rb, assets.rb and entities.rb
spin build
spin test       # seven snapshot programs, 148 checks
rake check      # fail if the committed codegen artifacts are stale
rake parity     # re-run every test under CRuby against the same snapshots
```

`pulpmesh/templates.rb`, `pulpmesh/assets.rb` and `pulpmesh/entities.rb` are
**generated and committed** — `spin.toml` has no pre-build hook. Never
hand-edit them; edit `templates/*.erb` or the files in `assets/` and run
`rake generate`. Erubi and kramdown are dev-machine tools for that task only —
kramdown supplies the entity table as data — and neither is a dependency of
the binary.

## License

MIT, see [LICENSE](LICENSE).
