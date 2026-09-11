# frozen_string_literal: true

module Pulpmesh
  # Blog-wide metadata, read from `_pulpmesh.md` in the source folder. Its body
  # becomes the intro section on the index page.
  class Config
    CONFIG_FILE = "_pulpmesh.md"
    STYLESHEET = "_styles.css"

    DEFAULT_KEYWORDS = "blog, blogging, write, writing, hackers, developers, terminal"
    DEFAULT_FOOTER = "Published with [![pulpmesh](pulpmesh-logo.svg)](https://pulpme.sh)"

    attr_reader :source, :data, :intro_html

    def initialize(source, base_url: nil)
      @source = source
      raw = File.exist?(config_path) ? File.read(config_path) : ""
      @data, body = FrontMatter.split(raw)
      @data["base_url"] = base_url if base_url
      @intro_html = body.strip.empty? ? nil : Markdown.render(body)
    end

    def config_path
      File.join(source, CONFIG_FILE)
    end

    def title
      data["title"] || File.basename(source)
    end

    def description
      data["description"].to_s
    end

    def keywords
      data["keywords"] || DEFAULT_KEYWORDS
    end

    # One line of markdown, rendered as a line rather than as a document, so it
    # carries a link or an image without being wrapped in a paragraph.
    def footer
      Markdown.inline(data.fetch("footer", DEFAULT_FOOTER))
    end

    def favicon
      data["favicon"]
    end

    def card_image
      data["card_image"]
    end

    def base_url
      url = data["base_url"].to_s.strip
      url.empty? ? nil : url.chomp("/")
    end

    # Absolute URLs are only needed by the metadata tags and the feed. Without a
    # base_url the site still builds; those bits are left out instead.
    def url_for(path = nil)
      return nil unless base_url

      path.to_s.empty? ? base_url : "#{base_url}/#{path.to_s.delete_prefix("/")}"
    end

    def stylesheet_path
      File.join(source, STYLESHEET)
    end

    def styles?
      data.fetch("with_styles", true) && File.exist?(stylesheet_path)
    end
  end
end
