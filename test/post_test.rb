# frozen_string_literal: true

require_relative "support/harness"

# Not `post`: a top-level method shadows a class's own method of the same name
# under spinel, and `Site::Context#post` is what the generated templates call.
def fixture_post(name)
  Pulpmesh::Post.new(File.join(Harness::FIXTURE, name))
end

ordinal = fixture_post("0002-ordinal-prefixed.md")
dated = fixture_post("2025-10-01-date-prefixed.md")
code = fixture_post("with-code.md")

Harness.check("ordinal prefix dropped", ordinal.slug, "ordinal-prefixed")
Harness.check("filename from slug", ordinal.filename, "ordinal-prefixed.html")
Harness.check("date prefix dropped", dated.slug, "date-prefixed")
Harness.check("unprefixed name kept", code.slug, "with-code")

Harness.check("title from leading heading", ordinal.title, "Ordinal prefixed post")
Harness.check("heading not left in body", ordinal.html.include?("<h1"), false)
Harness.check("body kept", ordinal.html.include?("Body of the ordinal prefixed post."), true)

Harness.check("date from front matter", Harness.ymd(ordinal.date), "2024-03-04")
Harness.check("date from filename prefix", Harness.ymd(dated.date), "2025-10-01")

Harness.check("tags parsed", ordinal.tags, %w[ruby testing])
Harness.check("description parsed", ordinal.description, "the one with the ordinal prefix")
Harness.check("untagged post has no tags", dated.tags, [])

Harness.check("draft recognised", Pulpmesh::Post.draft?(File.join(Harness::FIXTURE, "_hidden-draft.md")), true)
Harness.check("non-draft recognised", Pulpmesh::Post.draft?(File.join(Harness::FIXTURE, "with-code.md")), false)

Harness.check("code block highlighted", code.html.include?("highlighter-rouge"), true)

# A file name that would not survive a url is reduced to one that does.
Harness.scratch("slugs") do |dir|
  slug_for = lambda do |name|
    path = File.join(dir, "#{name}.md")
    File.write(path, "# Title\n")
    Pulpmesh::Post.new(path).filename
  end

  Harness.check("spaces become dashes", slug_for.call("my first post"), "my-first-post.html")
  Harness.check("runs collapse to one dash", slug_for.call("a  --  b"), "a-b.html")
  Harness.check("query and fragment characters go", slug_for.call("what? #1 & 50%"), "what-1-50.html")
  Harness.check("colons and backslashes go", slug_for.call("a:b\\c"), "a-b-c.html")
  Harness.check("dots and underscores are kept", slug_for.call("v1.2_final"), "v1.2_final.html")
  Harness.check("accents are kept", Harness.ascii(slug_for.call("café")), "caf\\u00E9.html")
  Harness.check("edges are trimmed", slug_for.call("-.hello.-"), "hello.html")

  nameless = begin
    slug_for.call("---")
    "no error raised"
  rescue Pulpmesh::Error => e
    e.message
  end
  Harness.check("a name with nothing usable in it is refused", nameless, "---.md has no usable name")
end

# An undated post falls back to its mtime, which is not reproducible; only the
# fact that it resolved to the file's own mtime is checked.
Harness.scratch("undated") do |dir|
  path = File.join(dir, "undated.md")
  File.write(path, "# Undated\n\nbody\n")
  Harness.check_quiet("date falls back to mtime", Pulpmesh::Post.new(path).date, File.mtime(path).utc)
end
