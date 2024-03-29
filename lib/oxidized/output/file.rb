module Oxidized
  class OxidizedFile < Output
    require "fileutils"

    attr_reader :commitref

    # 实例化函数
    def initialize
      super
      @cfg = Oxidized.config.output.file
    end

    # 自动加载
    def setup
      return unless @cfg.empty?

      Oxidized.asetus.user.output.file.directory = File.join(Config::ROOT_DIR, "backup_config")
      Oxidized.asetus.save :user
      raise NoConfig, "no output file config, edit ~/.config/oxidized/config"
    end

    # 将节点运行配置存储到本地文件夹
    def store(node, outputs, opt = {})
      dir = File.expand_path(@cfg.directory)
      dir = File.join(File.dirname(dir), opt[:group]) if opt[:group]
      FileUtils.mkdir_p(dir)
      file = File.join(dir, node)
      File.write(file, outputs.to_cfg)
      @commitref = file
    end

    # 本地文件夹读取配置
    def fetch(node, group)
      dir = File.expand_path(@cfg.directory)
      node_name = node.name

      if group # group is explicitly defined by user
        dir = File.join(File.dirname(dir), group)
        File.read(File.join(dir, node_name))
      elsif File.exist?(File.join(dir, node_name)) # node configuration file is stored on base directory
        File.read(File.join(dir, node_name))
      else
        path = Dir.glob(File.join(File.dirname(dir), "**", node_name)).first # fetch node in all groups
        File.read(path) if path
      end
    rescue Errno::ENOENT
      nil
    end

    def version(_node, _group)
      # not supported
      []
    end

    def get_version(_node, _group, _oid)
      "not supported"
    end
  end
end
