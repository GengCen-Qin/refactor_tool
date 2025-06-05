#!/usr/bin/env ruby
require 'tempfile'
require 'fileutils'

module TextBasedExtract
  class Extractor
    # 初始化方法提取器
    # @param filename [String] 源代码文件路径
    # @param code_snippet [String] 要抽取的代码片段
    # @param start_line [Integer] 代码片段的起始行号
    # @param start_column [Integer] 代码片段的起始列号
    # @param new_method_name [String] 可选的新方法名，若不提供则会通过命令行交互获取
    def initialize(filename, code_snippet, start_line, start_column, new_method_name = nil)
      @filename = filename
      @code_snippet = normalize_snippet(code_snippet)
      @start_line = start_line.to_i
      @start_column = start_column.to_i
      @new_method_name = new_method_name
    end

    # 执行代码抽取
    # @return [Boolean] 操作是否成功
    def perform_extraction
      # 检查文件是否存在
      unless File.exist?(@filename)
        puts "文件 #{@filename} 不存在。"
        return false
      end

      # 读取源文件内容
      source_lines = File.readlines(@filename, chomp: true)

      # 找到代码片段位置
      code_location = find_code_location(source_lines, @code_snippet, @start_line)
      unless code_location
        puts '未能在文件中找到指定代码片段。'
        return false
      end

      # 找到包含代码片段的方法
      method_location = find_enclosing_method(source_lines, code_location)
      unless method_location
        puts '未能找到包含代码片段的方法。'
        return false
      end

      # 确定是否是类方法
      is_class_method = check_if_class_method(source_lines, method_location)

      # 获取新方法名
      method_name = @new_method_name || get_user_method_name
      return false unless method_name && valid_method_name?(method_name)

      # 提取代码片段
      extracted_code = extract_code(source_lines, code_location)

      # 创建方法调用
      method_call = create_method_call(method_name)

      # 创建新方法定义
      new_method = create_method_definition(method_name, extracted_code, is_class_method)

      # 替换源代码中的片段并插入新方法
      updated_source = replace_code_with_call(source_lines, code_location, method_call)
      updated_source = insert_method_definition(
        updated_source,
        method_location[:end_line],
        new_method,
        get_indentation(source_lines, method_location[:start_line])
      )

      # 写回文件
      write_to_file(@filename, updated_source)

      puts "成功将代码片段提取到方法 '#{method_name}' 中。"
      true
    end

    private

    # 规范化代码片段，移除首尾空格，标准化缩进
    # @param snippet [String] 原始代码片段
    # @return [String] 规范化后的片段
    def normalize_snippet(snippet)
      # 拆分成行
      lines = snippet.split("\n")

      # 确定最小缩进
      min_indent = lines.select { |line| line.strip.length > 0 }
                        .map { |line| line[/^\s*/].length }
                        .min || 0

      # 移除公共缩进
      lines.map do |line|
        line.empty? ? line : line[min_indent..-1]
      end.join("\n")
    end

    # 在源代码中查找代码片段的位置
    # @param source_lines [Array<String>] 源代码行
    # @param snippet [String] 要查找的代码片段
    # @param hint_line [Integer] 大致行号提示
    # @return [Hash, nil] 包含开始和结束行号的哈希，或nil
    def find_code_location(source_lines, snippet, hint_line)
      snippet_lines = snippet.split("\n")
      first_line = snippet_lines.first

      # 从提示行附近开始搜索
      start_search = [0, hint_line - 5].max
      end_search = [source_lines.length - 1, hint_line + 5].min

      (start_search..end_search).each do |i|
        # 检查第一行是否匹配
        next unless source_lines[i].include?(first_line)

        # 检查后续行是否匹配
        match = true
        snippet_lines.each_with_index do |snippet_line, j|
          source_index = i + j
          if source_index >= source_lines.length || !source_lines[source_index].include?(snippet_line)
            match = false
            break
          end
        end

        if match
          return {
            start_line: i + 1, # 转为1-based索引
            end_line: i + snippet_lines.length
          }
        end
      end

      nil
    end

    # 查找包含指定代码的方法
    # @param source_lines [Array<String>] 源代码行
    # @param code_location [Hash] 代码位置
    # @return [Hash, nil] 方法位置，包含开始和结束行号，或nil
    def find_enclosing_method(source_lines, code_location)
      # 从代码位置向上搜索方法定义
      method_start = nil
      method_end = nil

      # 向上查找方法开始
      (code_location[:start_line] - 1).downto(0) do |i|
        line = source_lines[i]
        if line =~ /^\s*(def|def\s+self\.)/
          method_start = i + 1 # 转为1-based索引
          break
        end
      end

      return nil unless method_start

      # 向下查找方法结束
      ((code_location[:end_line] - 1)...source_lines.length).each do |i|
        if source_lines[i] =~ /^\s*end\b/
          method_end = i + 1 # 转为1-based索引
          break
        end
      end

      return nil unless method_end

      {
        start_line: method_start,
        end_line: method_end
      }
    end

    # 检查是否是类方法
    # @param source_lines [Array<String>] 源代码行
    # @param method_location [Hash] 方法位置
    # @return [Boolean] 是否是类方法
    def check_if_class_method(source_lines, method_location)
      method_def_line = source_lines[method_location[:start_line] - 1]
      method_def_line.include?('def self.')
    end

    # 从源代码中提取代码片段
    # @param source_lines [Array<String>] 源代码行
    # @param code_location [Hash] 代码位置
    # @return [Array<String>] 提取的代码行
    def extract_code(source_lines, code_location)
      # 提取代码行并保留原始缩进
      source_lines[(code_location[:start_line] - 1)..(code_location[:end_line] - 1)]
    end

    # 创建方法调用代码
    # @param method_name [String] 方法名
    # @return [String] 方法调用代码
    def create_method_call(method_name)
      method_name
    end

    # 创建新方法定义
    # @param method_name [String] 方法名
    # @param code_lines [Array<String>] 代码行
    # @param is_class_method [Boolean] 是否是类方法
    # @return [String] 方法定义代码
    def create_method_definition(method_name, code_lines, is_class_method)
      prefix = is_class_method ? 'def self.' : 'def '

      # 格式化方法体，确保正确的缩进
      indented_code = code_lines.join("\n")

      <<~METHOD.chomp

        #{prefix}#{method_name}
          #{indented_code}
        end
      METHOD
    end

    # 替换源代码中的片段为方法调用
    # @param source_lines [Array<String>] 源代码行
    # @param code_location [Hash] 代码位置
    # @param method_call [String] 方法调用代码
    # @return [Array<String>] 更新后的源代码行
    def replace_code_with_call(source_lines, code_location, method_call)
      result = source_lines[0..(code_location[:start_line] - 2)] # 保留前面的代码

      # 获取缩进
      indentation = if code_location[:start_line] <= source_lines.length
                      source_lines[code_location[:start_line] - 1][/^\s*/]
                    else
                      '  ' # 默认缩进
                    end

      # 添加替换的方法调用
      result << "#{indentation}#{method_call}"

      # 添加后面的代码
      result.concat(source_lines[code_location[:end_line]..-1]) if code_location[:end_line] < source_lines.length

      result
    end

    # 在指定行后插入新方法定义
    # @param source_lines [Array<String>] 源代码行
    # @param after_line [Integer] 插入位置
    # @param method_definition [String] 方法定义代码
    # @param indentation [String] 缩进
    # @return [Array<String>] 更新后的源代码行
    def insert_method_definition(source_lines, after_line, method_definition, indentation)
      # 将方法定义拆分成行并应用缩进
      method_lines = method_definition.split("\n").map do |line|
        line.empty? ? line : "#{indentation}#{line}"
      end

      # 在指定位置插入
      result = source_lines[0..(after_line - 1)]
      result.concat(method_lines)
      result.concat(source_lines[after_line..-1]) if after_line < source_lines.length

      result
    end

    # 获取指定行的缩进
    # @param source_lines [Array<String>] 源代码行
    # @param line_number [Integer] 行号
    # @return [String] 缩进字符串
    def get_indentation(source_lines, line_number)
      return '  ' if line_number < 1 || line_number > source_lines.length

      source_lines[line_number - 1][/^\s*/] || ''
    end

    # 写入文件
    # @param filename [String] 文件名
    # @param content [Array<String>] 内容行
    def write_to_file(filename, content)
      File.write(filename, content.join("\n") + "\n")
    end

    # 验证方法名是否合法
    # @param method_name [String] 方法名
    # @return [Boolean] 是否合法
    def valid_method_name?(method_name)
      if method_name =~ /^[a-z_][a-zA-Z0-9_]*$/
        true
      else
        puts "非法方法名：#{method_name}"
        puts '方法名必须以小写字母或下划线开头，只能包含字母、数字和下划线。'
        false
      end
    end

    # 获取用户输入的方法名
    # @return [String, nil] 方法名或nil
    def get_user_method_name
      puts '请输入新函数名（合法 Ruby 方法名）：'
      method_name = STDIN.gets&.strip

      if method_name.nil? || method_name.empty?
        puts '未能获取有效的方法名。'
        return nil
      end

      method_name
    end
  end
end
