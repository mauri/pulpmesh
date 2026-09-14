# frozen_string_literal: true

require_relative "../../pulpmesh"

# Snapshot tests print rather than assert: `spin test` diffs stdout against the
# committed `.expected`, so a labelled line per check is both the assertion and
# the record of what it produced. `check` still prints ok/FAIL so a mismatch is
# readable without reaching for the diff.
module Harness
  @failures = 0

  # `spin test` fails on a non-zero exit as well as on a snapshot diff. Without
  # this, a check that failed the same way under CRuby and under spinel would
  # still pass, since only the two outputs are compared.
  def self.failed
    @failures += 1
  end

  def self.failures
    @failures
  end
  # CRuby resolves `__dir__` to this file's own directory; spinel resolves it to
  # the directory of the program being compiled, since a require_relative is
  # spliced rather than loaded. Probing both keeps one path working in each.
  FIXTURE = [
    File.expand_path("../fixtures/site", __dir__),
    File.expand_path("fixtures/site", __dir__),
    File.expand_path("test/fixtures/site", __dir__)
  ].find { |candidate| Dir.exist?(candidate) }

  def self.check(label, got, want)
    failed unless got == want
    puts "#{got == want ? "ok " : "FAIL"} #{label} => #{ascii(got.inspect)}"
    puts "     wanted #{ascii(want.inspect)}" unless got == want
  end

  # CRuby's String#inspect escapes non-ascii under a non-UTF-8 locale and prints
  # it literally under a UTF-8 one, so a snapshot would otherwise depend on the
  # locale of whoever regenerated it. Escaping here makes the output the same
  # everywhere, and the same as the compiled binary's.
  def self.ascii(text)
    text.each_char.map { |char| char.ord < 128 ? char : format("\\u%04X", char.ord) }.join
  end

  # Only ok/FAIL, for a value that is real but not reproducible (an mtime, an
  # absolute path), which must not reach the snapshot.
  def self.check_quiet(label, got, want)
    failed unless got == want
    puts "#{got == want ? "ok " : "FAIL"} #{label}"
  end

  # Hash#inspect differs between CRuby 3.3 and spinel (`{"a"=>1}` against
  # `{"a" => 1}`), so a hash is reported as sorted key=value pairs instead.
  def self.pairs(hash)
    hash.keys.sort.map { |key| "#{key}=#{hash[key].inspect}" }.join(",")
  end

  def self.ymd(time)
    time.utc.strftime("%Y-%m-%d")
  end

  # One scratch root per run, under which every throwaway directory is created.
  # There is no tmpdir stdlib here, and the usual atomic claim is unavailable:
  # spinel's Dir.mkdir neither honours a mode nor raises on a directory that
  # already exists. So the name is one nobody else could have guessed, and a
  # path that somehow exists already is skipped rather than reused — otherwise
  # a fixed /tmp name would let any local user pre-create it as a symlink and
  # aim the suite's cleanup at whatever they liked.
  ROOT = begin
    chosen = nil
    10.times do
      candidate = "/tmp/pulpmesh-test-#{Process.pid}-#{rand(1 << 32)}"
      next if File.symlink?(candidate) || File.exist?(candidate)

      Dir.mkdir(candidate)
      chosen = candidate
      break
    end
    raise "could not create a scratch directory under /tmp" unless chosen

    chosen
  end

  # A throwaway directory under ROOT. The name is stable within a run, since a
  # test may report the folder it built from and that reaches the snapshot.
  def self.scratch(name)
    path = File.join(ROOT, name)
    Pulpmesh::FSUtil.rm_rf(path)
    Pulpmesh::FSUtil.mkdir_p(path)
    yield path
    Pulpmesh::FSUtil.rm_rf(path)
  end

  # Builds a source folder and yields the site plus its output directory.
  def self.build(name, source, base_url: nil)
    scratch(name) do |out|
      site = Pulpmesh::Site.new(source: source, output: out, base_url: base_url)
      site.build
      yield site, out
    end
  end

  # Output that mentions an absolute path or an mtime is not reproducible, so
  # tests report the pieces that are.
  def self.children(dir)
    Dir.children(dir).sort
  end

  # The reason a build was refused, without the path it names, which is not
  # reproducible. Returns "no error raised" when the block completes.
  def self.refusal
    yield
    "no error raised"
  rescue Pulpmesh::Error => e
    e.message.split(":").first
  end
end

at_exit do
  Pulpmesh::FSUtil.rm_rf(Harness::ROOT)
  count = Harness.failures
  # Printed to stderr so it stays out of the snapshot comparison.
  if count.positive?
    warn "#{count} check(s) failed"
    exit 1
  end
end
