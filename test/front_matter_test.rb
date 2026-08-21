# frozen_string_literal: true

require_relative "support/harness"

FM = Pulpmesh::FrontMatter

data, body = FM.split("# Title\n\nbody\n")
Harness.check("no fence: data", Harness.pairs(data), "")
Harness.check("no fence: body", body, "# Title\n\nbody\n")

data, body = FM.split("---\ndate: 2026-06-20\n---\n\n# Title\n")
Harness.check("split: data", Harness.pairs(data), "date=\"2026-06-20\"")
Harness.check("split: body", body, "\n# Title\n")

data, = FM.split("---\ntitle: mauri's devlog: notes\n---\n")
Harness.check("apostrophes and colons kept", data["title"], "mauri's devlog: notes")

data, = FM.split("---\nwith_styles: false\ntags: [a, b]\n---\n")
Harness.check("boolean coerced", data["with_styles"], false)
Harness.check("list coerced", data["tags"], %w[a b])

Harness.check("list from bare string", FM.list("a, b"), %w[a b])
Harness.check("list from nil", FM.list(nil), [])
Harness.check("list from array", FM.list(%w[x]), %w[x])
Harness.check("keys downcased", Harness.pairs(FM.split("---\nTitle: T\n---\n")[0]), "title=\"T\"")
Harness.check("comment skipped", Harness.pairs(FM.split("---\n# c\na: 1\n---\n")[0]), "a=\"1\"")
