module Oxidized
  require "stringio"
  require_relative "cli"

  # 尝试加载 tftp 模块
  begin
    require "net/tftp"
  rescue LoadError
    raise OxidizedError, "net/tftp not found: sudo gem install net-tftp"
  end

  class TFTP < Input
    include Input::CLI

    # TFTP utilizes UDP, there is not a connection. We simply specify an IP and send/receive data.
    def connect(node)
      @node = node
      # tftp 相关配置回调
      @node.model.cfg["tftp"].each { |cb| instance_exec(&cb) }
      @log = File.open(Oxidized::Config::LOG_DIR + "/#{@node.ip}_tftp.log", "w") if Oxidized.config.input.debug?
      @tftp = Net::TFTP.new @node.ip
    end

    # 上传文件
    def cmd(file)
      Oxidized.logger.debug "TFTP: #{file} @ #{@node.name}"
      config = StringIO.new
      @tftp.getbinary file, config
      config.rewind
      config.read
    end

    private

    # 关闭会话
    def disconnect
      # TFTP uses UDP, there is no connection to close
      true
    ensure
      @log.close if Oxidized.config.input.debug?
    end
  end
end
