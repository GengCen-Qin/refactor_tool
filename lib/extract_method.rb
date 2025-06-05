#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
require 'parser/current'
require 'unparser'

# 加载模块文件
require_relative 'extract_method/node_finder'
require_relative 'extract_method/method_context_finder'
require_relative 'extract_method/extractor'

# 方法抽取工具入口模块
module ExtractMethod
  # 主入口方法
  # @param filename [String] 源代码文件路径
  # @param code_snippet [String] 要抽取的代码片段
  # @param start_line [Integer|String] 代码片段的起始行
  # @param start_column [Integer|String] 代码片段的起始列
  # @param new_method_name [String] 可选的新方法名，若不提供则会通过命令行交互获取
  # @return [Boolean] 操作是否成功
  def self.extract(filename, code_snippet, start_line, start_column, new_method_name = nil)
    Extractor.new(filename, code_snippet, start_line.to_i, start_column.to_i, new_method_name).perform_extraction
  end
end

# 仅当作为脚本运行时执行，被require时不执行
if __FILE__ == $0
  # 检查参数
  if ARGV.length < 4
    puts "Usage: #{$0} <filename> <code_snippet> <start_line> <start_column>"
    exit 1
  end

  filename, code_snippet, start_line, start_column = ARGV
  
  # 执行方法抽取
  exit 1 unless ExtractMethod.extract(filename, code_snippet, start_line, start_column)
end