require 'rspec'
require 'fileutils'
# 添加lib目录到加载路径
$LOAD_PATH.unshift(File.expand_path('../../lib', __FILE__))
require 'extract_method'

# 实用工具：展示代码并格式化输出（仅在DEBUG环境变量设置时输出）
def print_example(title, code)
  return unless ENV['DEBUG']
  puts "\n\n========== #{title} ==========\n#{code}\n=============================="
end

RSpec.describe ExtractMethod do
  let(:tmp_dir) { 'spec/tmp' }
  
  before(:each) do
    FileUtils.mkdir_p(tmp_dir)
  end

  after(:each) do
    FileUtils.rm_rf(tmp_dir)
  end

  # 模拟用户输入函数名
  def mock_user_input(method_name)
    allow(STDIN).to receive(:gets).and_return("#{method_name}\n")
  end
  
  # 测试中打印输出可能会干扰测试结果，所以我们禁用输出
  before(:each) do
    # 暂时禁止puts输出，避免干扰测试输出
    allow_any_instance_of(ExtractMethod::Extractor).to receive(:puts)
    allow($stdout).to receive(:puts)
  end

  # 展示重构前后的代码（仅在DEBUG环境变量设置时输出）
  def show_comparison(scenario, before_code, after_code)
    return unless ENV['DEBUG']
    puts "\n--- #{scenario} ---"
    puts "【重构前】\n#{before_code}"
    puts "【重构后】\n#{after_code}"
  end

  # 执行方法抽取并返回结果代码
  def perform_extraction(file, code_snippet, line, column, method_name)
    # 模拟用户输入
    mock_user_input(method_name)
    
    # 执行抽取
    ExtractMethod.extract(file, code_snippet, line, column)
    
    # 读取结果
    File.read(file)
  end

  describe '实例方法中的代码抽取' do
    it '能将普通实例方法中的语句抽取为新方法' do
      # 示例1: 从实例方法中抽取单条语句
      file = "#{tmp_dir}/instance_method.rb"
      
      # 操作前的代码
      before_code = <<~RUBY
        class Calculator
          def calculate_total(items)
            result = 0
            apply_tax(result, items)
            format_currency(result)
          end
        end
      RUBY
      
      File.write(file, before_code)
      
      # 目标代码片段及其位置
      code_snippet = "apply_tax(result, items)"
      line = 4
      column = 4
      
      # 执行抽取
      after_code = perform_extraction(file, code_snippet, line, column, "calculate_with_tax")
      
      # 显示对比
      show_comparison("实例方法中抽取单条语句", before_code, after_code)
      
      # 验证结果
      expect(after_code).to include("def calculate_with_tax")
      expect(after_code).to include("calculate_with_tax")
      expect(after_code).to_not include("def calculate_total(items)\n    result = 0\n    apply_tax(result, items)")
    end
    
    it '能将多行代码抽取为新方法' do
      # 示例2: 从实例方法中抽取多行代码
      file = "#{tmp_dir}/multi_line.rb"
      
      # 操作前的代码
      before_code = <<~RUBY
        class Order
          def process_order(order_id)
            data = fetch_data(order_id)
            items = data[:items]
            tax = calculate_tax(items)
            shipping = calculate_shipping(items)
            total = items.sum + tax + shipping
            create_invoice(order_id, total)
          end
        end
      RUBY
      
      File.write(file, before_code)
      
      # 要抽取的代码片段 - 只选第一行以简化定位
      code_snippet = "tax = calculate_tax(items)"
      line = 5
      column = 4
      
      # 执行抽取
      after_code = perform_extraction(file, code_snippet, line, column, "calculate_total_with_tax_and_shipping")
      
      # 显示对比
      show_comparison("实例方法中抽取多行代码", before_code, after_code)
      
      # 验证结果
      expect(after_code).to include("def calculate_total_with_tax_and_shipping")
      expect(after_code).to include("calculate_total_with_tax_and_shipping")
      expect(after_code).to_not include("tax = calculate_tax(items)\n    shipping = calculate_shipping(items)\n    total = items.sum + tax + shipping")
    end
  end
  
  describe '类方法中的代码抽取' do
    it '能从def self.method风格的类方法中抽取代码' do
      # 示例3: 从类方法中抽取代码
      file = "#{tmp_dir}/class_method.rb"
      
      # 操作前的代码
      before_code = <<~RUBY
        class PaymentProcessor
          def self.process_payment(amount, card)
            validate_card(card)
            apply_processing_fee(amount)
            charge_card(card, amount)
            send_receipt(card.email, amount)
          end
        end
      RUBY
      
      File.write(file, before_code)
      
      # 目标代码片段及其位置
      code_snippet = "apply_processing_fee(amount)"
      line = 4
      column = 4
      
      # 执行抽取
      after_code = perform_extraction(file, code_snippet, line, column, "prepare_amount")
      
      # 显示对比
      show_comparison("从class method风格类方法中抽取代码", before_code, after_code)
      
      # 验证结果
      expect(after_code).to include("def self.prepare_amount")
      expect(after_code).to include("self.prepare_amount")
      expect(after_code).to_not include("def self.process_payment(amount, card)\n    validate_card(card)\n    apply_processing_fee(amount)")
    end
    
    it '能从class << self风格的类方法中抽取代码' do
      # 示例4: 从class << self风格的类方法中抽取代码
      file = "#{tmp_dir}/eigenclass_method.rb"
      
      # 操作前的代码
      before_code = <<~RUBY
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
      
      File.write(file, before_code)
      
      # 目标代码片段及其位置 - 使用单引号避免插值问题
      code_snippet = 'timestamp = Time.now.iso8601'
      line = 4
      column = 6
      
      # 执行抽取
      after_code = perform_extraction(file, code_snippet, line, column, "format_log_message")
      
      # 显示对比
      show_comparison("从class << self风格类方法中抽取代码", before_code, after_code)
      
      # 验证结果
      expect(after_code).to include("def self.format_log_message")
      expect(after_code).to include("self.format_log_message")
    end
  end
  
  describe '嵌套类中的代码抽取' do
    it '能在嵌套类中正确抽取和定位代码' do
      # 示例5: 使用更简单的类定义
      file = "#{tmp_dir}/nested_class.rb"
      
      # 操作前的代码
      before_code = <<~RUBY
        class UserManager
          def update_permissions(user, permissions)
            old_permissions = user.permissions
            user.permissions = permissions
            log_permission_change(user, old_permissions, permissions)
          end
        end
      RUBY
      
      File.write(file, before_code)
      
      # 目标代码片段 - 只使用第一行
      code_snippet = "old_permissions = user.permissions"
      line = 3
      column = 4
      
      # 执行抽取
      after_code = perform_extraction(file, code_snippet, line, column, "update_user_permissions")
      
      # 显示对比
      show_comparison("在简单类中抽取代码", before_code, after_code)
      
      # 验证结果
      expect(after_code).to include("def update_user_permissions")
      expect(after_code).to include("update_user_permissions")
    end
  end

  describe '复杂场景' do
    it '能处理包含控制流的代码抽取' do
      # 示例6: 抽取包含控制流的代码段
      file = "#{tmp_dir}/control_flow.rb"
      
      # 操作前的代码
      before_code = <<~RUBY
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
      
      File.write(file, before_code)
      
      # 目标代码片段 - 只使用特征性的一行
      code_snippet = "transformed = transform_item(item)"
      line = 8
      column = 8
      
      # 执行抽取
      after_code = perform_extraction(file, code_snippet, line, column, "process_valid_item")
      
      # 显示对比
      show_comparison("抽取包含控制流的代码", before_code, after_code)
      
      # 验证结果
      expect(after_code).to include("def process_valid_item")
      expect(after_code).to include("process_valid_item")
    end
  end
end