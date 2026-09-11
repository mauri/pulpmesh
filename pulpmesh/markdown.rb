# frozen_string_literal: true

module Pulpmesh
  # The markdown the blog actually uses: ATX and setext headings with generated
  # ids, fenced code, lists, blockquotes, horizontal rules and paragraphs, over
  # inline code, links, images, strong and em.
  #
  # Markdown is the whole language. Html written in a post is text like any
  # other: `<script>` is read as the characters it is made of, never as a tag,
  # and `&amp;` as the five characters it is made of, never as an ampersand.
  # There is no passthrough, no tag stack and nothing to sanitise, because
  # nothing an author writes can become markup the renderer did not generate.
  #
  # Not CommonMark. Reference links, tables and footnotes are not handled; a
  # line using one is emitted as the paragraph text it looks like.
  module Markdown
    ATX = /\A(\#{1,6})[ \t]+(.*?)[ \t]*\#*[ \t]*\z/
    FENCE = /\A(?:```|~~~)[ \t]*([^\s`]*)[ \t]*\z/
    FENCE_END = /\A(?:```|~~~)[ \t]*\z/
    RULE = /\A[ \t]{0,3}(?:(?:-[ \t]*){3,}|(?:\*[ \t]*){3,}|(?:_[ \t]*){3,})\z/
    # The line under a setext heading. Its first character picks the level, and
    # the rest may mix the two, as kramdown's own pattern did.
    SETEXT_UNDERLINE = /\A([-=])[-=]*[ \t]*\z/
    # A source that ends on a blank line, as against one that merely ends with
    # a newline.
    TRAILING_BLANK = /\n[ \t]*\n\s*\z/
    QUOTE = /\A[ \t]{0,3}>[ \t]?/
    BULLET = /\A[ \t]{0,3}[-*+][ \t]+(.*)\z/
    ORDERED = /\A[ \t]{0,3}\d+\.[ \t]+(.*)\z/
    BLOCK_START = /\A(?:\#{1,6}[ \t]|```|~~~|[ \t]{0,3}>|[ \t]{0,3}[-*+][ \t]|[ \t]{0,3}\d+\.[ \t])/
    ABSOLUTE = %r{\A[a-z][a-z0-9+.-]*://}i

    # The scheme a url names, if it names one at all.
    SCHEME = /\A([a-zA-Z][a-zA-Z0-9+.-]*):/
    # Schemes a link or an image may use. A url with no scheme is relative and
    # always fine; one naming anything else — `javascript:` above all — is not a
    # url this will emit.
    SAFE_SCHEMES = %w[http https mailto].freeze
    # Whitespace and control characters, which a browser drops before it reads
    # the scheme. Left in while checking, `java<tab>script:` would pass as a
    # relative path and then run as `javascript:`.
    IGNORED_IN_SCHEME = /[[:space:]\x00-\x1F\x7F]/

    # The optional `"title"` trailing a link or image destination.
    TITLED_DOUBLE = /\A(.*?)[ \t]+"(.*)"\z/
    TITLED_SINGLE = /\A(.*?)[ \t]+'(.*)'\z/

    # Character sets tested one character at a time. A string include? beats
    # building a match against a regex for every character.
    WHITESPACE = " \t\r\n\f\v"
    ALPHANUMERIC = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"

    EM_DASH = "—"
    EN_DASH = "–"
    ELLIPSIS = "…"
    LDQUO = "“"
    RDQUO = "”"
    LSQUO = "‘"
    RSQUO = "’"

    QUOTE_CHAR = /["']/

    # Typographic quotes, ported from kramdown, which took them from RubyPants,
    # which took them from SmartyPants. Which of the four characters a `"` or a
    # `'` becomes depends on what surrounds it. The rules are tried in the order
    # they are written here, and the first that matches at the quote wins.
    #
    # They are named constants applied by a chain rather than a table walked in
    # a loop: spinel cannot call `match` with a start offset on a Regexp it read
    # out of an array, and every rule here needs that offset.
    SQ_PUNCT = '[!"#\$\%\'()*+,\-.\/:;<=>?\@\[\\\\\]\^_`{|}~]'
    SQ_CLOSE = %![^ \\\\\t\r\n\\[{(-]!

    # A quote opening emphasis, as in: "*emphasised*"
    SQ_EMPHASIS = /("|')(?=[_*]{1,2}\S)/
    # A quote against punctuation closes, unless an ellipsis follows.
    SQ_PUNCT_AHEAD = /("|')(?=#{SQ_PUNCT}(?!\.\.)\B)/
    # Two quotes together, as in: He said, "'Quoted' words in a larger quote."
    SQ_DOUBLE_SINGLE = /(\s?)"'(?=\w)/
    SQ_SINGLE_DOUBLE = /(\s?)'"(?=\w)/
    # A decade written as an abbreviation: the '80s.
    SQ_DECADE = /(\s?)'(?=\d\ds)/
    # Most opening quotes: whitespace, then a quote, then a word.
    SQ_OPENING = /(\s)('|")(?=\w)/
    # Most closing quotes: anything that can end a phrase, then a quote.
    SQ_CLOSING = /(#{SQ_CLOSE})('|")/
    # A possessive or a quote ending a phrase, as in: <i>Custer</i>'s Last Stand.
    SQ_TRAILING = /("|')(?=\s|s\b|$)/
    # Anything still undecided is an opening quote.
    SQ_ANY_SINGLE = /(.?)'/m
    SQ_ANY_DOUBLE = /(.?)"/m


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

    # Text content, where the three markup characters are escaped and quotes are
    # left alone. Every character an author writes goes through here, which is
    # what keeps html in a post from becoming html on the page. An attribute
    # value goes through `Escape.escape_html` instead, which escapes quotes too,
    # so that the value stays inside its delimiters whichever quote a template
    # chose.
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
    # code spans, then images, then links, then strong, then em.
    def self.inline(text)
      out = ::String.new
      # Plain characters are collected into a run rather than emitted one at a
      # time: the text transforms below work on runs, not on single characters.
      literal = ::String.new
      index = 0
      length = text.length
      # A link or an image needs a `]` after the `[` that opens it. Without one
      # ahead, matching_bracket would walk to the end of the text before giving
      # up, once per candidate, which is what made a paragraph of bare brackets
      # take time proportional to its length squared. Found once here instead.
      last_close = text.rindex("]")

      while index < length
        char = text[index]
        finish = nil

        if char == "`"
          finish = code_span(text, index)
        elsif char == "!" && last_close && index < last_close
          finish = image(text, index)
        elsif char == "[" && last_close && index < last_close
          finish = link(text, index)
        elsif char == "*" || char == "_"
          finish = emphasis(text, index)
        end

        if finish
          out << text_run(literal)
          literal = ::String.new
          out << finish[0]
          index = finish[1]
        else
          literal << char
          index += 1
        end
      end

      out << text_run(literal)
      out
    end

    # One run of plain characters, in the order the transforms have to happen:
    # the typographic ones first, since they read the characters around a quote,
    # then escaping, then the line breaks, which are markup and so cannot be
    # escaped afterwards.
    def self.text_run(run)
      return run if run.empty?

      escape_text(smart_quotes(dashes(run))).gsub("\n", "<br />\n")
    end

    # `---` is an em dash, `--` an en dash and `...` an ellipsis. Longest first,
    # so `----` comes out as an em dash followed by what is left over.
    def self.dashes(run)
      run.gsub("---", EM_DASH).gsub("--", EN_DASH).gsub("...", ELLIPSIS)
    end

    # Walks to each `"` or `'` and lets SQ_RULES decide which way it turns. The
    # rules may read the character before the quote, so matching starts there.
    def self.smart_quotes(run)
      out = ::String.new
      index = 0
      while (found = run.index(QUOTE_CHAR, index))
        # One character of lead-in, where there is one to spare and it has not
        # already been emitted.
        start = found > index ? found - 1 : found
        out << run[index...start]

        applied = apply_quote_rules(run, start)
        # The last two rules match any quote at all, so this only comes back
        # empty if the character found was not one, which cannot happen.
        break unless applied

        out << applied[0]
        index = applied[1]
      end
      out << run[index..].to_s
      out
    end

    # The first rule that matches exactly at `start`, applied. Returns
    # [replacement, index_after] or nil. The last two rules match any quote at
    # all, so nil only comes back when there was no quote to begin with.
    # Each rule is matched and tested in place rather than through a helper that
    # hands a match back: spinel cannot work out the type of a MatchData that
    # reached it as another method's return value, and a rule only counts when
    # it matches at the quote itself rather than somewhere further along.
    def self.apply_quote_rules(run, start)
      match = SQ_EMPHASIS.match(run, start)
      return [quote_for(:lquote1, match), match.end(0)] if match && match.begin(0) == start

      match = SQ_PUNCT_AHEAD.match(run, start)
      return [quote_for(:rquote1, match), match.end(0)] if match && match.begin(0) == start

      match = SQ_DOUBLE_SINGLE.match(run, start)
      return ["#{match[1]}#{LDQUO}#{LSQUO}", match.end(0)] if match && match.begin(0) == start

      match = SQ_SINGLE_DOUBLE.match(run, start)
      return ["#{match[1]}#{LSQUO}#{LDQUO}", match.end(0)] if match && match.begin(0) == start

      match = SQ_DECADE.match(run, start)
      return ["#{match[1]}#{RSQUO}", match.end(0)] if match && match.begin(0) == start

      match = SQ_OPENING.match(run, start)
      return ["#{match[1]}#{quote_for(:lquote2, match)}", match.end(0)] if match && match.begin(0) == start

      match = SQ_CLOSING.match(run, start)
      return ["#{match[1]}#{quote_for(:rquote2, match)}", match.end(0)] if match && match.begin(0) == start

      match = SQ_TRAILING.match(run, start)
      return [quote_for(:rquote1, match), match.end(0)] if match && match.begin(0) == start

      match = SQ_ANY_SINGLE.match(run, start)
      return ["#{match[1]}#{LSQUO}", match.end(0)] if match && match.begin(0) == start

      match = SQ_ANY_DOUBLE.match(run, start)
      return ["#{match[1]}#{LDQUO}", match.end(0)] if match && match.begin(0) == start

      nil
    end

    # Which of the four characters a rule produces: the shape comes from the
    # rule, the double-or-single from the quote the match captured.
    def self.quote_for(rule, match)
      double = (rule == :lquote1 || rule == :rquote1 ? match[1] : match[2]) == "\""

      case rule
      when :lquote1, :lquote2 then double ? LDQUO : LSQUO
      else double ? RDQUO : RSQUO
      end
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

    # `[label](href)` or `[label](href "title")`. A `[` with no matching `](...)`
    # is literal text, which is what a footnote marker like `[1]` relies on.
    def self.link(text, start)
      label_end = matching_bracket(text, start)
      return nil unless label_end && text[label_end + 1] == "("

      parsed = destination(text, label_end + 1)
      return nil unless parsed && safe_url?(parsed[0])

      href = parsed[0]
      title = parsed[1] ? " title=\"#{Escape.escape_html(parsed[1])}\"" : ""
      label = text[(start + 1)...label_end]
      rel = href.match?(ABSOLUTE) ? " rel=\"nofollow\"" : ""
      ["<a href=\"#{Escape.escape_html(href)}\"#{rel}#{title}>#{inline(label)}</a>", parsed[2]]
    end

    # `![alt](src)`. The label becomes the alt text literally: no inline markup
    # is recognised inside it, so `![a *b*](p.png)` keeps its asterisks, as
    # kramdown's did. A `!` that does not begin one is literal text.
    def self.image(text, start)
      return nil unless text[start + 1] == "["

      label_end = matching_bracket(text, start + 1)
      return nil unless label_end && text[label_end + 1] == "("

      parsed = destination(text, label_end + 1)
      return nil unless parsed && safe_url?(parsed[0])

      alt = text[(start + 2)...label_end]
      title = parsed[1] ? " title=\"#{Escape.escape_html(parsed[1])}\"" : ""
      ["<img src=\"#{Escape.escape_html(parsed[0])}\" alt=\"#{Escape.escape_html(alt)}\"#{title} />",
       parsed[2]]
    end

    # Whether a destination is one to emit. A url with no scheme is relative and
    # always fine; one that names a scheme has to name a known-harmless one. A
    # destination that fails here makes no link at all, so the markdown stays on
    # the page as the text it was written as.
    def self.safe_url?(url)
      match = SCHEME.match(url.gsub(IGNORED_IN_SCHEME, ""))
      match.nil? || SAFE_SCHEMES.include?(match[1].downcase)
    end

    # The `(href "title")` half of a link or an image, starting at the `(`.
    # Nested pairs are counted rather than stopping at the first `)`, so a url
    # like `…/Ruby_(programming_language)` survives intact.
    # Returns [href, title_or_nil, index_after_paren] or nil.
    def self.destination(text, start)
      depth = 0
      cursor = start
      while cursor < text.length
        char = text[cursor]
        if char == "("
          depth += 1
        elsif char == ")"
          depth -= 1
          break if depth.zero?
        end
        cursor += 1
      end
      return nil unless depth.zero?

      body = text[(start + 1)...cursor].strip
      # Two patterns rather than one with a backreference, which spinel does not
      # compile.
      match = TITLED_DOUBLE.match(body) || TITLED_SINGLE.match(body)
      return [body, nil, cursor + 1] unless match

      [match[1].strip, match[2], cursor + 1]
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

      !ALPHANUMERIC.include?(char)
    end

    # One document. Holds the ids already handed out, so a repeated heading gets
    # the `-1` suffix kramdown gave it.
    class Renderer
      def initialize(source)
        @source = source.gsub("\r\n", "\n")
        @used_ids = {}
      end

      def render
        blocks = []
        spaced = []
        parse(@source.split("\n", -1), blocks, spaced)
        return "" if blocks.empty?

        # kramdown kept the blank line that separated the title from the body,
        # and closed the document with a newline.
        leading = @source.start_with?("\n") ? "\n" : ""
        # A blank line that ended the source is kept. One trailing newline is
        # not a blank line.
        trailing = TRAILING_BLANK.match?(@source) ? "\n\n" : "\n"
        leading + join_blocks(blocks, spaced) + trailing
      end

      private

      # Two blocks are separated by a blank line only where the source had one
      # between them, which is the spacing kramdown's output carried.
      def join_blocks(blocks, spaced)
        out = ::String.new
        index = 0
        while index < blocks.length
          out << (spaced[index] ? "\n\n" : "\n") if index.positive?
          out << blocks[index]
          index += 1
        end
        out
      end

      # Appends to `blocks`, and to `spaced` one flag per block saying whether a
      # blank line came before it. Both are passed in rather than returned: a
      # method handing back a pair of arrays holding different types is more
      # than spinel can work out.
      def parse(lines, blocks, spaced)
        index = 0
        blank = false
        while index < lines.length
          line = lines[index]
          before = blocks.length
          if line.strip.empty?
            blank = true
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
          elsif (level = setext_level(lines, index, blank || blocks.empty?))
            blocks << heading(level, line.strip)
            index += 2
          else
            index = paragraph(blocks, lines, index)
          end

          added = blocks.length - before
          next unless added.positive?

          added.times { spaced << blank }
          blank = false
        end
      end

      # A line underlined with `=` or `-` is a heading, the character picking
      # the level. Only one line can be underlined, and only where a block
      # starts: a paragraph that has already taken a line goes on taking them,
      # so `One\nTwo\n===` is three lines of text rather than a heading.
      #
      # `opens` says the line follows a blank one or begins the document, which
      # kramdown also required — text pressed straight up against the block
      # before it is a paragraph, underlined or not.
      def setext_level(lines, index, opens)
        return nil unless opens

        line = lines[index]
        return nil if line.empty? || WHITESPACE.include?(line[0])
        return nil unless (match = SETEXT_UNDERLINE.match(lines[index + 1].to_s))

        match[1] == "=" ? 1 : 2
      end

      def heading(level, text)
        id = id_for(text)
        # kramdown emitted no attribute at all when nothing survived the rule.
        attribute = id.empty? ? "" : " id=\"#{Escape.escape_html(id)}\""
        "<h#{level}#{attribute}>#{Markdown.inline(text)}</h#{level}>"
      end

      # The GFM parser's rule, which is the one the gem's `input: "GFM"` used:
      # downcase, drop everything that is not a word character, dash or space,
      # then spaces and tabs to dashes. `\p{Word}` covers letters in any script,
      # so an accented heading keeps its letters while a dash, a curled quote or
      # an emoji falls out.
      def id_for(text)
        kept = plain_text(text).downcase.gsub(/[^\p{Word}\- \t]/, "")
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

      # A blank line ends a blockquote, and nothing else does: a line that has
      # dropped its `>` still belongs to the quote, which is how a wrapped
      # paragraph inside one reads and is where kramdown drew the line too.
      def blockquote(blocks, lines, index)
        body = []
        while index < lines.length && !lines[index].strip.empty?
          body << lines[index].sub(QUOTE, "")
          index += 1
        end

        inner = []
        inner_spaced = []
        parse(body, inner, inner_spaced)
        indented = inner.map { |block| indent(block) }
        blocks << "<blockquote>\n#{join_blocks(indented, inner_spaced)}\n</blockquote>"
        index
      end

      # Moves a nested block in by two. A line stays where it is when the
      # newline before it came from the text rather than from the structure:
      # either a `<br />` put it there, or it is inside a `<pre>`, where leading
      # whitespace is content.
      def indent(block)
        lines = block.split("\n", -1)
        out = ::String.new
        preformatted = false
        index = 0
        while index < lines.length
          line = lines[index]
          previous = index.positive? ? lines[index - 1] : ""
          out << "\n" if index.positive?
          out << "  " unless index.positive? && (preformatted || previous.end_with?("<br />"))
          out << line
          preformatted = true if line.include?("<pre")
          preformatted = false if line.include?("</pre>")
          index += 1
        end
        out
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
          # A line opening another block ends the paragraph. A horizontal rule
          # does not: once a paragraph is running, `---` under it is text, and
          # the typographic pass turns it into a dash. Only a rule that starts a
          # block of its own is one.
          break if body.any? && BLOCK_START.match(line)

          body << line
          index += 1
        end
        blocks << "<p>#{Markdown.inline(body.join("\n").strip)}</p>"
        index
      end
    end
  end
end
