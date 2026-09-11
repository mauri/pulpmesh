# frozen_string_literal: true

require_relative "support/harness"

MD = Pulpmesh::Markdown

Harness.check("title extracted", MD.extract_title("# T\n\nbody\n")[0], "T")
Harness.check("body after title", MD.extract_title("# T\n\nbody\n")[1], "\nbody\n")
Harness.check("no title when not a heading", MD.extract_title("body\n")[0], nil)
Harness.check("leading blank lines skipped", MD.extract_title("\n\n# T\n\nb")[0], "T")
Harness.check("hash without space is not a title", MD.extract_title("#T\n")[0], nil)

Harness.check("paragraph", MD.render("Hello."), "<p>Hello.</p>\n")
Harness.check("leading blank line kept", MD.render("\nHello."), "\n<p>Hello.</p>\n")
Harness.check("two paragraphs", MD.render("One.\n\nTwo."), "<p>One.</p>\n\n<p>Two.</p>\n")
Harness.check("soft break kept", MD.render("a\nb"), "<p>a\nb</p>\n")
Harness.check("empty input", MD.render(""), "")

Harness.check("heading with id", MD.render("#### The workaround"),
              "<h4 id=\"the-workaround\">The workaround</h4>\n")
Harness.check("heading id keeps underscores", MD.render("## snake_case heading"),
              "<h2 id=\"snake_case-heading\">snake_case heading</h2>\n")
Harness.check("heading id keeps leading digits", MD.render("## 10 years later"),
              "<h2 id=\"10-years-later\">10 years later</h2>\n")
Harness.check("heading id drops punctuation", MD.render("## What's wrong?"),
              "<h2 id=\"whats-wrong\">What's wrong?</h2>\n")
Harness.check("duplicate heading ids are numbered", MD.render("## Same\n\n## Same\n\n## Same"),
              "<h2 id=\"same\">Same</h2>\n\n<h2 id=\"same-1\">Same</h2>\n\n<h2 id=\"same-2\">Same</h2>\n")
Harness.check("heading with no id-able text", MD.render("## !!!"), "<h2>!!!</h2>\n")

Harness.check("horizontal rule", MD.render("a\n\n---\n\nb"), "<p>a</p>\n\n<hr />\n\n<p>b</p>\n")
Harness.check("unordered list", MD.render("- one\n- two"),
              "<ul>\n  <li>one</li>\n  <li>two</li>\n</ul>\n")
Harness.check("ordered list", MD.render("1. one\n2. two"),
              "<ol>\n  <li>one</li>\n  <li>two</li>\n</ol>\n")
Harness.check("blockquote", MD.render("> quoted\n> more"),
              "<blockquote>\n  <p>quoted\nmore</p>\n</blockquote>\n")

Harness.check("inline code", MD.render("a `c` b"), "<p>a <code>c</code> b</p>\n")
Harness.check("code span is literal", MD.render("a `x < y & z` b"),
              "<p>a <code>x &lt; y &amp; z</code> b</p>\n")
Harness.check("double backticks", MD.render("use ``a ` b`` here"),
              "<p>use <code>a ` b</code> here</p>\n")
Harness.check("strong", MD.render("a **b** c"), "<p>a <strong>b</strong> c</p>\n")
Harness.check("em with star", MD.render("a *b* c"), "<p>a <em>b</em> c</p>\n")
Harness.check("em with underscore", MD.render("a _b_ c"), "<p>a <em>b</em> c</p>\n")
Harness.check("intraword underscores untouched", MD.render("ID_ATA_FEATURE_SET_APM=1"),
              "<p>ID_ATA_FEATURE_SET_APM=1</p>\n")

Harness.check("absolute link gets nofollow", MD.render("[out](https://example.com)"),
              "<p><a href=\"https://example.com\" rel=\"nofollow\">out</a></p>\n")
Harness.check("relative link left alone", MD.render("[in](other.html)"),
              "<p><a href=\"other.html\">in</a></p>\n")
Harness.check("parens in a url are balanced, not cut at the first one",
              MD.render("[Ruby](https://en.wikipedia.org/wiki/Ruby_(programming_language))"),
              "<p><a href=\"https://en.wikipedia.org/wiki/Ruby_(programming_language)\" " \
              "rel=\"nofollow\">Ruby</a></p>\n")
Harness.check("an unbalanced destination is literal text", MD.render("[x](a(b)"),
              "<p>[x](a(b)</p>\n")
Harness.check("a title is its own attribute", MD.render(%([x](u "t"))),
              "<p><a href=\"u\" title=\"t\">x</a></p>\n")
Harness.check("a single-quoted title too", MD.render("[x](u 't')"),
              "<p><a href=\"u\" title=\"t\">x</a></p>\n")

Harness.check("a quote in an attribute cannot end it", MD.render("[a](u \"it's\")"),
              "<p><a href=\"u\" title=\"it&#39;s\">a</a></p>\n")
Harness.check("a quote in text is left alone", MD.render("plain 'quotes' stay"),
              "<p>plain 'quotes' stay</p>\n")

Harness.check("image", MD.render("![alt](pic.png)"),
              "<p><img src=\"pic.png\" alt=\"alt\" /></p>\n")
Harness.check("image with an empty alt", MD.render("![](pic.png)"),
              "<p><img src=\"pic.png\" alt=\"\" /></p>\n")
Harness.check("image alt is literal, not markup", MD.render("![a *b*](pic.png)"),
              "<p><img src=\"pic.png\" alt=\"a *b*\" /></p>\n")
Harness.check("image alt is escaped", MD.render(%(![a "b" & c](p.png))),
              "<p><img src=\"p.png\" alt=\"a &quot;b&quot; &amp; c\" /></p>\n")
