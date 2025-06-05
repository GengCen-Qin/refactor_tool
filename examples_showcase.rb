#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require_relative 'lib/extract_method'
require 'fileutils'
require 'stringio'

# 创建临时目录
TMP_DIR = '/tmp/extract_method_examples'
FileUtils.mkdir_p(TMP_DIR)

# 清理函数
def cleanup
  FileUtils.rm_rf(TMP_DIR)
end

# 注册退出时清理
at_exit { cleanup }

# 运行一个示例并展示前后对比
def run_example(title, code, target_snippet, line, column, new_method_name)
puts "\n#{'=' * 80}"
puts "示例：#{title}"
puts "=" * 80
  
# 创建文件
filename = "#{TMP_DIR}/example_#{title.gsub(/\s+/, '_').downcase}.rb"
File.write(filename, code)
  
puts "\n【重构前】"
puts "-" * 80
puts code
  
begin
  # 执行方法抽取，直接传入新方法名
  result = ExtractMethod.extract(filename, target_snippet, line, column, new_method_name)
    
  if result
    puts "\n【重构后】"
    puts "-" * 80
    puts File.read(filename)
    puts "\n✅ 成功：代码已重构，抽取了新方法 '#{new_method_name}'"
  else
    puts "\n❌ 失败：方法抽取未成功"
  end
rescue => e
  puts "\n❌ 错误：#{e.message}"
  puts e.backtrace.join("\n")
end
end

puts "## 方法抽取工具示例 ##"
puts "这个脚本展示了各种代码场景中的方法抽取操作。"

# 示例1: 从简单的实例方法中抽取一行代码
example1 = <<~RUBY
  class Calculator
    def calculate_total(items)
      result = 0
      apply_tax(result, items)
      format_currency(result)
    end
  end
RUBY
run_example("从实例方法中抽取单行代码", example1, "apply_tax(result, items)", 4, 4, "calculate_with_tax")

# 示例2: 从类方法中抽取代码
example2 = <<~RUBY
  class PaymentProcessor
    def self.process_payment(amount, card)
      validate_card(card)
      apply_processing_fee(amount)
      charge_card(card, amount)
      send_receipt(card.email, amount)
    end
  end
RUBY
run_example("从类方法中抽取代码", example2, "apply_processing_fee(amount)", 4, 4, "prepare_amount")

# 示例3: 从class << self风格的类方法抽取代码
example3 = <<~RUBY
  class Logger
    class << self
      def log_event(event_type, details)
        timestamp = Time.now.iso8601
        formatted_message = "\#{timestamp} [\#{event_type.upcase}] \#{details}"
        append_to_log_file(formatted_message)
        notify_subscribers(event_type, details) if critical?(event_type)
      end
    end
  end
RUBY
run_example("从class << self风格的类方法抽取代码", example3, "timestamp = Time.now.iso8601", 4, 6, "generate_timestamp")

# 示例4: 抽取包含控制流的代码
example4 = <<~RUBY
  class DataProcessor
    def process(data)
      return [] if data.nil?
      
      result = []
      data.each do |item|
        if item.valid?
          transformed = transform_item(item)
          result << transformed if transformed
        end
      end
      
      finalize_results(result)
    end
  end
RUBY
run_example("抽取包含转换逻辑的代码", example4, "transformed = transform_item(item)", 8, 8, "transform_valid_item")

puts "\n完成所有示例展示。"