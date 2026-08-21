# frozen_string_literal: true

require "socket"

module Pulpmesh
  # Static preview server for a built site.
  #
  # Ctrl-C stops the process through the default signal action: spinel compiles
  # `trap` to a no-op, so there is no handler to run a graceful shutdown.
  module Server
    CONTENT_TYPES = {
      ".html" => "text/html; charset=utf-8",
      ".css" => "text/css; charset=utf-8",
      ".xml" => "application/rss+xml; charset=utf-8",
      ".js" => "text/javascript; charset=utf-8",
      ".json" => "application/json",
      ".svg" => "image/svg+xml",
      ".png" => "image/png",
      ".jpg" => "image/jpeg",
      ".jpeg" => "image/jpeg",
      ".gif" => "image/gif",
      ".ico" => "image/x-icon",
      ".txt" => "text/plain; charset=utf-8"
    }.freeze

    def self.start(root, port: 4000, host: "127.0.0.1")
      server = TCPServer.new(host, port)
      puts "serving #{root} on http://#{host}:#{port} (ctrl-c to stop)"
      # Ctrl-C kills the process outright, so a buffered stdout would never be
      # flushed and this line would never be seen.
      $stdout.flush

      loop do
        session = server.accept
        begin
          serve(session, root)
        rescue StandardError
          nil
        end
        session.close
      end
    end

    def self.serve(session, root)
      request = session.gets
      return unless request

      method, target = parse_request_line(request)
      # Read past the headers so the client sees a clean response rather than a
      # reset connection.
      while (line = session.gets)
        break if line == "\r\n" || line == "\n"
      end

      return respond(session, 405, "text/plain; charset=utf-8", "method not allowed") unless
        method == "GET" || method == "HEAD"

      path = resolve(root, target)
      if path
        respond(session, 200, content_type(path), File.read(path), head: method == "HEAD")
      else
        not_found(session, root, head: method == "HEAD")
      end
    end

    def self.parse_request_line(line)
      parts = line.strip.split(" ")
      [parts[0].to_s, parts[1].to_s]
    end

    # Maps a request target onto a file under the output root, refusing anything
    # that climbs out of it.
    def self.resolve(root, target)
      relative = target.split("?").first.to_s
      relative = relative.split("#").first.to_s
      relative = "/" if relative.empty?
      return nil if relative.include?("..")

      candidate = File.join(root, relative.sub(%r{\A/}, ""))
      candidate = File.join(candidate, "index.html") if Dir.exist?(candidate)
      File.exist?(candidate) && !Dir.exist?(candidate) ? candidate : nil
    end

    def self.content_type(path)
      CONTENT_TYPES.fetch(File.extname(path).downcase, "application/octet-stream")
    end

    def self.not_found(session, root, head: false)
      page = File.join(root, "404.html")
      body = File.exist?(page) ? File.read(page) : "not found"
      respond(session, 404, "text/html; charset=utf-8", body, head: head)
    end

    def self.respond(session, status, type, body, head: false)
      reason = status == 200 ? "OK" : (status == 404 ? "Not Found" : "Method Not Allowed")
      session.write("HTTP/1.1 #{status} #{reason}\r\n")
      session.write("Content-Type: #{type}\r\n")
      session.write("Content-Length: #{body.bytesize}\r\n")
      session.write("Connection: close\r\n\r\n")
      session.write(body) unless head
    end
  end
end
