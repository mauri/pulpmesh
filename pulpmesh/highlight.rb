# frozen_string_literal: true

module Pulpmesh
  # Stand-in highlighter: emits the same wrapper markup the gem's Rouge output
  # uses, with the code escaped and untokenized. Per-language tokenizers are not
  # written yet.
  module Highlight
    def self.render(code, language)
      body = Escape.escape_html(code)
      klass = language.to_s.empty? ? "" : "language-#{language} "
      "<div class=\"#{klass}highlighter-rouge\"><div class=\"highlight\">" \
        "<pre class=\"highlight\"><code>#{body}</code></pre></div></div>"
    end
  end
end
