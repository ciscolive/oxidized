require "fileutils"
require "refinements"

module Oxidized
  class OxidizedError < StandardError; end

  # 获取项目路径
  DIRECTORY = File.expand_path(File.join(File.dirname(__FILE__), "../"))

  # 加载相关模块
  require "oxidized/version"
  require "oxidized/config"
  require "oxidized/config/vars"
  require "oxidized/worker"
  require "oxidized/nodes"
  require "oxidized/manager"
  require "oxidized/hook"
  require "oxidized/core"

  # 模块的单例类方法
  class << self
    def config
      asetus.cfg
    end

    # 查询或设置 asetus
    def asetus
      @@asetus
    end

    def asetus=(val)
      @@asetus = val
    end

    # 查询或设置 logger
    def logger
      @@logger
    end

    def logger=(val)
      @@logger = val
    end

    def setup_logger
      # 自动创建日志文件夹
      FileUtils.mkdir_p(Config::LOG_DIR) unless File.directory?(Config::LOG_DIR)

      self.logger  = if config.has_key?("use_syslog") && config.use_syslog
                       require "syslog/logger"
                       Syslog::Logger.new("oxidized")
                     else
                       require "logger"
                       if config.has_key?("log")
                         Logger.new(File.expand_path(config.log))
                       else
                         Logger.new(STDERR)
                       end
                     end

      # 如果项目配置 debug 模式，自动设置日志级别为 info
      logger.level = Logger::INFO unless config.debug
    end
  end
end
