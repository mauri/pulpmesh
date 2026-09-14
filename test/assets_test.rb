# frozen_string_literal: true

require_relative "support/harness"

# The stylesheets and the svgs are compiled into the binary by `rake assets`.
# What a compiled binary can check is that the constants it was built from still
# match the files on disk; the staleness diff itself lives in `rake check`.
PROJECT = [
  File.expand_path("..", __dir__),
  __dir__
].find { |candidate| File.exist?(File.join(candidate, "spin.toml")) }

# Compared as bytes because blog.css carries an em-dash, and CRuby reads the
# file in the default external encoding, which need not be UTF-8.
def same?(constant, file)
  constant.bytes == File.read(File.join(PROJECT, "assets", file)).bytes
end

Harness.check("blog.css compiled in verbatim", same?(Pulpmesh::Assets::BLOG, "blog.css"), true)
Harness.check("syntax.css compiled in verbatim", same?(Pulpmesh::Assets::SYNTAX, "syntax.css"), true)
Harness.check("favicon.svg compiled in verbatim", same?(Pulpmesh::Assets::FAVICON, "favicon.svg"), true)
Harness.check("the wordmark compiled in verbatim",
              same?(Pulpmesh::Assets::PULPMESH_LOGO, "pulpmesh-logo.svg"), true)
