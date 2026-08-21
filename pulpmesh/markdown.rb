# frozen_string_literal: true

module Pulpmesh
  module Markdown
    # Stand-in renderer: escapes the text and wraps blank-line-separated chunks
    # in paragraphs. Headings, lists, blockquotes, fenced code, links and inline
    # emphasis are not handled yet.
    def self.render(text)
      body = text.to_s
      chunks = body.split(/\r?\n[ \t]*\r?\n/)
      paragraphs = chunks.map { |chunk| chunk.strip }.reject { |chunk| chunk.empty? }
      paragraphs.map { |chunk| "<p>#{Escape.escape_html(chunk)}</p>\n" }.join("\n")
    end

    # The leading `# Title` doubles as the post title and is rendered in the page
    # header, so it is pulled off the body before conversion to keep it from
    # appearing twice. Returns [title_or_nil, remaining_body].
    def self.extract_title(text)
      body = text.to_s.sub(/\A(?:\s*\r?\n)+/, "")
      return [nil, text] unless body.start_with?("# ")

      heading, rest = body.split(/\r?\n/, 2)
      [heading.delete_prefix("# ").strip, rest.to_s]
    end
  end
end
