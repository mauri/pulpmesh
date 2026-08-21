# frozen_string_literal: true

module Pulpmesh
  # Replaces the corners of FileUtils the build needs. Dir.mkdir / Dir.rmdir /
  # Dir.children / File.write / File.delete are all available; the recursion
  # around them is not.
  module FSUtil
    def self.mkdir_p(path)
      return if Dir.exist?(path)

      parent = File.dirname(path)
      mkdir_p(parent) unless parent == path || Dir.exist?(parent)
      Dir.mkdir(path)
    end

    def self.rm_rf(path)
      return unless Dir.exist?(path) || File.exist?(path)

      unless Dir.exist?(path)
        File.delete(path)
        return
      end

      # Dir.children rather than Dir.glob: glob skips dotfiles, which would
      # leave a directory non-empty and fail the rmdir below.
      Dir.children(path).each { |child| rm_rf(File.join(path, child)) }
      Dir.rmdir(path)
    end

    def self.copy_file(from, to)
      File.write(to, File.read(from))
    end
  end
end
