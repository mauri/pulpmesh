# frozen_string_literal: true

require_relative "support/harness"

# Only the paths that refuse are covered here. A successful run prints the
# output directory, whose absolute path differs between runs and so cannot
# reach the snapshot, and neither stdout nor stderr can be redirected under
# spinel. What `build` does on the way to that line is site_test's subject
# anyway; what is worth pinning down is that every way of getting it wrong
# comes back as a message rather than a backtrace.
def refusal(*argv)
  Harness.refusal { Pulpmesh::CLI.new.run(argv) }
end

Harness.scratch("cli") do |dir|
  source = File.join(dir, "src")
  Pulpmesh::FSUtil.mkdir_p(source)
  File.write(File.join(source, "post.md"), "# P\n\nbody\n")

  Harness.check("unknown command", refusal("frobnicate", source), "unknown command")
  Harness.check("unknown option", refusal("build", source, "--nope"),
                "invalid option")
  Harness.check("missing source", refusal("build", File.join(dir, "absent")),
                "not a directory")
  Harness.check("source that is a file", refusal("build", File.join(source, "post.md")),
                "not a directory")
  Harness.check("output that is the source", refusal("build", source, "--out=#{source}"),
                "output directory is the source directory")
  Harness.check("output holding somebody else's files", refusal("build", source, "--out=#{dir}"),
                "output directory contains the source directory")

  colliding = File.join(dir, "colliding")
  Pulpmesh::FSUtil.mkdir_p(colliding)
  File.write(File.join(colliding, "0001-clash.md"), "# One\n")
  File.write(File.join(colliding, "0002-clash.md"), "# Two\n")
  Harness.check("colliding slugs", refusal("build", colliding, "--out=#{File.join(dir, "out")}"),
                "0001-clash.md and 0002-clash.md both publish as clash.html")

  # An output directory that cannot be written raises its own Errno, which the
  # entry point reports like any other refusal. Root can write it regardless, so
  # the check only asks that nothing escaped uncaught.
  locked = File.join(dir, "locked")
  Pulpmesh::FSUtil.mkdir_p(locked)
  File.chmod(0o500, locked)
  writable = begin
    probe = File.join(locked, "probe")
    File.write(probe, "x")
    File.delete(probe)
    true
  rescue SystemCallError
    false
  end
  code = begin
    Pulpmesh::CLI.new.run(["build", source, "--out=#{File.join(locked, "out")}"])
    "completed"
  rescue Pulpmesh::Error, SystemCallError
    "reported"
  end
  Harness.check("unwritable output", writable ? "reported" : code, "reported")
  File.chmod(0o700, locked)
end

# A date with the right shape but no such day falls back to the file's mtime
# rather than aborting the build.
Harness.scratch("cli-bad-date") do |dir|
  path = File.join(dir, "post.md")
  File.write(path, "---\ndate: 2025-13-45\n---\n\n# P\n\nbody\n")
  Harness.check_quiet("an impossible date falls back to mtime",
                      Pulpmesh::Post.new(path).date, File.mtime(path).utc)
end
