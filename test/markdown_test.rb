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
Harness.check("bare bracket is literal", MD.render("[1] a footnote marker"),
              "<p>[1] a footnote marker</p>\n")

Harness.check("quotes stay straight", MD.render("It's a \"quote\""), "<p>It's a \"quote\"</p>\n")
Harness.check("markup characters escaped", MD.render("5 < 6 & 7 > 4"),
              "<p>5 &lt; 6 &amp; 7 &gt; 4</p>\n")
