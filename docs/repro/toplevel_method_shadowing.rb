# Reproduction: a top-level method shadows a class's own method of the same
# name, inverting Ruby's method lookup.
#
# In CRuby a top-level `def` is a private method on Object, so a class's own
# method wins for instances of that class. Under spinel the top-level one wins.
#
#   ruby toplevel_method_shadowing.rb
#   spinel toplevel_method_shadowing.rb -o /tmp/shadow && /tmp/shadow

def check(label, got, want)
  puts "#{got == want ? "ok " : "BUG"} #{label.ljust(28)} got=#{got.inspect.ljust(22)} want=#{want.inspect}"
end

# --- 1. Silent wrong answer: same arity, so nothing raises. ---
class Greeter
  def greeting
    "from the class"
  end

  def render
    greeting
  end
end

def greeting
  "from the top level"
end

check("own method wins", Greeter.new.render, "from the class")

# --- 2. Same, through an attr_reader. ---
class Labelled
  attr_reader :label

  def initialize(label)
    @label = label
  end

  def render
    "<#{label}>"
  end
end

def label(prefix)
  "#{prefix}!"
end

# Under spinel this raises ArgumentError (given 0, expected 1) rather than
# returning "<a>", because the top-level `label` is dispatched instead.
result = begin
  Labelled.new("a").render
rescue ArgumentError => e
  "ArgumentError: #{e.message}"
end
check("attr_reader wins", result, "<a>")

# --- 3. The top-level method itself still works in both. ---
check("top-level still callable", greeting, "from the top level")
check("top-level with args", label("b"), "b!")
