# frozen_string_literal: true

require_relative "support/harness"

Harness.build("site", Harness::FIXTURE) do |site, out|
  Harness.check("one page per post plus the extras", Harness.children(out),
                %w[404.html date-prefixed.html favicon.svg index.html
                   ordinal-prefixed.html pulpmesh-logo.svg rss.xml smol.css
                   syntax.css with-code.html])
  Harness.check("drafts are not published", Harness.children(out).include?("hidden-draft.html"), false)
  Harness.check("readme is not a post", site.posts.map { |p| p.slug }.include?("readme"), false)
  Harness.check("posts ordered newest first", site.posts.map { |p| p.slug },
                %w[date-prefixed ordinal-prefixed with-code])

  index = File.read(File.join(out, "index.html"))
  Harness.check("draft body absent from index", index.include?("A draft nobody should see"), false)
  Harness.check("index links every post",
                site.posts.all? { |p| index.include?("href=\"#{p.filename}\"") }, true)
  Harness.check("index renders the readme intro",
                index.include?("Intro paragraph for the fixture blog."), true)
  Harness.check("site stylesheet not linked when absent", index.include?("href=\"_styles.css\""), false)
  Harness.check("default favicon linked",
                index.include?("<link rel=\"icon\" type=\"image/svg+xml\" href=\"favicon.svg\">"), true)
  Harness.check("footer carries the wordmark",
                index.include?("<img src=\"pulpmesh-logo.svg\" alt=\"pulpmesh\" class=\"footer-logo\">"), true)

  page = File.read(File.join(out, "ordinal-prefixed.html"))
  article = page[/<article class="md">(.*?)<\/article>/m, 1]
  Harness.check("title in the header",
                page.include?("<h1 class=\"text-2xl font-bold\">Ordinal prefixed post</h1>"), true)
  Harness.check("title not repeated in the article", article.include?("Ordinal prefixed post"), false)
  Harness.check("absolute og url",
                page.include?("<meta property=\"og:url\" content=\"https://fixture.example/ordinal-prefixed.html\">"), true)
  Harness.check("absolute twitter url",
                page.include?("<meta name=\"twitter:url\" content=\"https://fixture.example/ordinal-prefixed.html\">"), true)
  Harness.check("tags rendered", page.include?("<span class=\"tag\">ruby</span>"), true)

  feed = File.read(File.join(out, "rss.xml"))
  Harness.check("one rss item per post", feed.scan("<item>").size, site.posts.size)
  Harness.check("rss links are absolute",
                feed.include?("<link>https://fixture.example/with-code.html</link>"), true)
  Harness.check("rss carries categories", feed.include?("<category>ruby</category>"), true)
  Harness.check("syntax stylesheet written", File.read(File.join(out, "syntax.css")).include?(".highlight"), true)
  Harness.check("no warnings for a complete site", site.warnings, [])
end

Harness.build("override", Harness::FIXTURE, base_url: "https://override.example") do |_site, out|
  Harness.check("base_url option overrides the config",
                File.read(File.join(out, "rss.xml")).include?("https://override.example/with-code.html"), true)
end

# A folder with no _readme.md and no base_url.
Harness.scratch("solo-src") do |source|
  File.write(File.join(source, "solo.md"), "# Solo\n\nJust one post.\n")

  Harness.build("solo", source) do |site, out|
    Harness.check("builds without a readme", Harness.children(out).include?("solo.html"), true)
    Harness.check("title falls back to the folder name", site.config.title, File.basename(source))
    Harness.check("no feed without base_url", Harness.children(out).include?("rss.xml"), false)
    Harness.check("no og:url without base_url", File.read(File.join(out, "solo.html")).include?("og:url"), false)
    Harness.check("warning names base_url", site.warnings.first.include?("base_url"), true)
  end
end

# A stylesheet in the source folder is copied and linked.
Harness.scratch("styled-src") do |source|
  File.write(File.join(source, "post.md"), "# P\n\nbody\n")
  File.write(File.join(source, "_styles.css"), "body { color: red }")

  Harness.build("styled", source) do |_site, out|
    Harness.check("stylesheet copied", File.read(File.join(out, "_styles.css")), "body { color: red }")
    Harness.check("stylesheet linked",
                  File.read(File.join(out, "index.html")).include?("href=\"_styles.css\""), true)
  end
end

# A configured favicon replaces the bundled one, which is then not written.
Harness.scratch("favicon-src") do |source|
  File.write(File.join(source, "_readme.md"), "---\nfavicon: /icon.png\n---\n")
  File.write(File.join(source, "post.md"), "# P\n\nbody\n")

  Harness.build("favicon", source) do |_site, out|
    Harness.check("bundled favicon not written", Harness.children(out).include?("favicon.svg"), false)
    Harness.check("configured favicon linked",
                  File.read(File.join(out, "index.html")).include?("<link rel=\"icon\" href=\"/icon.png\">"), true)
  end
end

# Colliding slugs abort before anything is written.
Harness.scratch("collision-src") do |source|
  File.write(File.join(source, "0001-clash.md"), "# One\n")
  File.write(File.join(source, "0002-clash.md"), "# Two\n")

  message = begin
    Pulpmesh::Site.new(source: source, output: "/tmp/pulpmesh-test-unused")
    "no error raised"
  rescue Pulpmesh::Error => e
    e.message
  end
  Harness.check("colliding slugs abort", message,
                "0001-clash.md and 0002-clash.md both publish as clash.html")
end

# The output directory is replaced, and the source is never written into.
Harness.scratch("replace-src") do |source|
  File.write(File.join(source, "solo.md"), "# Solo\n\nbody\n")
  before = Harness.children(source)

  Harness.scratch("replace-out") do |out|
    File.write(File.join(out, "stale.html"), "old")
    Pulpmesh::Site.new(source: source, output: out).build
    Harness.check("previous output removed", Harness.children(out).include?("stale.html"), false)
  end

  Harness.check("source folder untouched", Harness.children(source), before)
end

# A directory that does not exist is refused.
missing = begin
  Pulpmesh::Site.new(source: "/tmp/pulpmesh-test-does-not-exist")
  "no error raised"
rescue Pulpmesh::Error => e
  e.message.split(":").first
end
Harness.check("missing source refused", missing, "not a directory")
