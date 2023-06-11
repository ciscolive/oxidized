module Oxidized
  require "resolv"
  require "ostruct"
  require_relative "node/stats"

  class MethodNotFound < OxidizedError; end

  class ModelNotFound < OxidizedError; end

  # 备份节点相关属性
  class Node
    # 实例对象 -- 只读属性
    attr_reader :name, :ip, :model, :input, :output, :group, :auth, :prompt, :vars, :last, :repo
    # 实例对象 -- 可读写属性
    attr_accessor :running, :user, :email, :msg, :from, :stats, :retry, :err_type, :err_reason
    # 节点别名
    alias running? running

    # 实例化函数
    def initialize(opt)
      Oxidized.logger.debug "resolving DNS for #{opt[:name]}..."
      # remove the prefix if an IP Address is provided with one as IPAddr converts it to a network address.
      ip_addr, = opt[:ip].to_s.split("/")
      Oxidized.logger.debug "IPADDR #{ip_addr}"
      # 设定节点名称和IP地址
      @name = opt[:name]
      @ip = IPAddr.new(ip_addr).to_s rescue nil
      @ip    ||= Resolv.new.getaddress(@name) if Oxidized.config.resolve_dns?
      @ip    ||= @name
      @group = opt[:group]
      # 动态解析节点相关的模型、输入、输出和认证等信息
      # 节点关联的模块解析期间会自动实例化
      @model  = resolve_model(opt)
      @input  = resolve_input(opt)
      @output = resolve_output(opt)
      @auth   = resolve_auth(opt)
      @prompt = resolve_prompt(opt)
      # 节点本身相关变量
      @vars       = opt[:vars]
      @stats      = Stats.new
      @retry      = 0
      @repo       = resolve_repo(opt)
      @err_type   = nil
      @err_reason = nil
      # model instance needs to access node instance
      @model.node = self
    end

    # 执行节点配置备份任务 -- 返回状态和配置信息
    def run
      # 设定初始状态
      status, config = :fail, nil
      # 支持多种方式去登录设备
      @input.each do |input|
        # don't try input if model is missing config block, we may need strong config to class_name map
        method_name = input.to_s.split("::").last.downcase
        next unless @model.cfg[method_name] && !@model.cfg[method_name].empty?

        # 如果其中一种登录方式已成功拿到数据则跳出后续处理逻辑
        @model.input = input = input.new
        if (config = run_input(input))
          Oxidized.logger.debug "lib/oxidized/node.rb: #{input.class.name} ran for #{name} successfully"
          status = :success
          break
        else
          Oxidized.logger.debug "lib/oxidized/node.rb: #{input.class.name} failed for #{name}"
          status = :no_connection
        end
      end
      # 刷新登录方式
      @model.input = nil
      [status, config]
    end

    # 执行设备登录和配置备份
    def run_input(input)
      # 实例化数据字典
      rescue_fail = {}
      [input.class::RescueFail, input.class.superclass::RescueFail].each do |hash|
        hash.each do |level, errors|
          errors.each do |err|
            rescue_fail[err] = level
          end
        end
      end

      # 尝试登录设备并抓取运行配置
      # *rescue_fail.keys => err -- 设定为数组参数
      begin
        input.connect(self) && input.get
      rescue *rescue_fail.keys => err
        ctx = ""
        unless (level = rescue_fail[err.class])
          ctx   = err.class.ancestors.find { |e| rescue_fail.has_key?(e) }
          level = rescue_fail[ctx]
          ctx   = " (rescued #{ctx})"
        end
        Oxidized.logger.send(level, "#{ip} raised #{err.class}#{ctx} with msg #{err.message}")
        @err_type   = err.class.to_s
        @err_reason = err.message.to_s
        false
      rescue StandardError => err
        crash_dir  = Oxidized.config.crash.directory
        crash_file = Oxidized.config.crash.hostnames? ? name : ip.to_s
        FileUtils.mkdir_p(crash_dir) unless File.directory?(crash_dir)

        # 写入异常日志文件
        File.open File.join(crash_dir, crash_file), "w" do |fh|
          fh.puts Time.now.utc + (8 * 60 * 60)
          fh.puts "#{err.message} [#{err.class}]"
          fh.puts "-" * 50
          fh.puts err.backtrace
        end
        Oxidized.logger.error "#{ip} raised #{err.class} with msg #{err.message}, #{crash_file} saved"
        @err_type   = err.class.to_s
        @err_reason = err.message.to_s
        false
      end
    end

    # 节点序列化函数
    def serialize
      h = {
        name:      @name,
        full_name: @name,
        ip:        @ip,
        group:     @group,
        model:     @model.class.to_s,
        last:      nil,
        vars:      @vars,
        mtime:     @stats.mtime
      }
      # 修正数据
      h[:full_name] = [@group, @name].join("/") if @group
      if @last
        h[:last] = {
          start:  @last.start,
          end:    @last.end,
          status: @last.status,
          time:   @last.time
        }
      end
      h
    end

    # 节点运行快照
    def last=(job)
      if job
        ostruct        = OpenStruct.new
        ostruct.start  = job.start
        ostruct.end    = job.end
        ostruct.status = job.status
        ostruct.time   = job.time
        # 更新最新的备份数据
        @last = ostruct
      else
        @last = nil
      end
    end

    # 重置节点状态
    def reset
      @user  = @email = @msg = @from = nil
      @retry = 0
    end

    # 节点状态是否已修改
    def modified
      @stats.update_mtime
    end

    private

    # 提取设备登录成功提示符 节点配置>模块配置>全局配置
    def resolve_prompt(opt)
      opt[:prompt] || @model.prompt || Oxidized.config.prompt
    end

    # 提取账户密码
    def resolve_auth(opt)
      # Resolve configured username/password
      {
        username: resolve_key(:username, opt),
        password: resolve_key(:password, opt)
      }
    end

    # 设备登录方式
    def resolve_input(opt)
      inputs = resolve_key(:input, opt, Oxidized.config.input.default)

      # 支持多种登录方式同时工作，拿到数据及时退出
      inputs.split(/\s*,\s*/).map do |input|
        Oxidized.mgr.add_input(input) || raise(MethodNotFound, "#{input} not found for node #{ip}") unless Oxidized.mgr.input[input]

        Oxidized.mgr.input[input]
      end
    end

    # 设备登录成功配置保存方式
    # 支持单一的配置转储逻辑
    def resolve_output(opt)
      output = resolve_key(:output, opt, Oxidized.config.output.default)
      Oxidized.mgr.add_output(output) || raise(MethodNotFound, "#{output} not found for node #{ip}") unless Oxidized.mgr.output[output]

      # 输出方式只支持单一模式
      Oxidized.mgr.output[output]
    end

    # 设备登录驱动 -- 模型
    def resolve_model(opt)
      model = resolve_key(:model, opt)
      # 懒加载模板
      unless Oxidized.mgr.model[model]
        Oxidized.logger.debug "lib/oxidized/node.rb: Loading model #{model.inspect}"
        Oxidized.mgr.add_model(model) || raise(ModelNotFound, "#{model} not found for node #{ip}")
      end
      Oxidized.mgr.model[model].new
    end

    # 解析版本控制仓库地址
    def resolve_repo(opt)
      type = git_type(opt)
      return nil unless type

      remote_repo = Oxidized.config.output.send(type).repo
      if remote_repo.is_a?(::String)
        if Oxidized.config.output.send(type).single_repo? || @group.nil?
          remote_repo
        else
          File.join(File.dirname(remote_repo), @group + ".git")
        end
      else
        remote_repo[@group]
      end
    end

    # 解析节点键值对配置，优先级：节点>模型>属组>全局
    def resolve_key(key, opt, global = nil)
      # resolve key, first get global, then get group then get node config
      key_sym = key.to_sym
      key_str = key.to_s
      value   = global
      Oxidized.logger.debug "node.rb: resolving node key '#{key}', with passed global value of '#{value}' and node value '#{opt[key_sym]}'"

      # global -- 全局配置
      if !value && Oxidized.config.has_key?(key_str)
        value = Oxidized.config[key_str]
        Oxidized.logger.debug "node.rb: setting node key '#{key}' to value '#{value}' from global"
      end

      # group -- 组配置
      if Oxidized.config.groups.has_key?(@group) && Oxidized.config.groups[@group].has_key?(key_str)
        value = Oxidized.config.groups[@group][key_str]
        Oxidized.logger.debug "node.rb: setting node key '#{key}' to value '#{value}' from group"
      end

      # model -- 模块配置
      if Oxidized.config.models.has_key?(@model.class.name.to_s.downcase) && Oxidized.config.models[@model.class.name.to_s.downcase].has_key?(key_str)
        value = Oxidized.config.models[@model.class.name.to_s.downcase][key_str]
        Oxidized.logger.debug "node.rb: setting node key '#{key}' to value '#{value}' from model"
      end

      # node -- 节点配置
      value = opt[key_sym] || value
      Oxidized.logger.debug "node.rb: returning node key '#{key}' with value '#{value}'"
      value
    end

    # 判定是否为 git 类型
    def git_type(opt)
      type = opt[:output] || Oxidized.config.output.default
      return nil unless type[0..2] == "git"

      type
    end
  end
end
