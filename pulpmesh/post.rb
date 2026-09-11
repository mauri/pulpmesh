# frozen_string_literal: true

module Pulpmesh
  # A single `.md` file, resolved into everything a template needs.
  class Post
    # Sequencing prefixes exist to order files on disk and are dropped from the
    # published path: `0010-foo.md` and `2025-10-01-foo.md` both publish as `foo`.
    SEQUENCE_PREFIX = /\A(?:\d{4}-\d{2}-\d{2}|\d+)-/
    DATE_PREFIX = /\A(\d{4}-\d{2}-\d{2})-/
    ISO_DATE = /\A(\d{4})-(\d{2})-(\d{2})/

    attr_reader :path, :basename, :slug, :title, :date, :updated_at, :tags, :description, :html

    def self.draft?(path)
      File.basename(path).start_with?("_")
    end

    def initialize(path)
      @path = path
      @basename = File.basename(path, ".md")
      front, body = FrontMatter.split(File.read(path))
      heading, body = Markdown.extract_title(body)

      stripped = basename.sub(SEQUENCE_PREFIX, "")
      @slug = slugify(stripped.empty? ? basename : stripped)
      raise Error, "#{File.basename(path)} has no usable name" if @slug.empty?

      @title = heading || front["title"] || @slug
      @updated_at = File.mtime(path).utc
      @date = resolve_date(front["date"])
      @tags = FrontMatter.list(front["tags"])
      @description = front["description"].to_s
      @html = Markdown.render(body)
    end

    def filename
      "#{slug}.html"
    end

    private

    # The published name has to be usable as a url path without escaping, since
    # it is both the file written to disk and the href linking to it. Runs of
    # anything else collapse to a single dash, and leading and trailing dashes
    # and dots come off, so `my first post.md` publishes as `my-first-post.html`.
    #
    # Letters outside ascii are kept: they are valid in a url and a browser
    # encodes them itself. The ord check stands in for a unicode property, which
    # spinel compiles to a pattern that matches nothing.
    def slugify(name)
      kept = name.gsub(/[^A-Za-z0-9._-]/) { |char| char.ord >= 128 ? char : "-" }
      kept.gsub(/-+/, "-").sub(/\A[.-]+/, "").sub(/[.-]+\z/, "")
    end

    # Date.parse is unavailable, so the accepted spelling is ISO only. That is
    # what every front-matter date and every date-prefixed filename already uses;
    # anything else falls back to the file's mtime, as an unparseable date did.
    def resolve_date(from_front_matter)
      raw = from_front_matter || basename[DATE_PREFIX, 1]
      return updated_at unless raw

      match = ISO_DATE.match(raw.to_s)
      return updated_at unless match

      # The shape can be right and the date still not exist, as `2025-13-45` is.
      # Time.utc raises on one, and that falls back like any other date it could
      # not read.
      begin
        Time.utc(match[1].to_i, match[2].to_i, match[3].to_i)
      rescue ArgumentError
        updated_at
      end
    end
  end
end
