# frozen_string_literal: true

# Renders random documents through both pulpmesh and kramdown and compares the
# html byte for byte. CRuby only, like the other tools here: kramdown is a
# dev-machine dependency and never reaches the binary.
#
# The snapshot tests pin the output that was already thought about. This asks
# the question those cannot: whether the parser agrees with the one it replaced
# on documents nobody wrote by hand.
#
# A failure prints the seed. Re-run with FUZZ_SEED set to it for the same
# documents in the same order.

require "kramdown"
require "kramdown-parser-gfm"
require_relative "../pulpmesh"

ROOT = File.expand_path("..", __dir__)

# pulpmesh adds rel="nofollow" to outbound links, which kramdown does not. It is
# the one difference this harness allows.
#
# Html is the other, and it cannot be normalised away: kramdown renders a tag an
# author wrote, and decodes an entity reference, where pulpmesh escapes both on
# purpose. So the corpus below contains neither. A bare `<` and a bare `&` do
# appear, since both renderers escape those the same way.
NOFOLLOW = ' rel="nofollow"'

INLINE = [
  "plain words", "a [link](page.html)", "an ![image](pic.png)", "**bold**",
  "*em*", "_em_", "`code()`", "it's fine", '"quoted"', "the '80s",
  "a -- dash", "an --- em dash", "an ... ellipsis", "AT&T", "5 < 6", "a > b",
  "Ben & Jerry",
  "a [wiki](https://en.wikipedia.org/wiki/Ruby_(programming_language))",
  'a [titled](u "the title")', "snake_case_name", "[1] footnote marker",
  "ID_ATA_FEATURE_SET", "https://example.com/a", "50% of x", "a(b)c",
  "![alt](p.png \"t\")", "trailing  spaces", "x_y_z", "**a _b_ c**"
].freeze

def words(count = rand(1..4))
  Array.new(count) { INLINE.sample }.join(" ")
end

# Each entry builds one block. Lists are built tight and never touch each other:
# pulpmesh documents tight lists only, and a blank line inside a list or between
# two of them is what makes kramdown treat the whole thing as loose.
def block(kind)
  case kind
  when :atx then "#{"#" * rand(1..6)} #{words(2)}"
  when :setext_h1 then "#{words(2)}\n==="
  when :setext_h2 then "#{words(2)}\n---"
  when :paragraph then words(rand(1..4))
  when :wrapped then Array.new(rand(2..3)) { words(2) }.join("\n")
  when :bullets then Array.new(rand(1..4)) { "- #{words(2)}" }.join("\n")
  when :ordered then Array.new(rand(1..4)).each_with_index.map { |_, i| "#{i + 1}. #{words(2)}" }.join("\n")
  when :quote then Array.new(rand(1..2)) { "> #{words(2)}" }.join("\n")
  when :rule then ["---", "***", "___"].sample
  when :fence then "```\nliteral -- text 'here'\nnot **markdown**\n```"
  else words
  end
end

KINDS = %i[atx setext_h1 setext_h2 paragraph wrapped bullets ordered quote rule
           fence].freeze

# A list may not sit next to another list, and a rule may not follow a paragraph
# that would swallow it as a setext underline. Both are shapes this parser
# renders differently on purpose, and both are documented.
LIST_KINDS = %i[bullets ordered].freeze

def document
  kinds = []
  rand(1..6).times do
    candidate = KINDS.sample
    next if LIST_KINDS.include?(candidate) && LIST_KINDS.include?(kinds.last)

    kinds << candidate
  end
  kinds << :paragraph if kinds.empty?
  "#{kinds.map { |kind| block(kind) }.join("\n\n")}\n"
end

count = Integer(ENV.fetch("FUZZ_COUNT", "2000"))
seed = Integer(ENV.fetch("FUZZ_SEED", Random.new_seed.to_s[-9..]))
srand(seed)

failures = []
count.times do
  source = document
  mine = Pulpmesh::Markdown.render(source).gsub(NOFOLLOW, "")
  theirs = Kramdown::Document.new(source, input: "GFM").to_html
  failures << [source, mine, theirs] unless mine == theirs
end

if failures.empty?
  puts "ok   #{count} documents render exactly as kramdown renders them (seed #{seed})"
  exit 0
end

puts "FAIL #{failures.size} of #{count} documents differ from kramdown (seed #{seed})"
failures.first(3).each do |source, mine, theirs|
  puts
  puts "source:   #{source.inspect}"
  puts "pulpmesh: #{mine.inspect}"
  puts "kramdown: #{theirs.inspect}"
end
abort("re-run with FUZZ_SEED=#{seed} to get these documents again")
