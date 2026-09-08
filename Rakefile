# frozen_string_literal: true

require_relative "tools/codegen"

desc "regenerate pulpmesh/templates.rb from templates/*.erb"
task :templates do
  File.write(File.join(ROOT, "pulpmesh", "templates.rb"), generated_templates)
  puts "wrote pulpmesh/templates.rb"
end

desc "regenerate pulpmesh/assets.rb from assets/*.css and assets/*.svg"
task :assets do
  File.write(File.join(ROOT, "pulpmesh", "assets.rb"), generated_assets)
  puts "wrote pulpmesh/assets.rb"
end

desc "regenerate pulpmesh/entities.rb from kramdown's entity table"
task :entities do
  File.write(File.join(ROOT, "pulpmesh", "entities.rb"), generated_entities)
  puts "wrote pulpmesh/entities.rb"
end

desc "fail if the committed artifacts are stale"
task :check do
  ruby "-e", "require_relative 'tools/check_generated'"
end

desc "run each test under CRuby and diff against the spinel snapshots"
task :parity do
  ruby "-e", "require_relative 'tools/check_parity'"
end

task generate: %i[templates assets entities]
task default: %i[generate check parity]
