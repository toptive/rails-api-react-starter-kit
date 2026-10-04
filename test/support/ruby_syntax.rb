require "prism"

module RubySyntax
  def nodes(node)
    return [] unless node

    [ node ] + node.compact_child_nodes.flat_map { |child| nodes(child) }
  end

  def syntax(path)
    result = Prism.parse_file(path.to_s)
    assert_empty result.errors, "#{path}: invalid Ruby"
    result.value
  end

  def calls(node)
    nodes(node).grep(Prism::CallNode)
  end
end
