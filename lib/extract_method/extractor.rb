# -*- coding: utf-8 -*-

module ExtractMethod
  # 方法抽取器核心类
  # 负责执行代码抽取操作的主要逻辑
  class Extractor
    # 初始化方法抽取器
    # @param filename [String] 源代码文件路径
    # @param code_snippet [String] 要抽取的代码片段
    # @param start_line [Integer] 代码片段的起始行
    # @param start_column [Integer] 代码片段的起始列
    # @param new_method_name [String] 可选的新方法名，若不提供则会通过命令行交互获取
    def initialize(filename, code_snippet, start_line, start_column, new_method_name = nil)
      @filename = filename
      @code_snippet = code_snippet
      @start_line = start_line
      @start_column = start_column
      @tmp_func_name = :extracted_method_temp
      @new_method_name = new_method_name
    end

    # 执行代码抽取
    # @return [Boolean] 操作是否成功
    def perform_extraction
      # 检查文件是否存在
      unless File.exist?(@filename)
        puts "File #{@filename} not found."
        return false
      end

      # 读取和解析源代码
      source = File.read(@filename)
      @ast = parse_source(source)

      # 定位目标节点
      @target_node = find_target_node
      unless @target_node
        puts "Could not locate target code snippet in AST."
        return false
      end

      # 查找包含目标代码的方法节点及判断是否是类方法
      @enclosing_def, @is_class_method = find_enclosing_method

      # 进行代码替换和新方法插入
      transformed_ast = transform_ast

      # 获取用户输入的新函数名或使用预先提供的函数名
      user_func_name = @new_method_name || get_user_function_name
      return false unless user_func_name
    
      # 重命名临时函数为用户提供的函数名
      final_ast = rename_method(transformed_ast, @tmp_func_name, user_func_name)

      # 写回文件
      new_source = Unparser.unparse(final_ast)
      File.write(@filename, new_source)
      puts "已完成重构，文件已更新。"

      true
    end

    private

    # 解析源代码为AST
    # @param source [String] 源代码
    # @return [Parser::AST::Node] 解析后的AST
    def parse_source(source)
      buffer = Parser::Source::Buffer.new(@filename)
      buffer.source = source
      parser = Parser::CurrentRuby.new
      parser.parse(buffer)
    end

    # 根据位置和内容查找目标代码节点
    # @return [Parser::AST::Node, nil] 目标代码节点或nil
    def find_target_node
      finder = NodeFinder.new(@start_line, @start_column, @code_snippet)
      finder.find(@ast)
    end

    # 查找包含目标节点的方法定义
    # @return [Array(Parser::AST::Node, Boolean)] 方法节点和是否是类方法的标志
    def find_enclosing_method
      context_finder = MethodContextFinder.new(@target_node)
      context_finder.find(@ast)
    end

    # 转换AST：替换目标代码并插入新方法
    # @return [Parser::AST::Node] 转换后的AST
    def transform_ast
      # 创建新方法节点
      new_method_node = build_method_node(@tmp_func_name, @target_node, @is_class_method)

      # 替换原代码为方法调用
      ast_with_call = replace_node(@ast, @target_node, build_call_node(@tmp_func_name, @is_class_method))

      # 在合适位置插入新方法
      if @enclosing_def
        # 查找合适的父节点来插入新方法
        parent_node = find_insertion_parent(@ast, @enclosing_def, @is_class_method)
        insert_method_after_node(ast_with_call, parent_node || @enclosing_def, new_method_node)
      elsif ast_with_call.type == :begin
        # 顶层代码段，添加到末尾
        ast_with_call.updated(nil, ast_with_call.children + [new_method_node])
      else
        # 单语句顶层代码，包装为代码段并添加新方法
        Parser::AST::Node.new(:begin, [ast_with_call, new_method_node])
      end
    end

    # 创建方法定义节点
    # @param name [Symbol] 方法名
    # @param body_node [Parser::AST::Node] 方法体
    # @param is_class_method [Boolean] 是否是类方法
    # @return [Parser::AST::Node] 方法定义节点
    def build_method_node(name, body_node, is_class_method)
      if is_class_method
        # 创建类方法定义: def self.name ... end
        Parser::AST::Node.new(:defs, [
          Parser::AST::Node.new(:self, []),
          name.to_sym,
          Parser::AST::Node.new(:args, []), # 无参数
          body_node
        ])
      else
        # 创建实例方法定义: def name ... end
        Parser::AST::Node.new(:def, [
          name.to_sym,
          Parser::AST::Node.new(:args, []), # 无参数
          body_node
        ])
      end
    end

    # 创建方法调用节点
    # @param name [Symbol] 方法名
    # @param is_class_method [Boolean] 是否是类方法
    # @return [Parser::AST::Node] 方法调用节点
    def build_call_node(name, is_class_method)
      if is_class_method
        # 创建类方法调用: name (不需要self前缀，在同类中可以直接调用)
        Parser::AST::Node.new(:send, [nil, name.to_sym])
      else
        # 创建实例方法调用: name
        Parser::AST::Node.new(:send, [nil, name.to_sym])
      end
    end

    # 查找适合插入新方法的父节点
    # @param ast [Parser::AST::Node] 完整AST
    # @param method_node [Parser::AST::Node] 包含目标代码的方法节点
    # @param is_class_method [Boolean] 是否是类方法
    # @return [Parser::AST::Node, nil] 适合插入的父节点或nil
    def find_insertion_parent(ast, method_node, is_class_method)
      # 尝试获取方法所在的上下文
      context = MethodContextFinder.new(method_node)
      class_node, eigenclass_node = context.find_class_context(ast)

      # 为类方法选择正确的上下文
      if is_class_method
        eigenclass_node || class_node || method_node
      else
        method_node
      end
    end

    # 在指定节点后插入新方法
    # @param ast [Parser::AST::Node] 完整AST
    # @param target_node [Parser::AST::Node] 插入位置的目标节点
    # @param new_method [Parser::AST::Node] 要插入的新方法节点
    # @return [Parser::AST::Node] 修改后的AST
    def insert_method_after_node(ast, target_node, new_method)
      if ast.type == :begin
        # 在开始节点中寻找目标节点，并在其后插入
        idx = ast.children.index(target_node)
        if idx
          children = ast.children.dup
          children.insert(idx + 1, new_method)
          return Parser::AST::Node.new(:begin, children)
        end
      elsif ast.type == :def || ast.type == :defs
        # 单一方法定义，转换为序列并插入
        return Parser::AST::Node.new(:begin, [ast, new_method])
      elsif ast.type == :class || ast.type == :sclass
        # 类定义或单例类，在类体内插入
        insert_method_in_class(ast, new_method)
      else
        ast
      end
    end
    
    # 在类定义内插入方法
    # @param class_node [Parser::AST::Node] 类定义节点
    # @param new_method [Parser::AST::Node] 新方法节点
    # @return [Parser::AST::Node] 修改后的类定义节点
    def insert_method_in_class(class_node, new_method)
      # 获取类体
      class_body = class_node.children.last
      
      if class_body.nil?
        # 空类，添加方法作为第一个元素
        updated_body = Parser::AST::Node.new(:begin, [new_method])
        class_node.updated(nil, [*class_node.children[0..-2], updated_body])
      elsif class_body.is_a?(Parser::AST::Node) && class_body.type == :begin
        # 多语句类体，添加到末尾
        updated_body = class_body.updated(nil, class_body.children + [new_method])
        class_node.updated(nil, [*class_node.children[0..-2], updated_body])
      else
        # 单语句类体，转换为多语句并添加
        updated_body = Parser::AST::Node.new(:begin, [class_body, new_method])
        class_node.updated(nil, [*class_node.children[0..-2], updated_body])
      end
    end
    
    # 替换AST中的节点
    # @param ast [Parser::AST::Node] 要修改的AST
    # @param target [Parser::AST::Node] 要替换的目标节点
    # @param replacement [Parser::AST::Node] 替换节点
    # @return [Parser::AST::Node] 修改后的AST
    def replace_node(ast, target, replacement)
      return replacement if ast.equal?(target)
      
      if ast.is_a?(Parser::AST::Node)
        updated_children = ast.children.map { |c| replace_node(c, target, replacement) }
        ast.updated(nil, updated_children)
      else
        ast
      end
    end
    
    # 重命名方法定义和调用
    # @param ast [Parser::AST::Node] AST
    # @param old_name [Symbol] 旧方法名
    # @param new_name [Symbol] 新方法名
    # @return [Parser::AST::Node] 修改后的AST
    def rename_method(ast, old_name, new_name)
      if ast.is_a?(Parser::AST::Node)
        new_children = ast.children.map { |child| rename_method(child, old_name, new_name) }
        
        # 普通方法定义
        if ast.type == :def && ast.children[0] == old_name
          return ast.updated(nil, [new_name.to_sym, *ast.children[1..-1]])
        end
        
        # 类方法定义
        if ast.type == :defs && ast.children[1] == old_name
          return ast.updated(nil, [ast.children[0], new_name.to_sym, *ast.children[2..-1]])
        end
        
        # 方法调用
        if ast.type == :send && ast.children[1] == old_name
          return ast.updated(nil, [ast.children[0], new_name.to_sym, *ast.children[2..-1]])
        end
        
        ast.updated(nil, new_children)
      else
        ast
      end
    end
    
    # 获取用户输入的新函数名
    # @return [String, nil] 函数名或nil
    def get_user_function_name
      puts "请输入新函数名（合法 Ruby 方法名）："
      user_func_name = STDIN.gets&.strip
    
      if user_func_name.nil? || user_func_name !~ /^[a-z_][a-zA-Z0-9_]*$/
        puts "非法方法名。"
        return nil
      end
    
      user_func_name
    end
  end
end