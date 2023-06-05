module Oxidized
  class SQL < Source
    # 尝试加载 sequel 模块
    begin
      require "sequel"
    rescue LoadError
      raise OxidizedError, "sequel not found: sudo gem install sequel"
    end

    # 自动装配
    def setup
      return unless @cfg.empty?

      Oxidized.asetus.user.source.sql.adapter   = "sqlite"
      Oxidized.asetus.user.source.sql.database  = File.join(Config::ROOT_DIR, "sqlite.db")
      Oxidized.asetus.user.source.sql.table     = "devices"
      Oxidized.asetus.user.source.sql.map.name  = "name"
      Oxidized.asetus.user.source.sql.map.model = "rancid"
      Oxidized.asetus.save :user
      raise NoConfig, "no source sql config, edit ~/.config/oxidized/config"
    end

    # 加载数据库清单
    def load(node_want = nil)
      nodes = []

      # 连接数据库并查询清单
      db    = connect
      query = db[@cfg.table.to_sym]
      query = query.with_sql(@cfg.query) if @cfg.query?
      # 过滤特定节点信息
      query = query.where(@cfg.map.name.to_sym => node_want) if node_want

      # 遍历已有清单
      query.each do |node|
        # map node parameters
        keys = {}
        @cfg.map.each { |key, sql_column| keys[key.to_sym] = node_var_interpolate node[sql_column.to_sym] }
        # 设置设备属组和模型
        keys[:model] = map_model keys[:model] if keys.has_key? :model
        keys[:group] = map_group keys[:group] if keys.has_key? :group

        # map node specific vars
        vars = {}
        @cfg.vars_map.each do |key, sql_column|
          vars[key.to_sym] = node_var_interpolate node[sql_column.to_sym]
        end
        keys[:vars] = vars unless vars.empty?

        nodes << keys
      end
      db.disconnect

      nodes
    end

    private

    # 实例化函数
    def initialize
      super
      @cfg = Oxidized.config.source.sql
    end

    # 数据库建联参数
    def connect
      options = {
        adapter:  @cfg.adapter,
        host:     @cfg.host?,
        user:     @cfg.user?,
        password: @cfg.password?,
        database: @cfg.database,
        ssl_mode: @cfg.ssl_mode?
      }
      if @cfg.with_ssl?
        options.merge!(sslca:   @cfg.ssl_ca?,
                       sslcert: @cfg.ssl_cert?,
                       sslkey:  @cfg.ssl_key?)
      end
      Sequel.connect(options)
    rescue Sequel::AdapterNotFound => error
      raise OxidizedError, "SQL adapter gem not installed: " + error.message
    end
  end
end
