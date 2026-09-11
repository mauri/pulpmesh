# frozen_string_literal: true

require_relative "support/harness"

# What a build refuses to do, and what it leaves behind, kept in its own program
# because one that also rendered the fixture site grew past what spinel can
# compile — the same reason the asset checks are their own program.

# Colliding slugs abort before anything is written.
Harness.scratch("collision-src") do |source|
  File.write(File.join(source, "0001-clash.md"), "# One\n")
  File.write(File.join(source, "0002-clash.md"), "# Two\n")

  message = begin
    Pulpmesh::Site.new(source: source, output: File.join(Harness::ROOT, "unused"))
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
    Pulpmesh::Site.new(source: source, output: out).build
    Harness.check("the build leaves its marker",
                  File.exist?(File.join(out, Pulpmesh::Site::OUTPUT_MARKER)), true)

    File.write(File.join(out, "stale.html"), "old")
    Pulpmesh::Site.new(source: source, output: out).build
    Harness.check("previous output removed", Harness.children(out).include?("stale.html"), false)
  end

  Harness.check("source folder untouched", Harness.children(source), before)
end

# The feed wraps each post's html in a CDATA section, which ends at the first
# `]]>` in it. No post can produce one any more, since every `>` an author
# writes is escaped, but the wrapper does not lean on that: it splits the
# sequence wherever it finds it.
Harness.scratch("cdata-src") do |source|
  File.write(File.join(source, "_pulpmesh.md"), "---\nbase_url: https://cdata.example\n---\n")
  File.write(File.join(source, "brackets.md"), "# Brackets\n\na ]]> b\n")

  Harness.build("cdata", source) do |site, out|
    feed = File.read(File.join(out, "rss.xml"))
    Harness.check("a post cannot put the sequence in the feed", feed.include?("a ]]> b"), false)
    Harness.check("the post shows it as text", feed.include?("a ]]&gt; b"), true)
    Harness.check("one section opens for each that closes",
                  feed.scan("<![CDATA[").size, feed.scan("]]>").size)

    context = Pulpmesh::Site::Context.new(site)
    Harness.check("the wrapper splits the sequence anyway",
                  context.cdata("a ]]> b"), "<![CDATA[a ]]]]><![CDATA[> b]]>")
    Harness.check("and leaves html without it alone",
                  context.cdata("<p>x</p>"), "<![CDATA[<p>x</p>]]>")
  end
end

# A build only deletes an output directory that is empty or that a previous
# build marked as its own.
Harness.scratch("guard-src") do |source|
  File.write(File.join(source, "solo.md"), "# Solo\n\nbody\n")

  Harness.check("the source folder is refused as output",
                Harness.refusal { Pulpmesh::Site.new(source: source, output: source) },
                "output directory is the source directory")
  Harness.check("a folder holding the source is refused as output",
                Harness.refusal { Pulpmesh::Site.new(source: source, output: File.dirname(source)) },
                "output directory contains the source directory")
  Harness.check("the home directory is refused as output",
                Harness.refusal { Pulpmesh::Site.new(source: source, output: Dir.home) },
                "output directory is the home directory")

  Harness.scratch("guard-out") do |out|
    File.write(File.join(out, "notes.txt"), "not ours")
    Harness.check("a folder pulpmesh did not write is refused as output",
                  Harness.refusal { Pulpmesh::Site.new(source: source, output: out) },
                  "refusing to delete an output directory pulpmesh did not write")
    Harness.check("the refused folder is untouched", Harness.children(out), ["notes.txt"])
  end

  Harness.scratch("guard-empty") do |out|
    Pulpmesh::Site.new(source: source, output: out).build
    Harness.check("an empty folder is accepted as output",
                  Harness.children(out).include?("solo.html"), true)
  end
end

# A directory that does not exist is refused.
missing = begin
  Pulpmesh::Site.new(source: File.join(Harness::ROOT, "does-not-exist"))
  "no error raised"
rescue Pulpmesh::Error => e
  e.message.split(":").first
end
Harness.check("missing source refused", missing, "not a directory")
