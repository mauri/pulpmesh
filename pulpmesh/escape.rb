# frozen_string_literal: true

module Pulpmesh
  # Replaces CGI.escapeHTML, which spinel does not provide. Escapes the same
  # five characters, to the same entities, so template output is unchanged.
  #
  # Both quotes are escaped, so a value is safe inside either delimiter. This is
  # what the templates pass everything through and what the markdown renderer
  # writes attribute values with.
  module Escape
    def self.escape_html(text)
      text.to_s.gsub(/[&<>"']/) do |char|
        case char
        when "&" then "&amp;"
        when "<" then "&lt;"
        when ">" then "&gt;"
        when '"' then "&quot;"
        else "&#39;"
        end
      end
    end
  end
end
