module Oxidized
  class CLI
    require 'slop'
    require 'oxidized'
    require 'English'

    def run
      check_pid
      Process.daemon if @opts[:daemonize]
      write_pid
      begin
        Oxidized.logger.info "Oxidized starting, running as pid #{$PROCESS_ID}"
        Oxidized.new
      rescue StandardError => error
        crash error
        raise
      end
    end

    private

    # 实例化函数
    def initialize
      _args, @opts = parse_opts

      Config.load(@opts)
      Oxidized.setup_logger

      @pidfile = File.expand_path(Oxidized.config.pid)
    end

    def crash(error)
      Oxidized.logger.fatal "Oxidized crashed, crash_file written in #{Config::CRASH_DIR}"
      File.open Config::CRASH_DIR, 'w' do |file|
        file.puts '-' * 50
        file.puts Time.now.utc + (8 * 60 * 60)
        file.puts error.message + ' [' + error.class.to_s + ']'
        file.puts '-' * 50
        file.puts error.backtrace
        file.puts '-' * 50
      end
    end

    def parse_opts
      opts = Slop.parse do |opt|
        opt.on '-d', '--debug', 'turn on debugging'
        opt.on '--daemonize', 'Daemonize/fork the process'
        # 项目使用说明
        opt.on '-h', '--help', 'show usage' do
          puts opt
          exit
        end
        # 项目详细配置
        opt.on '-a', '--show-exhaustive-config', 'output entire configuration, including defaults' do
          asetus = Config.load
          puts asetus.to_yaml asetus.cfg
          Kernel.exit
        end
        # 查看项目版本
        opt.on '-v', '--version', 'show version' do
          puts Oxidized::VERSION_FULL
          Kernel.exit
        end
      end
      [opts.arguments, opts]
    end

    attr_reader :pidfile

    def pidfile?
      !!pidfile
    end

    def write_pid
      return unless pidfile?

      begin
        File.open(pidfile, ::File::CREAT | ::File::EXCL | ::File::WRONLY) { |f| f.write(Process.pid.to_s) }
        at_exit { FileUtils.rm_f(pidfile) }
      rescue Errno::EEXIST
        check_pid
        retry
      end
    end

    def check_pid
      return unless pidfile?

      case pid_status(pidfile)
      when :running, :not_owned
        puts "A server is already running. Check #{pidfile}"
        exit(1)
      when :dead
        File.delete(pidfile)
      else
        puts "Something wrong!"
      end
    end

    def pid_status(pidfile)
      return :exited unless File.exist?(pidfile)

      pid = ::File.read(pidfile).to_i
      return :dead if pid.zero?

      Process.kill(0, pid)
      :running
    rescue Errno::ESRCH
      :dead
    rescue Errno::EPERM
      :not_owned
    end
  end
end
