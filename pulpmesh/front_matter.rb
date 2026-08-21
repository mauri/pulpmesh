# frozen_string_literal: true

module Pulpmesh
  # Reads the optional `---` fenced header at the top of a markdown file.
  #
  # Deliberately not YAML: the supported shape is flat `key: value` pairs, which
  # keeps unquoted apostrophes and colons-in-values working without a parser that
  # would reject them.
  module FrontMatter
    FENCE = /\A---[ \t]*\r?\n(.*?)^---[ \t]*\r?\n?/m

    # Returns [hash, body].
    def self.split(text)
      match = FENCE.match(text)
      return [{}, text] unless match

      [parse(match[1]), match.post_match]
    end

    def self.parse(block)
      block.each_line.with_object({}) do |line, data|
        stripped = line.strip
        next if stripped.empty? || stripped.start_with?("#")

        key, value = stripped.split(":", 2)
        next if value.nil?

        data[key.strip.downcase] = coerce(value.strip)
      end
    end

    def self.coerce(value)
      case value
      when /\A\[(.*)\]\z/ then list($1)
      when /\A"(.*)"\z/m, /\A'(.*)'\z/m then $1
      when "true" then true
      when "false" then false
      else value
      end
    end

    # Accepts what `coerce` may have produced for a list-ish key, in either the
    # `[a, b]` or the bare `a, b` spelling.
    #
    # Guard clauses rather than a `case`: spinel miscompiles a `case` branch that
    # yields an empty array literal when another branch yields a non-empty one,
    # handing back nil instead of [].
    def self.list(value)
      return [] if value.nil?
      return value if value.is_a?(Array)

      value.to_s.split(",").map { |item| item.strip }.reject { |item| item.empty? }
    end
  end
end
