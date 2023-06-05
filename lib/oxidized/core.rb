module Oxidized
  # 模块的单类实例 -- self 指定为模块本身
  # new 是类方法，initialize 实例方法
  class << self
    def new(*args)
      Core.new args
    end
  end

  class Core
    class NoNodesFound < OxidizedError; end

    # 实例化函数
    def initialize(_args)
      # 实例化 mgr hooks
      Oxidized.mgr = Manager.new
      Oxidized.hooks = HookManager.from_config(Oxidized.config)
      # 实例化并加载节点清单
      nodes = Nodes.new
      raise NoNodesFound, "source returns no usable nodes" if nodes.size.zero?

      # 启动节点配置备份调度器
      @worker = Worker.new(nodes)
      # HUP 信号通常用于重启或重新加载配置文件。通过使用 trap 方法，你可以捕获和处理指定的信号，执行相应的操作
      trap("HUP") { nodes.load }

      if Oxidized.config.rest?
        begin
          require "oxidized/web"
        rescue LoadError
          raise OxidizedError, 'oxidized-web not found: sudo gem install oxidized-web - \
          or disable web support by setting "rest: false" in your configuration'
        end
        # 启动 web 端
        @rest = API::Web.new nodes, Oxidized.config.rest
        @rest.run
      end
      run
    end

    private

    def run
      Oxidized.logger.debug "lib/oxidized/core.rb: Starting the worker..."
      @worker.work while sleep Config::SLEEP_TIME
    end
  end
end
