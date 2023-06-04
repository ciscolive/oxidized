module Oxidized
  class Input
    module CLI
      # 类对象属性
      attr_reader :node

      # 实例化函数
      def initialize
        @post_login = []
        @pre_logout = []
        @username   = nil
        @password   = nil
        @exec       = nil
      end

      # 获取运行配置
      def get
        connect_cli
        d = node.model.get
        disconnect
        d
      rescue PromptUndetect
        disconnect
        raise
      end

      # 新建会话
      # TODO 考虑是否和 @pre_logout方法内逻辑保持一致
      # block ? block.call : (cmd command, nil)
      def connect_cli
        Oxidized.logger.debug "lib/oxidized/input/cli.rb: Running post_login commands at #{node.name}"
        @post_login.each do |command, block|
          Oxidized.logger.debug "lib/oxidized/input/cli.rb: Running post_login command: #{command.inspect}, block: #{block.inspect} at #{node.name}"
          block ? block.call : (cmd command)
        end
      end

      # 删除会话
      def disconnect_cli
        Oxidized.logger.debug "lib/oxidized/input/cli.rb Running pre_logout commands at #{node.name}"
        @pre_logout.each do |command, block|
          Oxidized.logger.debug "lib/oxidized/input/cli.rb: Running pre_logout command: #{command.inspect}, block: #{block.inspect} at #{node.name}"
          block ? block.call : (cmd command, nil)
        end
        # @pre_logout.each { |command, block| block ? block.call : (cmd command, nil) }
      end

      # 登录后执行脚本
      def post_login(cmd = nil, &block)
        return if @exec

        @post_login << [cmd, block]
      end

      # 登出前执行脚本
      def pre_logout(cmd = nil, &block)
        return if @exec

        @pre_logout << [cmd, block]
      end

      # 设置用户提示符
      def username(regex = /^(Username|login)/i)
        @username || (@username = regex)
      end

      # 设置密码提示符
      def password(regex = /^Password/i)
        @password || (@password = regex)
      end

      # 设备登录逻辑
      def login
        # 设置捕捉提示符容器
        match_re = [@node.prompt]
        match_re << @username if @username
        match_re << @password if @password

        # 直到正常捕捉到设备登录成功提示符
        # expect(match_re) 子模块具体实现
        until (match = expect(match_re)) == @node.prompt
          # 自动交互输入账户和密码 -- 不需要捕捉回显也就不会等待回显超时
          cmd(@node.auth[:username], nil) if match == @username
          cmd(@node.auth[:password], nil) if match == @password
          match_re.delete match
        end
      end
    end
  end
end
