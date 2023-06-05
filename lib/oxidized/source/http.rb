module Oxidized
  class HTTP < Source
    def initialize
      super
      @cfg = Oxidized.config.source.http
    end

    # 自动装配
    def setup
      return unless @cfg.url.empty?

      Oxidized.asetus.user.source.http.url = "http://www.example.com/devices"
      Oxidized.asetus.user.source.http.user = "username"
      Oxidized.asetus.user.source.http.pass = "password"
      Oxidized.asetus.user.source.http.map.name = 0
      Oxidized.asetus.user.source.http.map.model = 1
      Oxidized.asetus.save :user
      raise NoConfig, "no source http url config, edit ~/.config/oxidized/config"
    end

    # 加载依赖
    require "net/http"
    require "net/https"
    require "uri"
    require "json"

    # 自动加载数据
    def load(node_want = nil)
      nodes = []
      # 发起请求并解析响应
      data = JSON.parse(read_http(node_want))
      # FIXME: 作用不明确
      data = string_navigate(data, @cfg.hosts_location) if @cfg.hosts_location?
      data.each do |node|
        next if node.empty?

        # map node parameters
        keys = {}
        @cfg.map.each do |key, want_position|
          keys[key.to_sym] = node_var_interpolate string_navigate(node, want_position)
        end
        # 设置设备分组和模型
        keys[:model] = map_model keys[:model] if keys.has_key? :model
        keys[:group] = map_group keys[:group] if keys.has_key? :group

        # map node specific vars
        vars = {}
        @cfg.vars_map.each do |key, want_position|
          vars[key.to_sym] = node_var_interpolate string_navigate(node, want_position)
        end
        keys[:vars] = vars unless vars.empty?

        # 数据压入数组
        nodes << keys
      end
      nodes
    end

    private

    def string_navigate(object, wants)
      wants = wants.split(".").map do |want|
        # 根据正则切割字串，输出匹配前、命中正则和匹配后的字串
        head, match, _tail = want.partition(/\[\d+\]/)
        match.empty? ? head : [head, match[1..-2].to_i]
      end
      wants.flatten.each do |want|
        object = object[want] if object.respond_to? :each
      end
      object
    end

    # 发起 http 请求并读取 body
    def read_http(node_want)
      uri = URI.parse(@cfg.url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true if uri.scheme == "https"
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE unless @cfg.secure

      # Add read_timeout to handle case of big list of nodes (default value is 60 seconds)
      http.read_timeout = Integer(@cfg.read_timeout) if @cfg.has_key? "read_timeout"

      # map headers
      headers = {}
      @cfg.headers.each do |header, value|
        headers[header] = value
      end

      req_uri = uri.request_uri
      # 查询特定节点配置清单
      req_uri = "#{req_uri}/#{node_want}" if node_want

      # 实例化 http 对象 -- get 请求
      request = Net::HTTP::Get.new(req_uri, headers)
      # 设置 http 头部认证
      request.basic_auth(@cfg.user, @cfg.pass) if @cfg.user? && @cfg.pass?
      http.request(request).body
    end
  end
end
