module Oxidized
  require "asetus"

  class << self
    attr_accessor :mgr, :hooks
  end

  class NoConfig < OxidizedError; end

  class InvalidConfig < OxidizedError; end

  class Config
    ROOT_DIR   = ENV["OXIDIZED_HOME"] || File.join(Dir.home, ".config", "oxidized")
    CRASH_DIR  = File.join(ENV["OXIDIZED_LOGS"] || ROOT_DIR, "crash")
    LOG_DIR    = File.join(ENV["OXIDIZED_LOGS"] || ROOT_DIR, "logs")
    INPUT_DIR  = File.join(DIRECTORY, %w[lib oxidized input])
    OUTPUT_DIR = File.join(DIRECTORY, %w[lib oxidized output])
    MODEL_DIR  = File.join(DIRECTORY, %w[lib oxidized model])
    SOURCE_DIR = File.join(DIRECTORY, %w[lib oxidized source])
    HOOK_DIR   = File.join(DIRECTORY, %w[lib oxidized hook])
    SLEEP_TIME = 1

    # 类方法 -- 自动装配设置缺省值，位置参数并设定默认值
    # rubocop:disable Metrics/AbcSize
    # rubocop:disable Metrics/MethodLength
    def self.load(cmd_opts = {})
      # 实例化 asetus 对象
      asetus = Asetus.new(name: "oxidized", load: false, key_to_s: true, usrdir: Oxidized::Config::ROOT_DIR)
      # 设定 asetus
      Oxidized.asetus = asetus

      # 设定缺省值
      asetus.default.username        = "username"
      asetus.default.password        = "password"
      asetus.default.model           = "ios"
      asetus.default.resolve_dns     = true # if false, don't resolve DNS to IP
      asetus.default.interval        = 28_800
      asetus.default.use_syslog      = false
      asetus.default.remove_secret   = true
      asetus.default.debug           = false
      asetus.default.threads         = 30
      asetus.default.use_max_threads = false
      asetus.default.timeout         = 30
      asetus.default.retries         = 3
      asetus.default.prompt          = /^([\w.@-]+[#>]\s?)$/
      asetus.default.rest            = "127.0.0.1:8888" # or false to disable
      asetus.default.next_adds_job   = true # if true, /next adds job, so device is fetched immmeiately
      asetus.default.vars            = {} # could be 'enable'=>'enablePW'
      asetus.default.groups          = {} # group level configuration
      asetus.default.group_map       = {} # map aliases of groups to names
      asetus.default.models          = {} # model level configuration
      asetus.default.pid             = File.join(Oxidized::Config::ROOT_DIR, "pid")
      # 异常退出相关参数
      asetus.default.crash.directory = File.join(Oxidized::Config::ROOT_DIR, "crashes")
      asetus.default.crash.hostnames = true

      asetus.default.stats.history_size = 10
      asetus.default.input.default      = "ssh, telnet"
      asetus.default.input.debug        = false # or String for session log file
      asetus.default.input.ssh.secure   = false # complain about changed certs
      asetus.default.input.ftp.passive  = true # ftp passive mode
      asetus.default.input.utf8_encoded = true # configuration is utf8 encoded or ascii-8bit

      asetus.default.output.default = "git" # file, git
      asetus.default.source.default = "csv" # csv, sql, http

      asetus.default.model_map = {
        "juniper"   => "junos",
        "cisco"     => "ios",
        "PANOS"     => "panos",
        "Comware"   => "h3c",
        "Hillstone" => "stoneos",
        "Radware"   => "alteonos",
        "ros"       => "ios"
      }

      begin
        asetus.load # load system+user configs, merge to Config.cfg
      rescue StandardError => error
        raise InvalidConfig, "Error loading config: #{error.message}"
      end

      raise NoConfig, "edit ~/.config/oxidized/config" if asetus.create

      # override if command line flag given
      asetus.cfg.debug = cmd_opts[:debug] if cmd_opts[:debug]

      # 返回 asetus
      asetus
    end

    # rubocop:enable Metrics/AbcSize
    # rubocop:enable Metrics/MethodLength
  end
end
