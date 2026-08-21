# Reproduction: String.new applied to a poly value fails to COMPILE, with a C
# type error rather than a Ruby-level diagnostic.
#
#   ruby string_new_poly.rb                              # prints x, exit 0
#   spinel string_new_poly.rb -o /tmp/str_poly           # C compilation failed
#
# Comment out the marked line and the rest compiles and runs.

nested = [["class", "x"]]
flat = ["class", "x"]
local = "x"

puts ::String.new(local)      # ok
puts ::String.new(flat[1])    # ok
puts ::String.new("x")        # ok

# Workarounds, all fine:
puts nested[0][1].dup
puts(+nested[0][1])
buffer = ::String.new
buffer << nested[0][1]
puts buffer

# BUG: passing 'sp_RbVal' to parameter of incompatible type 'const char *'
puts ::String.new(nested[0][1])
