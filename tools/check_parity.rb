# frozen_string_literal: true

# Runs each test under CRuby and diffs against the committed snapshot, which the
# compiled binary is already checked against. Committing a snapshot makes
# `spin test` compare the binary to the snapshot rather than to CRuby, so this
# keeps the CRuby-vs-spinel comparison that the no-snapshot mode gave for free.
ROOT = File.expand_path("..", __dir__)

failures = []
Dir.glob(File.join(ROOT, "test", "*.rb")).sort.each do |test|
  snapshot = "#{test}.expected"
  name = File.basename(test)
  unless File.exist?(snapshot)
    puts "skip #{name} (no snapshot)"
    next
  end

  actual = IO.popen([RbConfig.ruby, test], &:read)
  if actual == File.read(snapshot)
    puts "ok   #{name}"
  else
    failures << name
    puts "FAIL #{name} — CRuby output differs from the snapshot"
  end
end

abort("#{failures.size} test(s) diverge between CRuby and spinel") if failures.any?
