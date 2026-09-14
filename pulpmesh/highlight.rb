# frozen_string_literal: true

module Pulpmesh
  # Hand-rolled highlighting for the two languages the blog uses, emitting the
  # class names Rouge emitted into the same wrapper markup, so the snapshotted
  # syntax.css and the blog's own _styles.css keep working untouched.
  #
  # This is not a reimplementation of Rouge's lexers. It recognises the same
  # kinds of token and labels them the same way; where Rouge's lexer splits a
  # run differently, the colouring is equivalent but the markup is not identical.
  module Highlight
    SHELL = %w[sh bash shell zsh console].freeze
    RUBY = %w[ruby rb].freeze

    # Rouge's shell lexer word lists, copied so the same words get the same
    # class. `case` is a keyword there too, via its own rule.
    SHELL_KEYWORDS = %w[
      if fi else while do done for then return function
      select continue until esac elif in case
    ].freeze

    SHELL_BUILTINS = %w[
      alias bg bind break builtin caller cd command compgen
      complete declare dirs disown enable eval exec exit
      export false fc fg getopts hash help history jobs let
      local logout mapfile popd pushd pwd read readonly set
      shift shopt source suspend test time times trap true type
      typeset ulimit umask unalias unset wait
      cat tac nl od base32 base64 fmt pr fold head tail split csplit
      wc sum cksum b2sum md5sum sha1sum sha224sum sha256sum sha384sum
      sha512sum sort shuf uniq comm ptx tsort cut paste join tr expand
      unexpand ls dir vdir dircolors cp dd install mv rm shred link ln
      mkdir mkfifo mknod readlink rmdir unlink chown chgrp chmod touch
      df du stat sync truncate echo printf yes expr tee basename dirname
      pathchk mktemp realpath stty printenv tty id logname whoami
      groups users who date arch nproc uname hostname hostid uptime chcon
      runcon chroot env nice nohup stdbuf timeout kill sleep factor numfmt
      seq tar grep sudo awk sed gzip gunzip
    ].freeze

    RUBY_KEYWORDS = %w[
      def end class module if elsif else unless while until for do then
      begin rescue ensure raise return yield next break redo retry case when
      in self nil true false and or not super alias defined? __method__ lambda
      proc loop
    ].freeze

    RUBY_BUILTINS = %w[
      puts print p pp require require_relative attr_reader attr_writer
      attr_accessor include extend prepend new freeze raise format sprintf
      gets loop catch throw
    ].freeze

    def self.render(code, language)
      name = language.to_s.downcase
      tokens = if SHELL.include?(name)
                 Shell.new(code).tokens
               elsif RUBY.include?(name)
                 Ruby.new(code).tokens
               end

      # An unrecognised language is plain escaped text in a labelled <code>,
      # which is what kramdown emitted when Rouge had no lexer for it.
      unless tokens
        return "<pre><code class=\"language-#{Escape.escape_html(language)}\">" \
               "#{Markdown.escape_text(code)}</code></pre>"
      end

      "<div class=\"language-#{Escape.escape_html(language)} highlighter-rouge\">" \
        "<div class=\"highlight\"><pre class=\"highlight\"><code>#{join(tokens)}</code></pre></div></div>"
    end

    # Adjacent tokens sharing a class are merged, which is what keeps the output
    # close to Rouge's runs rather than one span per character.
    def self.join(tokens)
      out = ::String.new
      index = 0
      while index < tokens.length
        css = tokens[index][0]
        # `dup` rather than `String.new(...)`: spinel fails to compile
        # String.new applied to a poly value such as a nested array element.
        text = tokens[index][1].dup
        index += 1
        while index < tokens.length && tokens[index][0] == css
          text << tokens[index][1]
          index += 1
        end

        escaped = Markdown.escape_text(text)
        out << (css ? "<span class=\"#{css}\">#{escaped}</span>" : escaped)
      end
      out
    end

    # Shared character-walking machinery. A subclass fills in `step`, pushing
    # [css_class_or_nil, text] pairs.
    class Lexer
      WORD = /[A-Za-z0-9_]/

      def initialize(source)
        @source = source.to_s
        @pos = 0
        @tokens = []
      end

      def tokens
        step while @pos < @source.length
        @tokens
      end

      private

      attr_reader :source

      def push(css, text)
        @tokens << [css, text] unless text.empty?
      end

      def peek(offset = 0)
        @source[@pos + offset]
      end

      def word?(char)
        !char.nil? && char.match?(WORD)
      end

      # Everything up to (not including) the next newline.
      def rest_of_line
        stop = @source.index("\n", @pos) || @source.length
        text = @source[@pos...stop]
        @pos = stop
        text
      end

      def take_while
        start = @pos
        @pos += 1 while @pos < @source.length && yield(@source[@pos])
        @source[start...@pos]
      end
    end

    class Shell < Lexer
      # Rouge's shell lexer marks only these. A single `|` or `<` is plain text
      # there, and adjacent operators (`}==`) merge into one span downstream.
      OPERATORS = ["&&", "||", "=", ">", "(", ")", "{", "}", "[", "]", "!"].freeze

      def initialize(source)
        super
        @command_position = true
      end

      private

      def step
        char = peek

        if char == "\n"
          @pos += 1
          @command_position = true
          push(nil, "\n")
        elsif char == " " || char == "\t"
          push(nil, take_while { |c| c == " " || c == "\t" })
        elsif char == "#"
          push("c", rest_of_line)
        elsif char == "$" && peek(1) == " " && @command_position
          # The `$ ` of a pasted prompt, which Rouge labels as a variable.
          @pos += 2
          push("nv", "$ ")
        elsif char == "$"
          variable
        elsif char == "'"
          push("s1", quoted("'"))
        elsif char == '"'
          double_quoted
        elsif char == ";"
          @pos += 1
          @command_position = true
          push("p", ";")
        elsif (operator = operator_at)
          @pos += operator.length
          @command_position = true if operator != "=" && operator != "}"
          push("o", operator)
        elsif char == "-"
          push("nt", take_while { |c| c != " " && c != "\t" && c != "\n" && c != ";" })
        elsif word?(char)
          bare_word
        else
          @pos += 1
          push(nil, char)
        end
      end

      def operator_at
        OPERATORS.find { |op| @source[@pos, op.length] == op }
      end

      def variable
        start = @pos
        @pos += 1
        if peek == "("
          # `$( ... )` — the delimiters are the interpolation, the inside is code.
          @pos += 1
          push("si", "$(")
          push_inner_until(")")
          return
        end

        if peek == "{"
          @pos += 1
          @pos += 1 while @pos < @source.length && peek != "}"
          @pos += 1 if @pos < @source.length
        else
          @pos += 1 while @pos < @source.length && word?(peek)
        end
        push("nv", @source[start...@pos])
      end

      # The body of a command substitution is lexed as shell, then closed.
      def push_inner_until(closer)
        depth = 0
        while @pos < @source.length
          char = peek
          if char == closer && depth.zero?
            @pos += 1
            push("si", closer)
            return
          end
          depth += 1 if char == "("
          depth -= 1 if char == ")"
          @command_position = true if char == "\n"
          step
        end
      end

      def quoted(delimiter)
        start = @pos
        @pos += 1
        @pos += 1 while @pos < @source.length && peek != delimiter
        @pos += 1 if @pos < @source.length
        @command_position = false
        @source[start...@pos]
      end

      # A double-quoted string is one s2 run, interrupted by any variable or
      # command substitution inside it, exactly as Rouge splits it.
      def double_quoted
        @pos += 1
        push("s2", '"')
        buffer = ::String.new
        while @pos < @source.length
          char = peek
          if char == '"'
            @pos += 1
            buffer << '"'
            break
          elsif char == "$" && (word?(peek(1)) || peek(1) == "{" || peek(1) == "(")
            push("s2", buffer) unless buffer.empty?
            buffer = ::String.new
            variable
          else
            buffer << char
            @pos += 1
          end
        end
        push("s2", buffer) unless buffer.empty?
        @command_position = false
      end

      def bare_word
        # Rouge's catch-all text rule swallows these mid-run, so `2>/dev/null`
        # and `/dev/sdb|grep` stay one plain token; only at the start of a token
        # does `>` reach the operator rule.
        text = take_while { |c| c.match?(WORD) || c == "." || c == "-" || c == "/" || c == "|" || c == ">" }

        if SHELL_KEYWORDS.include?(text)
          @command_position = true
          return push("k", text + trailing_space)
        end

        @command_position = false
        return push("nv", text) if peek == "="
        return push("nb", text + trailing_space) if SHELL_BUILTINS.include?(text)

        push(nil, text)
      end

      # Rouge matches a keyword as `\b(KEYWORD)\s*\b`, so the whitespace after
      # it joins the same span — but only when a word follows, since otherwise
      # there is no trailing word boundary for the pattern to land on.
      def trailing_space
        cursor = @pos
        cursor += 1 while cursor < @source.length && (@source[cursor] == " " || @source[cursor] == "\t" || @source[cursor] == "\n")
        return "" if cursor == @pos || !word?(@source[cursor])

        space = @source[@pos...cursor]
        @pos = cursor
        space
      end
    end

    class Ruby < Lexer
      OPERATORS = ["<=>", "===", "**=", "||=", "&&=", "==", "!=", "<=", ">=",
                   "<<", ">>", "=>", "->", "::", "+=", "-=", "*=", "/=", "%=",
                   "=", "+", "-", "*", "/", "%", "<", ">", "!", "&", "|", "^",
                   "~", "?"].freeze
      PUNCTUATION = ["(", ")", "[", "]", "{", "}", ",", ";", "."].freeze

      def initialize(source)
        super
        @after_def = false
      end

      private

      def step
        char = peek

        if char == "\n" || char == " " || char == "\t"
          push(nil, take_while { |c| c == "\n" || c == " " || c == "\t" })
        elsif char == "#"
          push("c1", rest_of_line)
        elsif char == '"'
          double_quoted
        elsif char == "'"
          push("s1", quoted("'"))
        elsif char == ":" && word?(peek(1))
          start = @pos
          @pos += 1
          @pos += 1 while @pos < @source.length && (word?(peek) || peek == "?" || peek == "!")
          push("ss", @source[start...@pos])
        elsif char == "@"
          start = @pos
          @pos += 1
          klass = peek == "@" ? "vc" : "vi"
          @pos += 1 if peek == "@"
          @pos += 1 while @pos < @source.length && word?(peek)
          push(klass, @source[start...@pos])
        elsif char == "$"
          start = @pos
          @pos += 1
          @pos += 1 while @pos < @source.length && word?(peek)
          push("vg", @source[start...@pos])
        elsif char >= "0" && char <= "9"
          number
        elsif word?(char)
          bare_word
        elsif PUNCTUATION.include?(char)
          @pos += 1
          push("p", char)
        elsif (operator = operator_at)
          @pos += operator.length
          push("o", operator)
        else
          @pos += 1
          push(nil, char)
        end
      end

      def operator_at
        OPERATORS.find { |op| @source[@pos, op.length] == op }
      end

      def number
        text = take_while { |c| c.match?(/[0-9_.eE]/) }
        push(text.include?(".") ? "mf" : "mi", text)
      end

      def quoted(delimiter)
        start = @pos
        @pos += 1
        while @pos < @source.length && peek != delimiter
          @pos += peek == "\\" ? 2 : 1
        end
        @pos += 1 if @pos < @source.length
        @source[start...@pos]
      end

      # `#{ ... }` inside a double-quoted string is `si` around plain contents.
      def double_quoted
        @pos += 1
        push("s2", '"')
        buffer = ::String.new
        while @pos < @source.length
          char = peek
          if char == '"'
            @pos += 1
            buffer << '"'
            break
          elsif char == "\\"
            buffer << @source[@pos, 2].to_s
            @pos += 2
          elsif char == "#" && peek(1) == "{"
            push("s2", buffer) unless buffer.empty?
            buffer = ::String.new
            interpolation
          else
            buffer << char
            @pos += 1
          end
        end
        push("s2", buffer) unless buffer.empty?
      end

      def interpolation
        @pos += 2
        push("si", '#{')
        depth = 0
        while @pos < @source.length
          char = peek
          if char == "}" && depth.zero?
            @pos += 1
            push("si", "}")
            return
          end
          depth += 1 if char == "{"
          depth -= 1 if char == "}"
          step
        end
      end

      def bare_word
        text = take_while { |c| c.match?(WORD) }
        text += take_while { |c| c == "?" || c == "!" } if peek == "?" || peek == "!"

        css = if @after_def
                "nf"
              elsif RUBY_KEYWORDS.include?(text)
                "k"
              elsif RUBY_BUILTINS.include?(text)
                "nb"
              elsif text[0] >= "A" && text[0] <= "Z"
                "no"
              end
        @after_def = text == "def"
        push(css, text)
      end
    end
  end
end
