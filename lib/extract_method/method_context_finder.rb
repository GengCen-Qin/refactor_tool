# -*- coding: utf-8 -*-

# 查找方法上下文的类
class MethodContextFinder
  # 初始化上下文查找器
  # @param target_node [Parser::AST::Node] 目标节点
  def initialize(target_node)
    @target_node = target_node
  end
  
  # 查找包含目标节点的方法定义及是否是类方法
  # @param ast [Parser::AST::Node] 完整AST
  # @return [Array(Parser::AST::Node, Boolean)] 方法节点和是否是类方法的标志
  def find(ast)
    @parent_method = nil
    @is_class_method = false
    @in_class_self_context = false
    
    traverse(ast)
    
    [@parent_method, @is_class_method]
  end
  
  # 查找节点所在的类上下文
  # @param ast [Parser::AST::Node] 完整AST
  # @return [Array(Parser::AST::Node, Parser::AST::Node)] 类节点和单例类节点
  def find_class_context(ast)
    @class_node = nil
    @eigenclass_node = nil
    
    traverse_for_class(ast)
    
    [@class_node, @eigenclass_node]
  end
  
  private
  
  # 遍历AST查找方法上下文
  # @param node [Parser::AST::Node] 当前节点
  def traverse(node)
    if node.is_a?(Parser::AST::Node)
      # 检查是否在 class << self 上下文中
      if node.type == :sclass && 
         node.children.first && 
         node.children.first.type == :self
        old_context = @in_class_self_context
        @in_class_self_context = true
        node.children.each { |child| traverse(child) if child.is_a?(Parser::AST::Node) }
        @in_class_self_context = old_context
        return
      end
      
      # 检查是否是方法定义
      if (node.type == :def || node.type == :defs) && node.location && node.location.expression
        expr = node.location.expression
        t_expr = @target_node.location.expression
        
        # 检查目标节点是否在此方法内
        if t_expr.line >= expr.line && t_expr.last_line <= expr.last_line
          @parent_method = node
          @is_class_method = (node.type == :defs || @in_class_self_context)
        end
      end
      
      node.children.each { |child| traverse(child) if child.is_a?(Parser::AST::Node) }
    end
  end
  
  # 遍历AST查找类上下文
  # @param node [Parser::AST::Node] 当前节点
  def traverse_for_class(node)
    return unless node.is_a?(Parser::AST::Node)
    
    if node.type == :class
      # 记录当前类节点
      old_class = @class_node
      @class_node = node
      
      # 递归检查类的子节点
      node.children.each { |child| traverse_for_class(child) if child.is_a?(Parser::AST::Node) }
      
      # 还原类上下文
      @class_node = old_class
      return
    end
    
    if node.type == :sclass && node.children.first&.type == :self
      # 记录单例类
      old_eigenclass = @eigenclass_node
      @eigenclass_node = node
      
      # 递归检查单例类的子节点
      node.children.each { |child| traverse_for_class(child) if child.is_a?(Parser::AST::Node) }
      
      # 还原单例类上下文
      @eigenclass_node = old_eigenclass
      return
    end
    
    # 检查特定节点是否是目标方法
    if node.equal?(@target_node) && (@class_node || @eigenclass_node)
      # 如果找到目标节点，停止搜索
      return
    end
    
    # 继续递归搜索
    node.children.each { |child| traverse_for_class(child) if child.is_a?(Parser::AST::Node) }
  end
end