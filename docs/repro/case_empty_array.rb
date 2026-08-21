# Reproduction: an empty Array literal as the value of a `case` branch.
#
# Every line below prints the same thing under CRuby. Under spinel the cases
# marked BUG print something else.
#
#   ruby case_empty_array.rb        # all OK
#   spinel case_empty_array.rb -o /tmp/case_empty && /tmp/case_empty

def check(label, got, want)
  status = got == want ? "ok " : "BUG"
  puts "#{status} #{label.ljust(34)} got=#{got.inspect.ljust(10)} want=#{want.inspect}"
end

# 1. Empty array literal, on its own.
check("[] alone", (case "s" when String then [] end), [])

# 2. Empty array literal against another empty one.
check("[] vs []", (case "s" when String then [] else [] end), [])

# 3. Against a non-empty array: collapses to nil.
check("[] vs [\"x\"]", (case "s" when String then [] else ["x"] end), [])

# 4. Against a String: collapses to "".
check("[] vs \"str\"", (case "s" when String then [] else "str" end), [])

# 5. Against an Integer: collapses to 0.
check("[] vs 7", (case "s" when String then [] else 7 end), [])

# 6. Empty Hash literal against a non-empty array: collapses to nil.
check("{} vs [\"x\"]", (case "s" when String then {} else ["x"] end), {})

# 7. Non-empty array literals are unaffected.
check("[\"a\"] vs [\"b\"]", (case "s" when String then ["a"] else ["b"] end), ["a"])
check("[\"a\"] vs \"str\"", (case "s" when String then ["a"] else "str" end), ["a"])

# 8. An empty array reaching the branch as a variable or a call is unaffected;
#    only the literal in branch position is miscompiled.
def empty_via_call = []
empty = []
check("[] via local", (case "s" when String then empty else ["x"] end), [])
check("[] via method", (case "s" when String then empty_via_call else ["x"] end), [])

# 9. The if/else and ternary spellings are unaffected.
check("if/else", (if "s".is_a?(String) then [] else ["x"] end), [])
check("ternary", ("s".is_a?(String) ? [] : ["x"]), [])

puts
puts "-- the miscompiled value is typed as Array, so using it crashes --"
r = case "s" when String then [] else ["x"] end
puts "about to call .each on #{r.inspect}"
$stdout.flush
r.each { |e| puts e }
puts "survived (CRuby reaches here; spinel segfaults before this)"
