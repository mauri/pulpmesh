# frozen_string_literal: true

module Pulpmesh
  # The markdown the blog actually uses, rendered to the same html kramdown
  # produced: ATX headings with generated ids, fenced code, lists, blockquotes,
  # horizontal rules and paragraphs, over inline code, links, strong and em.
  #
  # Not CommonMark. Reference links, images, tables, setext headings, html
  # blocks and footnotes are not handled; a line using one is emitted as the
  # paragraph text it looks like.
  module Markdown
    ATX = /\A(\#{1,6})[ \t]+(.*?)[ \t]*\#*[ \t]*\z/
    FENCE = /\A(?:```|~~~)[ \t]*([^\s`]*)[ \t]*\z/
    FENCE_END = /\A(?:```|~~~)[ \t]*\z/
    RULE = /\A[ \t]{0,3}(?:(?:-[ \t]*){3,}|(?:\*[ \t]*){3,}|(?:_[ \t]*){3,})\z/
    QUOTE = /\A[ \t]{0,3}>[ \t]?/
    BULLET = /\A[ \t]{0,3}[-*+][ \t]+(.*)\z/
    ORDERED = /\A[ \t]{0,3}\d+\.[ \t]+(.*)\z/
    BLOCK_START = /\A(?:\#{1,6}[ \t]|```|~~~|[ \t]{0,3}>|[ \t]{0,3}[-*+][ \t]|[ \t]{0,3}\d+\.[ \t])/
    ABSOLUTE = %r{\A[a-z][a-z0-9+.-]*://}i

    def self.render(text)
      Renderer.new(text.to_s).render
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

    # Text content, where only the three markup characters are escaped. Quotes
    # are left alone, as kramdown left them.
    def self.escape_text(text)
      text.to_s.gsub(/[&<>]/) do |char|
        case char
        when "&" then "&amp;"
        when "<" then "&lt;"
        else "&gt;"
        end
      end
    end

    # Walks the string once, emitting escaped text and finished html as it goes,
    # so generated markup is never re-escaped and never re-scanned. Precedence is
    # code spans, then links, then strong, then em.
    def self.inline(text)
      out = ::String.new
      index = 0
      length = text.length

      while index < length
        char = text[index]
        handled = false

        if char == "`"
          finish = code_span(text, index)
          if finish
            out << finish[0]
            index = finish[1]
            handled = true
          end
        elsif char == "["
          finish = link(text, index)
          if finish
            out << finish[0]
            index = finish[1]
            handled = true
          end
        elsif char == "*" || char == "_"
          finish = emphasis(text, index)
          if finish
            out << finish[0]
            index = finish[1]
            handled = true
          end
        end

        next if handled

        out << case char
               when "&" then "&amp;"
               when "<" then "&lt;"
               when ">" then "&gt;"
               else char
               end
        index += 1
      end

      out
    end

    # A run of n backticks closes on the next run of exactly n. The content is
    # literal: no inline markup is recognised inside it.
    def self.code_span(text, start)
      open_end = start
      open_end += 1 while open_end < text.length && text[open_end] == "`"
      ticks = open_end - start

      cursor = open_end
      while cursor < text.length
        if text[cursor] == "`"
          run_end = cursor
          run_end += 1 while run_end < text.length && text[run_end] == "`"
          return ["<code>#{escape_text(text[open_end...cursor])}</code>", run_end] if run_end - cursor == ticks

          cursor = run_end
        else
          cursor += 1
        end
      end
      nil
    end

    # `[label](href)`. A `[` with no matching `](...)` is literal text, which is
    # what a footnote marker like `[1]` relies on.
    def self.link(text, start)
      label_end = matching_bracket(text, start)
      return nil unless label_end && text[label_end + 1] == "("

      href_end = text.index(")", label_end + 2)
      return nil unless href_end

      label = text[(start + 1)...label_end]
      href = text[(label_end + 2)...href_end].strip
      rel = href.match?(ABSOLUTE) ? " rel=\"nofollow\"" : ""
      ["<a href=\"#{escape_attribute(href)}\"#{rel}>#{inline(label)}</a>", href_end + 1]
    end

    # Bracket matching rather than a regex, so a label may contain brackets.
    def self.matching_bracket(text, start)
      depth = 0
      cursor = start
      while cursor < text.length
        char = text[cursor]
        if char == "["
          depth += 1
        elsif char == "]"
          depth -= 1
          return cursor if depth.zero?
        elsif char == "`"
          span = code_span(text, cursor)
          if span
            cursor = span[1]
            next
          end
        end
        cursor += 1
      end
      nil
    end

    # `**x**` / `__x__` are strong, `*x*` / `_x_` are em. An underscore only
    # delimits at a word boundary, so `snake_case_name` stays intact.
    def self.emphasis(text, start)
      char = text[start]
      double = text[start + 1] == char
      marker = double ? "#{char}#{char}" : char
      content_start = start + marker.length

      return nil if char == "_" && !boundary?(text[start - 1]) && start.positive?
      return nil if content_start >= text.length
      return nil if text[content_start] == " " || text[content_start] == "\t"

      cursor = content_start
      while cursor < text.length
        found = text.index(marker, cursor)
        return nil unless found
        # A longer run is a different delimiter; skip past it.
        if !double && text[found + 1] == char
          cursor = found + 2
          next
        end

        previous = text[found - 1]
        if previous == " " || previous == "\t" || previous == "\n"
          cursor = found + marker.length
          next
        end
        if char == "_" && !boundary?(text[found + marker.length])
          cursor = found + marker.length
          next
        end

        tag = double ? "strong" : "em"
        content = text[content_start...found]
        return ["<#{tag}>#{inline(content)}</#{tag}>", found + marker.length]
      end
      nil
    end

    # End of string, whitespace or punctuation — anything but a word character.
    def self.boundary?(char)
      return true if char.nil?

      !char.match?(/[a-zA-Z0-9]/)
    end

    def self.escape_attribute(text)
      text.to_s.gsub(/[&<>"]/) do |char|
        case char
        when "&" then "&amp;"
        when "<" then "&lt;"
        when ">" then "&gt;"
        else "&quot;"
        end
      end
    end

    # One document. Holds the ids already handed out, so a repeated heading gets
    # the `-1` suffix kramdown gave it.
    class Renderer
      def initialize(source)
        @source = source.gsub("\r\n", "\n")
        @used_ids = {}
      end

      def render
        blocks = parse(@source.split("\n", -1))
        return "" if blocks.empty?

        # kramdown kept the blank line that separated the title from the body,
        # and closed the document with a newline.
        leading = @source.start_with?("\n") ? "\n" : ""
        leading + blocks.join("\n\n") + "\n"
      end

      private

      def parse(lines)
        blocks = []
        index = 0
        while index < lines.length
          line = lines[index]
          if line.strip.empty?
            index += 1
          elsif (fence = FENCE.match(line))
            index = fenced_code(blocks, lines, index, fence[1])
          elsif (atx = ATX.match(line))
            blocks << heading(atx[1].length, atx[2])
            index += 1
          elsif RULE.match(line)
            blocks << "<hr />"
            index += 1
          elsif QUOTE.match(line)
            index = blockquote(blocks, lines, index)
          elsif BULLET.match(line)
            index = list(blocks, lines, index, "ul", BULLET)
          elsif ORDERED.match(line)
            index = list(blocks, lines, index, "ol", ORDERED)
          else
            index = paragraph(blocks, lines, index)
          end
        end
        blocks
      end

      def heading(level, text)
        id = id_for(text)
        # kramdown emitted no attribute at all when nothing survived the rule.
        attribute = id.empty? ? "" : " id=\"#{Markdown.escape_attribute(id)}\""
        "<h#{level}#{attribute}>#{Markdown.inline(text)}</h#{level}>"
      end

      # The GFM parser's rule, which is the one the gem's `input: "GFM"` used:
      # downcase, drop everything that is not a word character, dash or space,
      # then spaces and tabs to dashes. `\w` rather than `\p{Word}`, which
      # spinel compiles to a pattern that matches nothing.
      def id_for(text)
        # `\w` is ASCII-only, so non-ascii is kept explicitly. That is an
        # approximation of \p{Word}: it keeps accented letters, and also keeps
        # non-ascii symbols that kramdown would have dropped.
        kept = plain_text(text).downcase.gsub(/[^\w\- \t]/) do |char|
          char.ord >= 128 ? char : ""
        end
        base = kept.tr(" \t", "-")

        seen = @used_ids[base]
        if seen
          @used_ids[base] = seen + 1
          "#{base}-#{seen}"
        else
          @used_ids[base] = 1
          base
        end
      end

      # The id comes from the heading's text content. Rendering the inline pass
      # and dropping the tags gets that exactly, so an underscore that never
      # delimited emphasis stays part of the word.
      def plain_text(text)
        bare = Markdown.inline(text).gsub(/<[^>]*>/, "")
        bare.gsub("&lt;", "<").gsub("&gt;", ">").gsub("&quot;", "\"").gsub("&amp;", "&")
      end

      def fenced_code(blocks, lines, index, language)
        body = []
        index += 1
        while index < lines.length && !FENCE_END.match(lines[index])
          body << lines[index]
          index += 1
        end
        index += 1 if index < lines.length

        code = body.empty? ? "" : "#{body.join("\n")}\n"
        blocks << if language.empty?
                    "<pre><code>#{Markdown.escape_text(code)}</code></pre>"
                  else
                    Highlight.render(code, language)
                  end
        index
      end

      def blockquote(blocks, lines, index)
        body = []
        while index < lines.length && !lines[index].strip.empty? && QUOTE.match(lines[index])
          body << lines[index].sub(QUOTE, "")
          index += 1
        end

        inner = parse(body)
        blocks << "<blockquote>\n#{inner.map { |block| "  #{block}" }.join("\n\n")}\n</blockquote>"
        index
      end

      # Tight lists only: a blank line ends the list rather than making it loose.
      # A line that is not a new item and starts no other block continues the
      # current item, which is how a wrapped item reads.
      def list(blocks, lines, index, tag, marker)
        items = []
        current = nil
        while index < lines.length
          line = lines[index]
          break if line.strip.empty?

          match = marker.match(line)
          if match
            items << current if current
            current = [match[1]]
          elsif current && !BLOCK_START.match(line) && !RULE.match(line)
            current << line.strip
          else
            break
          end
          index += 1
        end
        items << current if current

        rendered = items.map { |item| "  <li>#{Markdown.inline(item.join("\n"))}</li>" }
        blocks << "<#{tag}>\n#{rendered.join("\n")}\n</#{tag}>"
        index
      end

      def paragraph(blocks, lines, index)
        body = []
        while index < lines.length
          line = lines[index]
          break if line.strip.empty?
          break if body.any? && (BLOCK_START.match(line) || RULE.match(line) || FENCE.match(line))

          body << line
          index += 1
        end
        blocks << "<p>#{Markdown.inline(body.join("\n").strip)}</p>"
        index
      end
    end
  end
end
