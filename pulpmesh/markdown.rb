# frozen_string_literal: true

module Pulpmesh
  # The markdown the blog actually uses, rendered to the same html kramdown
  # produced: ATX and setext headings with generated ids, fenced code, lists,
  # blockquotes, horizontal rules and paragraphs, over inline code, links,
  # images, strong and em.
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
    QUOTE = /\A[ \t]{0,3}>[ \t]?/
    BULLET = /\A[ \t]{0,3}[-*+][ \t]+(.*)\z/
    ORDERED = /\A[ \t]{0,3}\d+\.[ \t]+(.*)\z/
    BLOCK_START = /\A(?:\#{1,6}[ \t]|```|~~~|[ \t]{0,3}>|[ \t]{0,3}[-*+][ \t]|[ \t]{0,3}\d+\.[ \t])/
    ABSOLUTE = %r{\A[a-z][a-z0-9+.-]*://}i

    # The bounds of a decodable numeric character reference.
    MAX_CODE_POINT = 0x10FFFF
    SURROGATE_FIRST = 0xD800
    SURROGATE_LAST = 0xDFFF

    # The optional `"title"` trailing a link or image destination.
    TITLED_DOUBLE = /\A(.*?)[ \t]+"(.*)"\z/
    TITLED_SINGLE = /\A(.*?)[ \t]+'(.*)'\z/

    # Elements that never take a closing tag; they are emitted self-closed and
    # never pushed onto the open-tag stack.
    VOID = %w[area base br col embed hr img input link meta param source track wbr].freeze

    # A line opening one of these starts a raw html block rather than a
    # paragraph, and is passed through untouched to its matching close.
    BLOCK_LEVEL = %w[
      address article aside audio blockquote canvas dd details dialog div dl dt
      fieldset figcaption figure footer form h1 h2 h3 h4 h5 h6 header hgroup hr
      iframe li main nav noscript ol p pre script section style table tbody td
      tfoot th thead tr ul video
    ].freeze

    TAG_NAME = /\A[A-Za-z][A-Za-z0-9-]*\z/

    # Character sets the tag scanner walks one character at a time. A string
    # include? beats building a match against a regex for every character.
    WHITESPACE = " \t\r\n\f\v"
    ALPHANUMERIC = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    TAG_NAME_CHARS = "#{ALPHANUMERIC}-"
    ATTRIBUTE_NAME_CHARS = "#{ALPHANUMERIC}:_.-"

    # Elements whose content is raw text rather than markup. Together with the
    # void elements these are the blocks kramdown closed with a blank line.
    RAW_TEXT = %w[script style].freeze

    EM_DASH = "—"
    EN_DASH = "–"
    ELLIPSIS = "…"
    LDQUO = "“"
    RDQUO = "”"
    LSQUO = "‘"
    RSQUO = "’"

    QUOTE_CHAR = /["']/

    # Unicode's General Punctuation block, which holds every character the
    # typographic pass above can produce. A heading id drops these.
    PUNCTUATION_BLOCK = (0x2000..0x206F).freeze

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

    # Text content, where only the three markup characters are escaped. Quotes
    # are left alone, as kramdown left them. `unescape_text` reverses this, and
    # is the only thing that may: an attribute value goes through
    # `Escape.escape_html`, which escapes quotes too, so that the value stays
    # inside its delimiters whichever quote a template chose.
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
      open_tags = []
      out = scan(text, open_tags)
      # Anything still open at the end of the block is closed here, innermost
      # first, as kramdown's html parser does.
      while (name = open_tags.pop)
        out << "</#{name}>"
      end
      out
    end

    def self.scan(text, open_tags)
      out = ::String.new
      # Plain characters are collected into a run rather than emitted one at a
      # time: the text transforms work on runs, not on single characters. A run
      # never spans a tag, so whether it sits inside a raw html element is
      # decided once, when its first character arrives.
      literal = ::String.new
      bare = open_tags.empty?
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
          finish = link(text, index, open_tags)
        elsif char == "*" || char == "_"
          finish = emphasis(text, index, open_tags)
        elsif char == "<"
          finish = html(text, index, open_tags)
        elsif char == "&"
          finish = entity(text, index)
        end

        if finish
          out << text_run(literal, bare)
          literal = ::String.new
          out << finish[0]
          index = finish[1]
        else
          bare = open_tags.empty? if literal.empty?
          literal << char
          index += 1
        end
      end

      out << text_run(literal, bare)
      out
    end

    # One run of plain characters, in the order the transforms have to happen:
    # the typographic ones first, since they read the characters around a quote,
    # then escaping, then the line breaks, which are markup and so cannot be
    # escaped afterwards.
    #
    # `bare` is false inside a raw html element, where kramdown left line
    # endings alone.
    def self.text_run(run, bare)
      return run if run.empty?

      escaped = escape_text(smart_quotes(dashes(run)))
      bare ? escaped.gsub("\n", "<br />\n") : escaped
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

    # `<` starts raw html only when what follows really is a tag or a comment.
    # Anything else — `5 < 6`, `a <3 b`, a stray `</b>` — is literal text.
    # Returns [html, next_index] or nil.
    def self.html(text, start, open_tags)
      return comment(text, start) if text[start, 4] == "<!--"

      cursor = start + 1
      closing = text[cursor] == "/"
      cursor += 1 if closing

      name_start = cursor
      cursor += 1 while cursor < text.length && TAG_NAME_CHARS.include?(text[cursor])
      name = text[name_start...cursor].downcase
      return nil if name.empty? || !name.match?(TAG_NAME)

      if closing
        return nil unless text[cursor] == ">"
        # Only the innermost open tag can be closed; anything else is text, so a
        # crossed pair like `<b><i>x</b>` leaves the `</b>` visible.
        return nil unless open_tags.last == name

        open_tags.pop
        return ["</#{name}>", cursor + 1]
      end

      parsed = attributes(text, cursor)
      return nil unless parsed

      rendered = parsed[0]
      finish = parsed[1]
      self_closed = parsed[2]

      if VOID.include?(name) || self_closed
        ["<#{name}#{rendered} />", finish]
      else
        open_tags.push(name)
        ["<#{name}#{rendered}>", finish]
      end
    end

    def self.comment(text, start)
      finish = text.index("-->", start + 4)
      return nil unless finish

      [text[start..(finish + 2)], finish + 3]
    end

    # Reads attributes up to the closing `>`, normalising each to
    # `name="value"`. Returns [rendered, index_after_gt, self_closed] or nil if
    # the tag never closes.
    #
    # Normalising is not sanitising. Nothing here drops a tag, an attribute or a
    # url: `onerror=alert(1)` comes out as a tidy `onerror="alert(1)"` and works.
    # Raw html is passed through by design, on the assumption that the markdown
    # was written by whoever owns the blog. Do not reach for this on input from
    # anyone else.
    def self.attributes(text, start)
      out = ::String.new
      cursor = start
      self_closed = false

      while cursor < text.length
        cursor += 1 while cursor < text.length && WHITESPACE.include?(text[cursor])

        if text[cursor] == "/" && text[cursor + 1] == ">"
          return [out, cursor + 2, true]
        elsif text[cursor] == ">"
          return [out, cursor + 1, self_closed]
        end

        name_start = cursor
        cursor += 1 while cursor < text.length && ATTRIBUTE_NAME_CHARS.include?(text[cursor])
        return nil if cursor == name_start

        name = text[name_start...cursor].downcase
        cursor += 1 while cursor < text.length && WHITESPACE.include?(text[cursor])

        value = ""
        if text[cursor] == "="
          cursor += 1
          cursor += 1 while cursor < text.length && WHITESPACE.include?(text[cursor])
          quote = text[cursor]
          if quote == "\"" || quote == "'"
            cursor += 1
            value_start = cursor
            cursor += 1 while cursor < text.length && text[cursor] != quote
            return nil if cursor >= text.length

            value = text[value_start...cursor]
            cursor += 1
          else
            value_start = cursor
            cursor += 1 while cursor < text.length && !WHITESPACE.include?(text[cursor]) && text[cursor] != ">"
            value = text[value_start...cursor]
          end
        end

        # A bare attribute becomes `name=""`, matching kramdown's normalisation.
        out << " #{name}=\"#{Escape.escape_html(decode_entities(value))}\""
      end
      nil
    end

    # `&name;`, `&#123;` or `&#x1F;`. An entity that is not recognised is left
    # for the caller to escape, so `&bogus;` renders as literal text.
    # Returns [text, next_index] or nil.
    def self.entity(text, start)
      finish = text.index(";", start + 1)
      return nil if finish.nil? || finish == start + 1 || finish - start > 12

      body = text[(start + 1)...finish]

      if body.start_with?("#")
        digits = body[1..].to_s
        code = if digits.start_with?("x") || digits.start_with?("X")
                 hex = digits[1..].to_s
                 hex.match?(/\A[0-9a-fA-F]+\z/) ? hex.to_i(16) : nil
               elsif digits.match?(/\A[0-9]+\z/)
                 digits.to_i
               end
        # `&#0;` is left as literal text rather than decoded: spinel's strings
        # are NUL-terminated at the C boundary, so an embedded NUL would
        # truncate the document.
        return nil if code.nil? || code.zero?

        # Past the end of unicode, or one half of a surrogate pair, names no
        # character. `pack("U")` would raise or build a byte sequence that
        # raises the next time the string is read, so these stay literal too.
        return nil if code > MAX_CODE_POINT || (code >= SURROGATE_FIRST && code <= SURROGATE_LAST)

        # `pack("U")` rather than `chr("UTF-8")`: spinel supports Integer#chr
        # only without an encoding argument, which limits it to ascii.
        return [escape_text([code].pack("U")), finish + 1]
      end

      code_point = ENTITIES[body]
      return nil unless code_point

      [escape_text([code_point].pack("U")), finish + 1]
    end

    # Entities inside an attribute value are decoded before the value is
    # re-escaped, so `&amp;` survives as `&amp;` rather than `&amp;amp;`.
    def self.decode_entities(value)
      out = ::String.new
      index = 0
      while index < value.length
        if value[index] == "&"
          finish = entity(value, index)
          if finish
            out << unescape_text(finish[0])
            index = finish[1]
            next
          end
        end
        out << value[index]
        index += 1
      end
      out
    end

    def self.unescape_text(text)
      text.gsub("&lt;", "<").gsub("&gt;", ">").gsub("&amp;", "&")
    end

    # `[label](href)` or `[label](href "title")`. A `[` with no matching `](...)`
    # is literal text, which is what a footnote marker like `[1]` relies on.
    def self.link(text, start, open_tags)
      label_end = matching_bracket(text, start)
      return nil unless label_end && text[label_end + 1] == "("

      parsed = destination(text, label_end + 1)
      return nil unless parsed

      href = parsed[0]
      title = parsed[1] ? " title=\"#{Escape.escape_html(parsed[1])}\"" : ""
      label = text[(start + 1)...label_end]
      rel = href.match?(ABSOLUTE) ? " rel=\"nofollow\"" : ""
      ["<a href=\"#{Escape.escape_html(href)}\"#{rel}#{title}>#{scan(label, open_tags)}</a>", parsed[2]]
    end

    # `![alt](src)`. The label becomes the alt text literally: no inline markup
    # is recognised inside it, so `![a *b*](p.png)` keeps its asterisks, as
    # kramdown's did. A `!` that does not begin one is literal text.
    def self.image(text, start)
      return nil unless text[start + 1] == "["

      label_end = matching_bracket(text, start + 1)
      return nil unless label_end && text[label_end + 1] == "("

      parsed = destination(text, label_end + 1)
      return nil unless parsed

      alt = text[(start + 2)...label_end]
      title = parsed[1] ? " title=\"#{Escape.escape_html(parsed[1])}\"" : ""
      ["<img src=\"#{Escape.escape_html(parsed[0])}\" alt=\"#{Escape.escape_html(alt)}\"#{title} />",
       parsed[2]]
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
    def self.emphasis(text, start, open_tags)
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
        return ["<#{tag}>#{scan(content, open_tags)}</#{tag}>", found + marker.length]
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
        @raw_html_last = false
      end

      def render
        blocks = parse(@source.split("\n", -1))
        return "" if blocks.empty?

        # kramdown kept the blank line that separated the title from the body,
        # and closed the document with a newline.
        leading = @source.start_with?("\n") ? "\n" : ""
        # kramdown closed a document ending in a raw html block with a blank
        # line rather than a single newline.
        trailing = @raw_html_last ? "\n\n" : "\n"
        leading + blocks.join("\n\n") + trailing
      end

      private

      def parse(lines)
        blocks = []
        index = 0
        while index < lines.length
          line = lines[index]
          @raw_html_last = false unless line.strip.empty?
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
          elsif (tag = block_html_tag(line))
            index = block_html(blocks, lines, index, tag)
          elsif QUOTE.match(line)
            index = blockquote(blocks, lines, index)
          elsif BULLET.match(line)
            index = list(blocks, lines, index, "ul", BULLET)
          elsif ORDERED.match(line)
            index = list(blocks, lines, index, "ol", ORDERED)
          elsif (level = setext_level(lines, index))
            blocks << heading(level, line.strip)
            index += 2
          else
            index = paragraph(blocks, lines, index)
          end
        end
        blocks
      end

      # A line underlined with `=` or `-` is a heading, the character picking
      # the level. Only one line can be underlined, and only where a block
      # starts: a paragraph that has already taken a line goes on taking them,
      # so `One\nTwo\n===` is three lines of text rather than a heading.
      def setext_level(lines, index)
        line = lines[index]
        return nil if line.empty? || WHITESPACE.include?(line[0])
        return nil unless (match = SETEXT_UNDERLINE.match(lines[index + 1].to_s))

        match[1] == "=" ? 1 : 2
      end

      # A line opening a block-level element starts a raw html block. Only the
      # opening tag has to be on the line; the rest is passed through untouched.
      def block_html_tag(line)
        match = /\A<([A-Za-z][A-Za-z0-9-]*)(?:[ \t>\/]|\z)/.match(line)
        return nil unless match

        name = match[1].downcase
        BLOCK_LEVEL.include?(name) ? name : nil
      end

      # Consumes to the matching close, counting nested opens of the same name so
      # a `<div>` inside a `<div>` does not end the block early. A void element,
      # a self-closed tag, or a block that never closes ends at the line itself.
      def block_html(blocks, lines, index, tag)
        first = lines[index]
        if VOID.include?(tag) || first.rstrip.end_with?("/>")
          # Normalised through the same tag parser the inline pass uses, so a
          # block `<hr>` comes out `<hr />` as kramdown wrote it.
          parsed = Markdown.html(first.rstrip, 0, [])
          blocks << (parsed && parsed[1] == first.rstrip.length ? parsed[0] : first.rstrip)
          @raw_html_last = true
          return index + 1
        end

        body = []
        depth = 0
        while index < lines.length
          line = lines[index]
          depth += count_tag(line, "<#{tag}")
          depth -= count_tag(line, "</#{tag}")
          body << line
          index += 1
          break if depth <= 0
        end

        blocks << body.join("\n").rstrip
        @raw_html_last = RAW_TEXT.include?(tag)
        index
      end

      # Occurrences of a literal tag opener, requiring a delimiter after the
      # name so `<div` does not also match `<divider`.
      def count_tag(line, opener)
        count = 0
        cursor = 0
        while (found = line.index(opener, cursor))
          after = line[found + opener.length]
          count += 1 if after.nil? || after == ">" || after == " " || after == "\t" || after == "/"
          cursor = found + opener.length
        end
        count
      end

      def heading(level, text)
        id = id_for(text)
        # kramdown emitted no attribute at all when nothing survived the rule.
        attribute = id.empty? ? "" : " id=\"#{Escape.escape_html(id)}\""
        "<h#{level}#{attribute}>#{Markdown.inline(text)}</h#{level}>"
      end

      # The GFM parser's rule, which is the one the gem's `input: "GFM"` used:
      # downcase, drop everything that is not a word character, dash or space,
      # then spaces and tabs to dashes. `\w` rather than `\p{Word}`, which
      # spinel compiles to a pattern that matches nothing.
      def id_for(text)
        # `\w` is ASCII-only, so non-ascii is decided by code point. That is an
        # approximation of \p{Word}: it keeps accented letters, and drops
        # General Punctuation, which is where the quotes, dashes and ellipsis
        # the typographic pass produces all live. A non-ascii symbol outside
        # that block is still kept where kramdown would have dropped it.
        kept = plain_text(text).downcase.gsub(/[^\w\- \t]/) do |char|
          char.ord >= 128 && !PUNCTUATION_BLOCK.include?(char.ord) ? char : ""
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
