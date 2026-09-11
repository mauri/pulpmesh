# frozen_string_literal: true

require_relative "support/harness"

# A symlink inside the tree is unlinked, and what it points at is left alone.
Harness.scratch("fsutil-nested-link") do |root|
  keep = File.join(root, "keep")
  Pulpmesh::FSUtil.mkdir_p(keep)
  File.write(File.join(keep, "data.txt"), "precious")

  tree = File.join(root, "tree")
  Pulpmesh::FSUtil.mkdir_p(tree)
  File.write(File.join(tree, "page.html"), "page")
  File.symlink(keep, File.join(tree, "link"))

  Pulpmesh::FSUtil.rm_rf(tree)

  Harness.check("the tree is gone", Dir.exist?(tree), false)
  Harness.check("the directory behind the link survives", Dir.exist?(keep), true)
  Harness.check("the file behind the link survives",
                File.read(File.join(keep, "data.txt")), "precious")
end

# A symlink named directly is unlinked rather than followed.
Harness.scratch("fsutil-direct-link") do |root|
  target = File.join(root, "target")
  Pulpmesh::FSUtil.mkdir_p(target)
  File.write(File.join(target, "data.txt"), "precious")

  link = File.join(root, "link")
  File.symlink(target, link)
  Pulpmesh::FSUtil.rm_rf(link)

  Harness.check("the link is gone", File.symlink?(link), false)
  Harness.check("the target survives", File.read(File.join(target, "data.txt")), "precious")
end

# Dotfiles are removed with everything else, or the rmdir would fail.
Harness.scratch("fsutil-dotfiles") do |root|
  tree = File.join(root, "tree")
  Pulpmesh::FSUtil.mkdir_p(File.join(tree, "nested"))
  File.write(File.join(tree, ".hidden"), "h")
  File.write(File.join(tree, "nested", "deep.txt"), "d")

  Pulpmesh::FSUtil.rm_rf(tree)
  Harness.check("a tree with dotfiles is removed", Dir.exist?(tree), false)
end

Harness.scratch("fsutil-missing") do |root|
  Pulpmesh::FSUtil.rm_rf(File.join(root, "never-existed"))
  Harness.check("removing a missing path is a no-op", Dir.children(root), [])
end
