# frozen_string_literal: true

require_relative "support/harness"

HL = Pulpmesh::Highlight
MD = Pulpmesh::Markdown

Harness.check("shell prompt and option", HL.render("$ ls -l\n", "sh"),
              "<div class=\"language-sh highlighter-rouge\"><div class=\"highlight\">" \
              "<pre class=\"highlight\"><code><span class=\"nv\">$ </span><span class=\"nb\">ls</span> " \
              "<span class=\"nt\">-l</span>\n</code></pre></div></div>")

Harness.check("shell comment", HL.render("# note\n", "sh").include?("<span class=\"c\"># note</span>"), true)
# Rouge matches a keyword as `\b(KEYWORD)\s*\b`, so the space joins the span
# when a word follows it.
Harness.check("shell keyword absorbs the space before a word", HL.render("if true\n", "sh"),
              "<div class=\"language-sh highlighter-rouge\"><div class=\"highlight\">" \
              "<pre class=\"highlight\"><code><span class=\"k\">if </span>" \
              "<span class=\"nb\">true</span>\n</code></pre></div></div>")
Harness.check("shell double-quoted string",
              HL.render("echo \"hi\"\n", "sh").include?("<span class=\"s2\">\"hi\"</span>"), true)
Harness.check("shell variable",
              HL.render("echo $HOME\n", "sh").include?("<span class=\"nv\">$HOME</span>"), true)
Harness.check("shell assignment",
              HL.render("APM=99\n", "sh").include?("<span class=\"nv\">APM</span><span class=\"o\">=</span>"), true)
Harness.check("shell single-quoted string",
              HL.render("sed -n 's/a//p'\n", "sh").include?("<span class=\"s1\">'s/a//p'</span>"), true)
Harness.check("shell command substitution",
              HL.render("x=\"$(date)\"\n", "sh").include?("<span class=\"si\">$(</span>"), true)
Harness.check("glued pipe stays plain",
              HL.render("$ a/b|grep x\n", "sh").include?("<span class=\"o\">|</span>"), false)

Harness.check("ruby keyword and method name",
              HL.render("def x\nend\n", "ruby").include?("<span class=\"k\">def</span> <span class=\"nf\">x</span>"), true)
Harness.check("ruby comment", HL.render("# hi\n", "ruby").include?("<span class=\"c1\"># hi</span>"), true)
Harness.check("ruby symbol", HL.render(":done\n", "ruby").include?("<span class=\"ss\">:done</span>"), true)
Harness.check("ruby ivar", HL.render("@count = 1\n", "ruby").include?("<span class=\"vi\">@count</span>"), true)
Harness.check("ruby integer", HL.render("@count = 1\n", "ruby").include?("<span class=\"mi\">1</span>"), true)
Harness.check("ruby interpolation",
              HL.render("\"a\#{b}\"\n", "ruby").include?("<span class=\"si\">\#{</span>"), true)

Harness.check("html in code is escaped",
              HL.render("echo \"<b>\"\n", "sh").include?("&lt;b&gt;"), true)

# An unknown language is plain escaped text in a labelled <code>, which is what
# kramdown emitted when Rouge had no lexer.
Harness.check("unknown language", MD.render("```notalang\nx = 1\n```"),
              "<pre><code class=\"language-notalang\">x = 1\n</code></pre>\n")
Harness.check("fence with no language", MD.render("```\nplain <tag>\n```"),
              "<pre><code>plain &lt;tag&gt;\n</code></pre>\n")
Harness.check("fenced shell inside markdown",
              MD.render("```sh\n$ ls\n```").include?("language-sh highlighter-rouge"), true)
