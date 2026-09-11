# frozen_string_literal: true

require "optparse"

module Pulpmesh
  class CLI
    USAGE = <<~TEXT
      usage: pulpmesh <command> [source] [options]

      commands:
        build [SOURCE]     render SOURCE into html (SOURCE defaults to the current directory)

      options:
            --out=DIR      output directory (default: SOURCE/_site)
            --base-url=URL absolute site url, overriding base_url in _pulpmesh.md
        -v, --version      print the version
        -h, --help         print this message
    TEXT

    def self.start(argv)
      new.run(argv)
    end

    def run(argv)
      options = {}
      args = argv.dup
      build_parser(options).parse!(args)

      # The bundled optparse leaves anything it does not recognise in argv
      # rather than raising, so an unknown flag would otherwise be taken as the
      # command or the source directory.
      unknown = args.find { |arg| arg.start_with?("-") }
      raise Error, "invalid option: #{unknown}" if unknown

      command = args.shift || "build"

      case command
      when "build" then build(args.shift, options) && 0
      else
        warn "unknown command: #{command}\n\n#{USAGE}"
        1
      end
    rescue Pulpmesh::Error, Errno::ENOENT => e
      warn "pulpmesh: #{e.message}"
      1
    end

    private

    # Value-carrying flags are long-only and must spell the value in the flag
    # (`--out=DIR`): the bundled optparse decides a flag takes a value by looking
    # for `=` in its long form, and matches such a flag by its long form alone.
    def build_parser(options)
      parser = OptionParser.new
      parser.banner = USAGE
      parser.on("--out=DIR", "output directory") { |value| options[:out] = value }
      parser.on("--base-url=URL", "absolute site url") { |value| options[:base_url] = value }
      parser.on("-v", "--version") do
        puts Pulpmesh::VERSION
        exit 0
      end
      parser.on("-h", "--help") do
        puts USAGE
        exit 0
      end
      parser
    end

    def build(source, options)
      site = Site.new(source: source || Dir.pwd, output: options[:out], base_url: options[:base_url])
      site.build
      site.warnings.each { |warning| warn "pulpmesh: #{warning}" }
      puts "built #{site.posts.size} #{site.posts.size == 1 ? "post" : "posts"} into #{site.output}"
      site
    end
  end
end