Harness.check("image with a title", MD.render(%(![a](p.png "t"))),
              "<p><img src=\"p.png\" alt=\"a\" title=\"t\" /></p>\n")
Harness.check("image inside a link", MD.render("[![a](p.png)](http://x)"),
              "<p><a href=\"http://x\" rel=\"nofollow\"><img src=\"p.png\" alt=\"a\" /></a></p>\n")
Harness.check("an image gets no nofollow", MD.render("![a](https://ex.com/p.png)"),
              "<p><img src=\"https://ex.com/p.png\" alt=\"a\" /></p>\n")
Harness.check("a bang that starts no image is literal", MD.render("!not an image"),
              "<p>!not an image</p>\n")
Harness.check("a bang before a link is literal", MD.render("!![a](p.png)"),
              "<p>!<img src=\"p.png\" alt=\"a\" /></p>\n")
Harness.check("bare bracket is literal", MD.render("[1] a footnote marker"),
              "<p>[1] a footnote marker</p>\n")

Harness.check("quotes stay straight", MD.render("It's a \"quote\""), "<p>It's a \"quote\"</p>\n")
Harness.check("markup characters escaped", MD.render("5 < 6 & 7 > 4"),
              "<p>5 &lt; 6 &amp; 7 &gt; 4</p>\n")

# Raw html passes through as kramdown passed it.
Harness.check("paired inline tag", MD.render("a <b>bold</b> c"), "<p>a <b>bold</b> c</p>\n")
Harness.check("unclosed tag is closed at the end of the block",
              MD.render("AT&T and <b> tags"), "<p>AT&amp;T and <b> tags</b></p>\n")
Harness.check("nested unclosed tags close innermost first",
              MD.render("a <b> <i> c"), "<p>a <b> <i> c</i></b></p>\n")
Harness.check("crossed pair leaves the stray close as text",
              MD.render("a <b><i>x</b></i> c"), "<p>a <b><i>x&lt;/b&gt;</i> c</b></p>\n")
Harness.check("closing tag with no opener is text",
              MD.render("a </b> c"), "<p>a &lt;/b&gt; c</p>\n")
Harness.check("void element is self-closed", MD.render("a <br> b"), "<p>a <br /> b</p>\n")
Harness.check("attributes are normalised",
              MD.render(%(a <span class="x" data-y='z'>s</span> b)),
              "<p>a <span class=\"x\" data-y=\"z\">s</span> b</p>\n")
Harness.check("bare attribute gets an empty value",
              MD.render("a <input disabled> b"), "<p>a <input disabled=\"\" /> b</p>\n")
Harness.check("attribute value is escaped",
              MD.render(%(a <b title="x>y">z</b> c)), "<p>a <b title=\"x&gt;y\">z</b> c</p>\n")
Harness.check("tag name is lowercased", MD.render("a <B>x</B> b"), "<p>a <b>x</b> b</p>\n")
Harness.check("markdown inside a tag is still rendered",
              MD.render("a <b>*it*</b> b"), "<p>a <b><em>it</em></b> b</p>\n")
Harness.check("comment passes through", MD.render("a <!-- hi --> b"), "<p>a <!-- hi --> b</p>\n")
Harness.check("lt that is not a tag stays literal", MD.render("5 < 6 and a <3 b"),
              "<p>5 &lt; 6 and a &lt;3 b</p>\n")
Harness.check("tag inside a code span is escaped",
              MD.render("use `<b>` here"), "<p>use <code>&lt;b&gt;</code> here</p>\n")
Harness.check("block level element is a raw block",
              MD.render("text\n\n<div>x</div>\n\ntext"),
              "<p>text</p>\n\n<div>x</div>\n\n<p>text</p>\n")
Harness.check("nested block level element", MD.render("<div>\n<div>x</div>\n</div>"),
              "<div>\n<div>x</div>\n</div>\n")
Harness.check("void block is normalised and closes the document",
              MD.render("<hr>"), "<hr />\n\n")

# Entities are decoded and re-escaped, never double-escaped.
Harness.check("named entity survives", MD.render("AT&T &amp; co"), "<p>AT&amp;T &amp; co</p>\n")
Harness.check("numeric entity decoded", MD.render("a &#x41; b"), "<p>a A b</p>\n")
Harness.check("unknown entity stays literal", MD.render("a &bogus; b"), "<p>a &amp;bogus; b</p>\n")
Harness.check("latin-1 named entity", MD.render("Caf&eacute;"), "<p>Caf\u00E9</p>\n")
Harness.check("entity names are case sensitive", MD.render("&Eacute; &eacute;"), "<p>\u00C9 \u00E9</p>\n")
Harness.check("typographic entity", MD.render("a &mdash; b"), "<p>a \u2014 b</p>\n")
Harness.check("non-ascii numeric entity", MD.render("a &#233; b"), "<p>a \u00E9 b</p>\n")
# Left literal on purpose: spinel's strings are NUL-terminated at the C
# boundary, so decoding this would truncate the document.
Harness.check("nul entity is refused", MD.render("a &#0; b"), "<p>a &amp;#0; b</p>\n")
Harness.check("entity past the end of unicode is refused", MD.render("&#x110000;"),
              "<p>&amp;#x110000;</p>\n")
Harness.check("surrogate entity is refused", MD.render("&#xD800;"), "<p>&amp;#xD800;</p>\n")
Harness.check("the last code point still decodes",
              Harness.ascii(MD.render("&#x10FFFF;")), "<p>\\u10FFFF</p>\n")
Harness.check("a huge decimal entity is refused", MD.render("&#9999999999;"),
              "<p>&amp;#9999999999;</p>\n")
