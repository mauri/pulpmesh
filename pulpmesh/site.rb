# frozen_string_literal: true

module Pulpmesh
  # Turns a folder of markdown into a folder of html.
  class Site
    OUTPUT_DIR = "_site"

    # Left in the output directory by every build. A later build looks for it
    # before deleting anything, so a directory pulpmesh did not write is never
    # removed.
    OUTPUT_MARKER = ".pulpmesh-output"
    MARKER_TEXT = "Written by pulpmesh. This directory is deleted and rebuilt on every build.\n"

    attr_reader :source, :output, :config, :posts, :warnings

    def initialize(source: Dir.pwd, output: nil, base_url: nil)
      @source = File.expand_path(source)
      raise Error, "not a directory: #{source}" unless File.directory?(@source)

      @output = File.expand_path(output || File.join(@source, OUTPUT_DIR))
      refuse_unsafe_output
      @config = Config.new(@source, base_url: base_url)
      @warnings = []
      @posts = collect_posts
    end

    def build
      FSUtil.rm_rf(output)
      FSUtil.mkdir_p(output)
      write(OUTPUT_MARKER, MARKER_TEXT)

      posts.each { |post| write(post.filename, render("post.html.erb", post: post)) }
      write("index.html", render("index.html.erb"))
      write("404.html", render("404.html.erb"))

      if config.base_url
        write("rss.xml", render("rss.xml.erb"))
      else
        warnings << "no base_url in #{Config::CONFIG_FILE}: skipping rss.xml and the og:/twitter: url tags"
      end

      write_assets
      self
    end

    private

    # A build opens by deleting the whole output directory, so the path has to
    # be one pulpmesh may delete: not the source folder, not a folder the source
    # sits inside, not the home directory, and not somewhere already holding
    # files that no previous build put there.
    def refuse_unsafe_output
      raise Error, "output directory is the source directory: #{output}" if output == source
      raise Error, "output directory contains the source directory: #{output}" if inside?(source, output)
      raise Error, "output directory is the home directory: #{output}" if output == File.expand_path(Dir.home)

      return unless Dir.exist?(output)
      return if Dir.children(output).empty?
      return if File.exist?(File.join(output, OUTPUT_MARKER))

      raise Error, "refusing to delete an output directory pulpmesh did not write: #{output}"
    end

    # Whether child sits somewhere under parent. Both paths are already expanded,
    # and the separator keeps a shared prefix from counting: `/srv/blog-old` is
    # not inside `/srv/blog`.
    def inside?(child, parent)
      prefix = parent.end_with?("/") ? parent : "#{parent}/"
      child.start_with?(prefix)
    end

    def collect_posts
      files = Dir.glob(File.join(source, "*.md")).sort.reject { |path| Post.draft?(path) }
      posts = files.map { |path| Post.new(path) }
      detect_collisions(posts)
      posts.sort_by { |post| [-post.date.to_i, post.title] }
    end

    def detect_collisions(posts)
      posts.group_by(&:slug).each do |slug, group|
        next if group.size == 1

        sources = group.map { |post| File.basename(post.path) }.join(" and ")
        raise Error, "#{sources} both publish as #{slug}.html"
      end
    end

    def write(name, contents)
      File.write(File.join(output, name), contents)
    end

    # The stylesheets and the svgs are compiled-in constants rather than files
    # on disk. syntax.css is a snapshot of one Rouge theme, and it is the only
    # one: a site that wants different colours overrides them in `_styles.css`,
    # which is linked last.
    def write_assets
      write("blog.css", Assets::BLOG)
      write("syntax.css", Assets::SYNTAX)
      write("pulpmesh-logo.svg", Assets::PULPMESH_LOGO)
      write("favicon.svg", Assets::FAVICON) unless config.favicon
      FSUtil.copy_file(config.stylesheet_path, File.join(output, Config::STYLESHEET)) if config.styles?
    end

    def render(template, post: nil)
      context = Context.new(self, post: post)
      case template
      when "post.html.erb" then context.render_post
      when "index.html.erb" then context.render_index
      when "404.html.erb" then context.render_404
      when "rss.xml.erb" then context.render_rss
      else raise Error, "unknown template: #{template}"
      end
    end

    # The object templates are evaluated against: site data plus the few escaping
    # and date helpers the markup needs. The generated render_* methods are
    # defined on this class, so bare `config`, `post` and `posts` in a template
    # resolve to these readers.
    class Context
      attr_reader :site, :config, :posts, :post

      def initialize(site, post: nil)
        @site = site
        @config = site.config
        @posts = site.posts
        @post = post
      end

      def h(text)
        Escape.escape_html(text)
      end

      # Raw html for the feed. A CDATA section ends at the first `]]>`, so a
      # post containing that sequence would close it early and leave the rest of
      # the document as markup; each occurrence is split across two sections
      # instead, which parsers rejoin into the original text.
      def cdata(html)
        "<![CDATA[#{html.to_s.gsub("]]>", "]]]]><![CDATA[>")}]]>"
      end

      def iso(time)
        time.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
      end

      def ymd(time)
        time.utc.strftime("%Y-%m-%d")
      end

      def rfc822(time)
        time.utc.strftime("%a, %d %b %Y %H:%M:%S +0000")
      end

      def url_for(path = nil)
        config.url_for(path)
      end

      # Absolute where a base_url is configured (metadata, feed), otherwise the
      # relative filename, which is what every in-page link uses anyway.
      def post_url(a_post)
        config.url_for(a_post.filename) || a_post.filename
      end
    end
  end
end
