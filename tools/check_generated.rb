# frozen_string_literal: true

# Staleness guard for the committed build artifacts. CRuby only: it runs the
# Erubi codegen and diffs the result against what is checked in, so a template
# or stylesheet edit that skipped `rake generate` fails here.
require_relative "codegen"

failures = []
{
  "pulpmesh/templates.rb" => generated_templates,
  "pulpmesh/assets.rb" => generated_assets
}.each do |relative, regenerated|
  path = File.join(ROOT, relative)
  if File.read(path) == regenerated
    puts "ok   #{relative} is up to date"
  else
    failures << relative
    puts "FAIL #{relative} is stale — run `rake generate`"
  end
end

abort("#{failures.size} stale artifact(s)") if failures.any?
