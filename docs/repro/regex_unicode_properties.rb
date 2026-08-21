# Reproduction: \p{...} Unicode property escapes match nothing under spinel.
#
# Every check prints `ok` under CRuby.
#
#   ruby regex_unicode_properties.rb
#   spinel regex_unicode_properties.rb -o /tmp/re_props && /tmp/re_props

def check(label, got, want)
  puts "#{got == want ? "ok " : "BUG"} #{label.ljust(30)} got=#{got.inspect.ljust(16)} want=#{want.inspect}"
end

SAMPLE = "abc def.1_2"

# Positive property escapes match nothing at all.
check("\\p{Word}",  SAMPLE.scan(/\p{Word}/).join,  "abcdef1_2")
check("\\p{Alpha}", SAMPLE.scan(/\p{Alpha}/).join, "abcdef")
check("\\p{Alnum}", SAMPLE.scan(/\p{Alnum}/).join, "abcdef12")
check("\\p{Digit}", SAMPLE.scan(/\p{Digit}/).join, "12")
check("\\p{L}",     SAMPLE.scan(/\p{L}/).join,     "abcdef")

# Negated, the same failure deletes nearly everything instead.
check("[^\\p{Word}\\- \\t]", SAMPLE.gsub(/[^\p{Word}\- \t]/, ""), "abc def1_2")

# The ascii spellings are correct, and are the workaround.
check("\\w shorthand",  SAMPLE.gsub(/[^\w\- \t]/, ""),            "abc def1_2")
check("explicit class", SAMPLE.gsub(/[^a-zA-Z0-9_\- \t]/, ""),    "abc def1_2")
