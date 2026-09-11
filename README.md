# spinel-pulpmesh

A minimalist static blog generator inspired by [prose.sh](https://pico.sh/prose). Also an
excuse to dive in [spinel](https://github.com/matz/spinel) development. 

```sh
spin build
./build/bin/pulpmesh build ~/Sites/my-blog --out=/tmp/site
```
## Description

Write your blog in a folder of markdown and generate html out. There is no site
scaffold and no theme system: the markdown folder *is* the project. A folder of
`.md` files and nothing else builds, and `_pulpmesh.md` is there when you want
to set a title or a base url. Output is static html with two small stylesheets
— no javascript, and nothing to run once the files are built.

The binary is standalone: the stylesheets and the compiled templates are
constants inside it, so there is no directory of Ruby files to read at
runtime.

## Usage

```
pulpmesh build [SOURCE] [options]   render SOURCE into html

--out=DIR        output directory (default: SOURCE/_site)
--base-url=URL   absolute site url, overriding base_url in _pulpmesh.md
-v, --version
-h, --help
```

There is no preview server. The output is plain files, so any static file
server will do:

```sh
python3 -m http.server -d _site 4000
```

`SOURCE` defaults to the current directory. Apart from the default output
directory, `SOURCE/_site`, nothing is written into `SOURCE` itself.

The output directory is wiped and rewritten on every build, so pulpmesh only
deletes a directory it wrote itself. Each build leaves a `.pulpmesh-output`
marker behind and the next one looks for it; a directory that is empty, or
that does not exist yet, is fine too. Anything else is refused, as is building
into `SOURCE`, into a directory `SOURCE` sits inside, or into your home
directory.

Each build produces one `.html` per post, plus `index.html`, `404.html`,
`rss.xml`, `blog.css`, `syntax.css`, `pulpmesh-logo.svg` and `favicon.svg`.

## How a folder is read

**One `.md` file, one post.** Only the top level of the folder is scanned.

**Filenames become paths.** A leading sequencing prefix is dropped, so
`0010-frontier-model.md` and `2026-06-20-frontier-model.md` both publish as
`frontier-model.html`. Anything that would need escaping in a url becomes a
dash, so `my first post.md` publishes as `my-first-post.html`; letters outside
ascii are kept. Two files that would publish to the same page abort the build.

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
| `with_styles` | set `false` to ignore `_styles.css` |
| `favicon` | path to a favicon, replacing the bundled `favicon.svg` |
| `card_image` | absolute url for the og:image / twitter:image card |
| `footer` | html for the footer line, replacing the bundled wordmark |

## Styling

Pages link three stylesheets, in order:

1. `blog.css` — bundled base styles and the utility classes the templates use.
2. `syntax.css` — one snapshotted Rouge theme, `base16.monokai.dark`. There is
   no theme setting; a site that wants other colours overrides these rules.
3. `_styles.css` — copied from the source folder, if present. This is where a
   site's own theme goes; it is loaded last and wins.

The default colours are the pulpme.sh palette: warm paper in light, near
black in dark, links in the brand green. The pixel wordmark ships as
`pulpmesh-logo.svg` and is what the default footer line ends with;
`favicon.svg` is the same mark cut down to `pm`.

### Syntax highlighting

**Two languages are highlighted: shell and Ruby.** A fenced block tagged `sh`,
`bash`, `shell`, `zsh` or `console` goes through the shell tokenizer, and one
tagged `ruby` or `rb` through the Ruby one. That is the whole list.

Any other tag — `python`, `json`, `yaml`, `go` — still renders, as escaped
plain text in `<pre><code class="language-…">`, with no colouring. An untagged
block is plain `<pre><code>`. Nothing warns about this, and nothing is lost;
the code is simply not coloured.

The two tokenizers emit Rouge's class names so the snapshotted `syntax.css`
colours them, but they are not Rouge's lexers. They recognise the same kinds
of token and label them the same way; where Rouge splits a run differently the
colours match and the markup does not.

Markdown is rendered with GitHub-flavored syntax and `rel="nofollow"` on
outbound links. `![alt](pic.png "title")` becomes an `<img>`; images are not
copied into the output directory, so the path has to resolve on its own.

A link or an image may point at `http`, `https` or `mailto`, or at a relative
path, an absolute one or an anchor. A destination naming any other scheme —
`javascript:` and `data:` are the ones that matter — makes no link at all, and
the line stays on the page as the text it was written as.

A newline inside a paragraph, a list item or a blockquote is a line break, and
prose is typeset: quotes curl, `--` becomes an en dash, `---` an em dash and
`...` an ellipsis. None of that happens inside a code span or a fenced block,
in a url, or in an image's alt text, all of which keep exactly what you typed.

Headings can be written either way: `# Title` or `Title` underlined with `===`
for an `h1` and `---` for an `h2`.

Reference links, tables and footnotes are not handled. A line using one comes
out as the paragraph text it looks like. Lists are tight: a blank line ends one
rather than making it loose, and a list item holds a line of text rather than
blocks of its own.

## Html

There is none. Markdown is the whole language, and a tag written in a post is
text like any other:

```markdown
Use <script> carefully, and set <b>bold</b> with two asterisks.
```

renders with both tags visible and nothing executed, the `<b>` no more special
than the `<script>`. There is no passthrough and no option to turn one on.

So there is nothing to sanitise. Every character an author writes is escaped on
its way out, which leaves the markup the renderer generated as the only markup
on the page. A `<` that opened no tag was always literal; now every `<` is.

The one other way markdown can name something a browser will execute is a
`javascript:` url, and those make no link either, so nothing a post says turns
into script. What this does not do is decide whether the pages are fit to
publish: a link still goes where it says, and prose is still whatever was
written.

An entity reference is text on the same terms: `&amp;` is the five characters
you typed and `&mdash;` the eight, not an ampersand and not a dash. Write the
character you want — the source is utf-8 and a `<` needs no escaping, since
nothing here reads one as markup.

The `footer` key in `_pulpmesh.md` is the remaining exception: it is written by
whoever owns the blog rather than by a post, and it is emitted as given.

## What's inside

Ahead-of-time compilation rules out the usual Ruby static-site dependencies —
kramdown, Rouge, ERB — since none of them can compile under spinel. Each is
reimplemented here instead:

| dependency | replaced by |
| --- | --- |
| kramdown | `pulpmesh/markdown.rb` — the markdown parser this project uses, not CommonMark, and with no html passthrough |
| Rouge | `pulpmesh/highlight.rb` — hand-rolled `sh` and `ruby` tokenizers, and only those two, emitting Rouge's class names |
| ERB | `templates/*.erb` compiled ahead of time by Erubi into `pulpmesh/templates.rb` |
| CGI | `pulpmesh/escape.rb` |
| FileUtils | `pulpmesh/fsutil.rb` |
| Date | ISO-only parsing in `pulpmesh/post.rb` |

## Development

```sh
rake generate   # regenerate templates.rb and assets.rb
spin build
spin test       # ten snapshot programs, 199 checks
rake check      # fail if the committed codegen artifacts are stale
rake parity     # re-run every test under CRuby against the same snapshots
rake fuzz       # render random documents through the parser and kramdown
```

`rake fuzz` builds documents out of the blocks the parser claims to handle and
requires the html to match kramdown's byte for byte, allowing only the
`rel="nofollow"` this adds on purpose. `FUZZ_COUNT` sets how many, and a
failure prints the seed so `FUZZ_SEED` reproduces it. The corpus leaves out the
two shapes the parser renders differently on purpose: a language-tagged code
block, which the hand-rolled highlighter tokenizes its own way, and two lists
touching or a blank line inside one, which kramdown merges into a single loose
list and this does not.

`pulpmesh/templates.rb` and `pulpmesh/assets.rb` are **generated and
committed** — `spin.toml` has no pre-build hook. Never hand-edit them; edit
`templates/*.erb` or the files in `assets/` and run `rake generate`. Erubi
compiles the templates and kramdown is what `rake fuzz` compares against; both
are dev-machine tools, and neither is a dependency of the binary.

## License

MIT, see [LICENSE](LICENSE).
