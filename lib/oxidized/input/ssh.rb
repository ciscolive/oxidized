module Oxidized
  require "net/ssh"
  require "net/ssh/proxy/command"
  require "timeout"
  require "oxidized/input/cli"

  class SSH < Input
    RescueFail = {
      debug: [
        Net::SSH::Disconnect
      ],
      warn: [
        RuntimeError,
        Net::SSH::AuthenticationFailed
      ]
    }.freeze

    # 加载模块方法作为该类实例方法 -- 包括实例方法
    # 如果使用 extend 则为类方法
    include Input::CLI

    class NoShell < OxidizedError; end

    # 连接设备 -- 必须提供节点信息
    # 设置终端信息
    def connect(node)
      @node = node
      @output = ""
      @pty_options = {term: "vt100"}
      # SSH 会话相关配置 -- 比如设置登录权限账户等
      @node.model.cfg["ssh"].each { |cb| instance_exec(&cb) }
      @log = File.open(Oxidized::Config::LOG_DIR + "/#{@node.ip}_ssh.log", "w") if Oxidized.config.input.debug?

      # 实例化 ssh 对象并尝试登录设备
      Oxidized.logger.debug "lib/oxidized/input/ssh.rb: Connecting to #{@node.name}"
      @ssh = Net::SSH.start(@node.ip, @node.auth[:username], make_ssh_opts)
      unless @exec
        shell_open @ssh
        begin
          login
        rescue Timeout::Error
          raise PromptUndetect, [@output, "not matching configured prompt during login device", @node.prompt].join(" ")
        end
      end
      connected?
    end

    # 是否已经连接设备
    def connected?
      @ssh && !@ssh&.closed?
    end

    # 通过 SSH 下发脚本，支持交互式逻辑
    def cmd(cmd, expect = node.prompt)
      Oxidized.logger.debug "lib/oxidized/input/ssh.rb #{cmd} @#{node.name} with expect: #{expect.inspect}"
      if @exec
        @ssh.exec! cmd
      else
        cmd_shell(cmd, expect).gsub(/\r\n/, "\n")
      end
    end

    # 直接发送脚本不捕捉回显
    def send(data)
      @ses.send_data data
    end

    # 类对象属性
    attr_reader :output

    # 支持伪终端
    def pty_options(hash)
      @pty_options = @pty_options.merge hash
    end

    private

    # 关闭会话
    def disconnect
      disconnect_cli
      # if disconnect does not disconnect us, give up after timeout
      Timeout.timeout(Oxidized.config.timeout) { @ssh.loop }
    rescue Errno::ECONNRESET, Net::SSH::Disconnect, IOError
      # Ignored
    ensure
      @log.close if Oxidized.config.input.debug?
      unless @ssh.closed?
        begin
          @ssh.close
        rescue
          true
        end
      end
    end

    # 新建 SSH 会话 -- channel
    def shell_open(ssh)
      @ses = ssh.open_channel do |ch|
        ch.on_data do |_ch, data|
          # 如果启用 debug 将回显写入日志文件
          if Oxidized.config.input.debug?
            @log.print data
            @log.flush
          end
          @output << data

          # 动态交互式执行脚本 -- 根据回显动态执行策略
          # lib/oxidized/model/model.rb -- 198 行
          @output = @node.model.expects @output
        end

        # 异步打开一个伪终端
        ch.request_pty(@pty_options) do |_ch, success_pty|
          raise NoShell, "Can't get PTY" unless success_pty

          ch.send_channel_request "shell" do |_ch, success_shell|
            raise NoShell, "Can't get shell" unless success_shell
          end
        end
      end
    end

    # 执行状态
    def exec(state = nil)
      return nil if vars(:ssh_no_exec)

      state.nil? ? @exec : (@exec = state)
    end

    # 交互式执行脚本
    def cmd_shell(cmd, expect_re)
      @output = ""
      @ses.send_data cmd + "\n"
      @ses.process
      expect expect_re if expect_re
      @output
    end

    # 交互式捕捉运行时回显
    def expect(*regexps)
      regexps = [regexps].flatten
      Oxidized.logger.debug "lib/oxidized/input/ssh.rb: expecting #{regexps.inspect} at #{node.name}"

      # 设定计时器 -- 有效时间内完成正则捕捉
      # 如果不匹配则抛出超时异常
      Timeout.timeout(Oxidized.config.timeout) do
        @ssh.loop(0.3) do
          sleep 0.5
          match = regexps.find { |regexp| @output.match(regexp) }
          return match if match

          true
        end
      end
    end

    # 生成 SSH 会话参数
    def make_ssh_opts
      secure = Oxidized.config.input.ssh.secure?
      ssh_opts = {
        number_of_password_prompts: 0,
        keepalive: vars(:ssh_no_keepalive) ? false : true,
        verify_host_key: secure ? :always : :never,
        append_all_supported_algorithms: true,
        password: @node.auth[:password],
        timeout: Oxidized.config.timeout,
        port: (vars(:ssh_port) || 22).to_i,
        forward_agent: false
      }

      auth_methods = vars(:auth_methods) || %w[none publickey password]
      ssh_opts[:auth_methods] = auth_methods
      Oxidized.logger.debug "AUTH METHODS::#{auth_methods.inspect}"

      ssh_opts[:proxy] = make_ssh_proxy_command(vars(:ssh_proxy), vars(:ssh_proxy_port), secure) if vars(:ssh_proxy)

      ssh_opts[:keys] = [vars(:ssh_keys)].flatten if vars(:ssh_keys)
      ssh_opts[:kex] = vars(:ssh_kex).split(/,\s*/) if vars(:ssh_kex)
      ssh_opts[:encryption] = vars(:ssh_encryption).split(/,\s*/) if vars(:ssh_encryption)
      ssh_opts[:host_key] = vars(:ssh_host_key).split(/,\s*/) if vars(:ssh_host_key)
      ssh_opts[:hmac] = vars(:ssh_hmac).split(/,\s*/) if vars(:ssh_hmac)

      if Oxidized.config.input.debug?
        ssh_opts[:logger] = Oxidized.logger
        ssh_opts[:verbose] = Logger::DEBUG
      end

      ssh_opts
    end

    # SSH 代理脚本
    def make_ssh_proxy_command(proxy_host, proxy_port, secure)
      return nil unless !proxy_host.nil? && !proxy_host.empty?

      proxy_command = "ssh "
      proxy_command += "-o StrictHostKeyChecking=no " unless secure
      proxy_command += "-p #{proxy_port} " if proxy_port
      proxy_command += "#{proxy_host} -W [%h]:%p"
      Net::SSH::Proxy::Command.new(proxy_command)
    end
  end
end
