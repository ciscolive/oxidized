require "strscan"
require_relative "outputs"

module Oxidized
  class Model
    using Refinements

    # 加载其他模块方法
    include Oxidized::Config::Vars

    # Oxidized::Model 类方法
    class << self
      # 重写继承方法逻辑 -- 元编程
      def inherited(klass)
        super

        # 重写继承方法 -- 动态设置类变量
        # Hash.new { |h, k| h[k] = [] } 是一个具有默认值的哈希表（Hash），其中默认值是一个空数组（[]）。
        # 当访问哈希表中不存在的键时，将使用提供的块代码来生成默认值并将其分配给该键。
        # 这意味着当你访问哈希表中不存在的键时，会自动创建一个空数组作为该键的默认值。

        # Hash.new { |h, k| h[k] = [] } 可以提供动态创建默认值的功能，
        # 而 Hash.new 只能提供静态的默认值。使用具有块的Hash.new 可以更方便地处理需要默认值为数组等可变对象的情况。
        if klass.superclass == Oxidized::Model
          klass.instance_variable_set(:@cmd, Hash.new { |h, k| h[k] = [] })
          klass.instance_variable_set(:@cfg, Hash.new { |h, k| h[k] = [] })
          klass.instance_variable_set(:@procs, Hash.new { |h, k| h[k] = [] })
          klass.instance_variable_set(:@expect, [])
          klass.instance_variable_set(:@comment, nil)
          klass.instance_variable_set(:@prompt, nil)
        else
          # we're subclassing some existing model, take its variables
          # 继承自其他子类模块，比如思科 NXOS 继承自 IOS
          instance_variables.each do |var|
            iv = instance_variable_get(var)
            klass.instance_variable_set(var, iv.dup)
            @cmd[:cmd] = iv[:cmd].dup if var.to_s == "@cmd"
          end
        end
      end

      # 模块注释行
      def comment(str = "# ")
        @comment = if block_given?
                     yield
                   elsif !@comment
                     str
                   else
                     @comment
                   end
      end

      # 设备登录提示符
      def prompt(regex = nil)
        @prompt = regex || @prompt
      end

      # *methods 表示可变长参数(比如设定 telnet ssh) -- 脚本容器
      # **args 表示关键字参数 -- 逻辑判断
      # &block 表示接收代码块 -- 交互逻辑
      def cfg(*methods, **args, &block)
        [methods].flatten.each do |method|
          process_args_block(@cfg[method.to_s], args, block)
        end
      end

      # 设备脚本
      def cfgs
        @cfg
      end

      # 执行脚本 -- 符号类型和字符串类型，支持正则表达式
      # cmd_arg -- 实际要执行的脚本或脚本类型
      # **args 关键字参数
      def cmd(cmd_arg = nil, regex_re = nil, **args, &block)
        if cmd_arg.instance_of?(Symbol)
          process_args_block(@cmd[cmd_arg], args, block)
        else
          # 每个命令执行的代码块不一样，此处同时传递脚本、期望回显正则和代码块
          process_args_block(@cmd[:cmd], args, [cmd_arg, regex_re, block])
        end
        Oxidized.logger.debug "lib/oxidized/model/model.rb Added #{cmd_arg} to the commands list"
      end

      # 模型相关脚本
      def cmds
        @cmd
      end

      # 根据正则执行相关脚本 -- 存储正则和关联的代码块
      def expect(regex, **args, &block)
        process_args_block(@expect, args, [regex, block])
      end

      # 正则属性
      def expects
        @expect
      end

      # @author Saku Ytti <saku@ytti.fi>
      # @since 0.0.39
      # @return [Hash] hash proc procs :pre+:post to be prepended/postfixed to output
      attr_reader :procs

      # calls the block at the end of the model, prepending the output of the
      # block to the output string
      #
      # @author Saku Ytti <saku@ytti.fi>
      # @since 0.0.39
      # @yield expects block which should return [String]
      # @return [void]
      def pre(**args, &block)
        process_args_block(@procs[:pre], args, block)
      end

      # calls the block at the end of the model, adding the output of the block
      # to the output string
      #
      # @author Saku Ytti <saku@ytti.fi>
      # @since 0.0.39
      # @yield expects block which should return [String]
      # @return [void]
      def post(**args, &block)
        process_args_block(@procs[:post], args, block)
      end

      private

      # 根据入参类型动态执行 -- 默认往 target push 压入数据
      # args -- 关键字参数
      def process_args_block(target, args, block)
        if args[:clear]
          if block.instance_of?(Array)
            target.reject! { |k, _| k == block[0] }
            target.push(block)
          else
            target.replace([block])
          end
        else
          method = args[:prepend] ? :unshift : :push
          target.send(method, block)
        end
      end
    end

    # 实例属性
    attr_accessor :input, :node

    # 执行脚本 -- 支持脚本输入后同时捕捉回显结果，如果未成功捕获则抛出异常
    def cmd(string, regex_re = nil, &block)
      Oxidized.logger.debug "lib/oxidized/model/model.rb Executing #{string}"

      # TODO: 执行脚本期间支持正则表达式 -- 如果未捕捉到回显则抛出异常
      out = regex_re ? @input.cmd(string, regex_re) : @input.cmd(string)
      return false unless out

      out = out.b unless Oxidized.config.input.utf8_encoded?

      # 实例对象执行脚本期间 -- 修饰逻辑
      # 将向代码块提供 |out, string| 参数
      self.class.cmds[:all].each do |all_block|
        out = instance_exec(out, string, &all_block)
      end

      # 是否项目配置移除敏感信息属性
      # 将向代码块提供 |out, string| 参数
      if vars :remove_secret
        self.class.cmds[:secret].each do |all_block|
          out = instance_exec(out, string, &all_block)
        end
      end

      # 动态加载代码块逻辑 |out| -> block
      # 将脚本执行回显作为输入提供到代码块
      out = instance_exec(out, &block) if block
      process_cmd_output(out, string)
    end

    # 设备登录脚本输出
    def output
      @input.output
    end

    # 交互执行脚本
    def send(data)
      @input.send(data)
    end

    # 设定正则执行的代码块 -- 设置正则表达式和代码块到 对象 @expects
    def expect(regex, &block)
      self.class.expect(regex, &block)
    end

    # 设备相关的配置
    def cfg
      self.class.cfgs
    end

    # 设备提示符
    def prompt
      self.class.prompt
    end

    # 根据回调函数的参数个数执行回调函数并将结果赋值给 data
    # 同时传递脚本和正则表达式
    def expects(data)
      self.class.expects.each do |re, cb|
        if data.match re
          data = cb.arity == 2 ? instance_exec([data, re], &cb) : instance_exec(data, &cb)
        end
      end
      data
    end

    # 获取设备运行配置
    def get
      Oxidized.logger.debug "lib/oxidized/model/model.rb Collecting commands' outputs"
      # 实例化脚本输出 -- 数组
      outputs = Outputs.new
      procs   = self.class.procs

      # 运行时脚本 -- 至上而下依次执行脚本
      self.class.cmds[:cmd].each do |command, regex_re, block|
        out = cmd(command, regex_re, &block)
        return false unless out

        outputs << out
      end

      # 前置脚本 -- 动态执行代码块
      procs[:pre].each do |pre_proc|
        outputs.unshift process_cmd_output(instance_eval(&pre_proc), "")
      end

      # 后置脚本 -- 动态执行代码块
      procs[:post].each do |post_proc|
        outputs << process_cmd_output(instance_eval(&post_proc), "")
      end

      outputs
    end

    # 为特定的字串输入注解符
    def comment(str)
      data = ""
      str.each_line do |line|
        data << self.class.comment << line
      end
      data
    end

    # xml 配置注释
    def xmlcomment(str)
      # XML Comments start with <!-- and end with -->
      #
      # Because it's illegal for the first or last characters of a comment
      # to be a -, i.e. <!--- or ---> are illegal, and also to improve
      # readability, we add extra spaces after and before the beginning
      # and end of comment markers.
      #
      # Also, XML Comments must not contain --. So we put a space between
      # any double hyphens, by replacing any - that is followed by another -
      # with '- '
      data = ""
      str.each_line do |_line|
        data << "<!-- " << str.gsub(/-(?=-)/, "- ").chomp << " -->\n"
      end
      data
    end

    def screenscrape
      @input.class.to_s.match(/Telnet/) || vars(:ssh_no_exec)
    end

    private

    # 设置脚本信息
    def process_cmd_output(output, command)
      output = String.new("") unless output.instance_of?(String)
      output.set_cmd(command)
      output
    end
  end
end
