module Oxidized
  require "oxidized/input/cli"
  require "net/http"
  require "json"

  class HTTP < Input
    include Input::CLI

    # 新建会话
    def connect(node)
      @node = node
      @secure = false
      @username = nil
      @password = nil
      @headers = {}
      @log = File.open(Oxidized::Config::LOG_DIR + "/#{@node.ip}_http.log", "w") if Oxidized.config.input.debug?
      @node.model.cfg["http"].each { |cb| instance_exec(&cb) }

      return true unless @main_page && defined?(login)

      begin
        require "mechanize"
      rescue LoadError
        raise OxidizedError, "mechanize not found: sudo gem install mechanize"
      end

      # 实例化 Mechanize 对象
      @m = Mechanize.new
      url = URI::HTTP.build host: @node.ip, path: @main_page
      @m_page = @m.get(url.to_s)
      login
    end

    # 执行脚本
    def cmd(callback_or_string)
      return cmd_cb callback_or_string if callback_or_string.is_a?(Proc)

      cmd_str callback_or_string
    end

    # cmd 回调函数
    def cmd_cb(callback)
      instance_exec(&callback)
    end

    # 请求 http 接口
    def cmd_str(string)
      path = string % {password: @node.auth[:password]}
      get_http path
    end

    private

    # 发起 HTTP 请求
    def get_http(path)
      schema = @secure ? "https://" : "http://"
      uri = URI("#{schema}#{@node.ip}#{path}")
      req = Net::HTTP::Get.new(uri)
      req.basic_auth @username, @password unless @username.nil?
      @headers.each do |header, value|
        req.add_field(header, value)
      end
      ssl_verify = Oxidized.config.input.http.ssl_verify? ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", verify_mode: ssl_verify) do |http|
        http.request(req)
      end
      res.body
    end

    # 打印日志
    def log(str)
      @log&.write(str)
    end

    # 关闭会话
    def disconnect
      @log.close if Oxidized.config.input.debug?
    end
  end
end
