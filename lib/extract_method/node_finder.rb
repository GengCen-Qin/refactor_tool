# -*- coding: utf-8 -*-

# 根据位置和内容查找AST节点的类
class NodeFinder
  # 初始化查找器
  # @param line [Integer] 目标代码行号
  # @param column [Integer] 目标代码列号
  # @param code_snippet [String] 目标代码片段
  def initialize(line, column, code_snippet)
    @line = line
    @column = column
    @code_snippet = code_snippet
    @found_node = nil
  end
  
  # 在AST中查找目标节点
  # @param ast [Parser::AST::Node] 要搜索的AST
  # @return [Parser::AST::Node, nil] 找到的节点或nil
  def find(ast)
    traverse(ast)
    @found_node
  end
  
  private
  
  # 遍历AST查找节点
  # @param node [Parser::AST::Node] 当前节点
  def traverse(node)
    if node.is_a?(Parser::AST::Node) && node.location
      expr = node.location.expression
      if expr && expr.line == @line && expr.column == @column
        # 比对源码片段
        snippet = expr.source
        @found_node ||= node if snippet.strip == @code_snippet.strip
      end
      
      node.children.each { |child| traverse(child) if child.is_a?(Parser::AST::Node) }
    end
  end
end